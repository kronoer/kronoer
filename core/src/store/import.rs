//! Import: an Archive, as `spec/export-format.md` defines it, read back into the store, adding
//! only what this device does not have.
//!
//! A Book or an Entry whose ID the store already has is skipped, wherever it is, the Trash
//! included: nothing is ever overwritten. The new Entries of a Book in the Trash are skipped too,
//! until the user restores it. What is added is sealed with this device's keys like anything new,
//! keeping its IDs and times; its stars and locks are sealed again as new records.
//!
//! The whole Archive is checked before anything changes. The Images to add are then prepared (their
//! metadata stripped, a thumbnail made, both sealed and written to their files), and everything is
//! added in one transaction: all of it or nothing. The store is only locked to look up what it has
//! and for that last transaction, not while the Images are prepared.

use std::collections::{HashMap, HashSet};
use std::io::{self, Cursor, Read, Seek};

use image::codecs::jpeg::JpegEncoder;
use image::{ImageFormat, ImageReader, Limits};
use rusqlite::{Connection, params};
use serde::Deserialize;
use zip::ZipArchive;
use zip::result::ZipError;

use super::export::parse_utc_time;
use super::files::ImageFiles;
use super::{
    ARCHIVE_DATA_FILE, ARCHIVE_FORMAT, ARCHIVE_FORMAT_VERSION, Change, Inner, Result, Store,
    StoreError, book_key, current_key_version, in_book_trash, index_entry, is_locked, lock, now,
    open_stored_book_record, store_book_lock, store_star,
};
use crate::{
    BookKey, BookRecord, Entry, EntryDate, Id, ImageRef, LockRecord, SealedImage, StarRecord,
    seal_book_record, seal_entry, seal_image, wrap_book_key,
};

/// The longest side an Image in an Archive may have, in pixels: the most Kronoer stores.
pub const MAX_IMAGE_SIDE: u32 = 2048;

/// The longest side of the thumbnail an Import makes for each Image, in pixels.
pub const THUMBNAIL_SIDE: u32 = 512;

const THUMBNAIL_QUALITY: u8 = 80;

/// The largest `kronoer.json` an Import reads, in bytes.
const MAX_DATA_LEN: u64 = 256 * 1024 * 1024;

/// The largest Image file an Import reads, in bytes.
const MAX_IMAGE_LEN: u64 = 32 * 1024 * 1024;

/// What an Archive holds.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct ArchiveCounts {
    /// How many Books, Locked Books included.
    pub book_count: u32,
    /// How many Entries.
    pub entry_count: u32,
    /// How many Images, Covers included.
    pub image_count: u32,
}

/// How far an Import has come.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ImportProgress {
    /// The Archive is being checked.
    Checking,
    /// The Archive is whole, and what this device lacks is being added.
    Adding {
        /// What the Archive holds.
        archive: ArchiveCounts,
        /// How many Books the Import will add.
        new_book_count: u32,
        /// How many Entries the Import will add.
        new_entry_count: u32,
        /// How many of those Entries are ready, with their Images.
        done: u32,
    },
}

/// What an Import did.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ImportSummary {
    /// What the Archive holds.
    pub archive: ArchiveCounts,
    /// Every Book of the Archive, in its order, with what was added to it.
    pub books: Vec<ImportedBook>,
}

impl ImportSummary {
    /// How many Books the Import added.
    pub fn added_book_count(&self) -> u32 {
        self.books.iter().filter(|book| book.added).count() as u32
    }

    /// How many Entries the Import added.
    pub fn added_entry_count(&self) -> u32 {
        self.books.iter().map(|book| book.added_entry_count).sum()
    }

    /// How many Entries were skipped because this device already has them.
    pub fn existing_entry_count(&self) -> u32 {
        self.books
            .iter()
            .map(|book| book.existing_entry_count)
            .sum()
    }

    /// How many new Entries were skipped because their Book is in the Trash.
    pub fn trashed_entry_count(&self) -> u32 {
        self.books.iter().map(|book| book.trashed_entry_count).sum()
    }
}

/// One Book of an Archive, after an Import.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ImportedBook {
    /// The Book's ID.
    pub id: Id,
    /// Its name on this device: the Archive's for a Book the Import added.
    pub name: String,
    /// Whether the Import added the Book itself.
    pub added: bool,
    /// Whether the Book is a Locked Book on this device.
    pub locked: bool,
    /// Whether the Book is in this device's Trash.
    pub in_trash: bool,
    /// How many of its Entries the Import added.
    pub added_entry_count: u32,
    /// How many of its Entries this device already had.
    pub existing_entry_count: u32,
    /// How many of its Entries were new but skipped, because the Book is in the Trash.
    pub trashed_entry_count: u32,
}

/// The head of `kronoer.json`, read first so a newer format is told from a damaged file.
#[derive(Deserialize)]
struct Head {
    format: String,
    format_version: u64,
}

/// `kronoer.json` as written; unknown keys are ignored.
#[derive(Deserialize)]
struct RawArchive {
    exported_at: String,
    books: Vec<RawBook>,
    locked_book_ids: Vec<String>,
    starred_entry_ids: Vec<String>,
    entries: Vec<RawEntry>,
}

#[derive(Deserialize)]
struct RawBook {
    id: String,
    name: String,
    description: String,
    cover_image_id: Option<String>,
}

#[derive(Deserialize)]
struct RawEntry {
    id: String,
    book_id: String,
    entry_date: String,
    text: String,
    image_ids: Vec<String>,
    created_at: String,
    updated_at: String,
}

/// An Archive that passed every check.
struct Archive {
    exported_at: i64,
    books: Vec<ArchivedBook>,
    locked: HashSet<Id>,
    starred: HashSet<Id>,
    entries: Vec<ArchivedEntry>,
    image_count: u32,
}

struct ArchivedBook {
    id: Id,
    name: String,
    description: String,
    cover: Option<Id>,
}

struct ArchivedEntry {
    id: Id,
    book_id: Id,
    date: EntryDate,
    text: String,
    images: Vec<Id>,
    created_at: i64,
    updated_at: i64,
}

/// What this device has of one Book of the Archive.
#[derive(Clone, PartialEq, Eq, Debug)]
enum BookState {
    /// It does not have the Book.
    New,
    /// It has the Book.
    Present {
        name: String,
        locked: bool,
        in_trash: bool,
    },
}

/// What becomes of one Entry of the Archive.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Fate {
    /// It is added.
    Add,
    /// This device already has it.
    Exists,
    /// It is new, but its Book is in the Trash.
    BookInTrash,
}

/// What this device has of an Archive, by Book and by Entry, in the Archive's order.
struct Plan {
    books: Vec<BookState>,
    entries: Vec<Fate>,
}

/// Image files written for an Import, deleted when it is dropped: all of them if the Import does
/// not commit, the ones it did not use if it does.
struct Written<'a> {
    files: &'a ImageFiles,
    ids: Vec<Id>,
}

impl Drop for Written<'_> {
    fn drop(&mut self) {
        for &id in &self.ids {
            self.files.remove(id);
        }
    }
}

impl Store {
    /// Adds to the store what the Archive `input` has and the store lacks, in one transaction.
    ///
    /// A Book or Entry the store already has is skipped, in the Trash too; a newer `updated_at`
    /// does not matter, so importing the same Archive again adds nothing. The new Entries of a
    /// Book in the Trash are skipped. A Book the Import adds is locked if the Archive says so, and
    /// an Entry it adds starred; nothing the store had changes.
    ///
    /// `progress` is called once before the Archive is checked, then after each new Entry is
    /// ready; returning `false` stops the Import with [`StoreError::Cancelled`], changing nothing.
    ///
    /// Fails, changing nothing, with [`StoreError::ArchiveDamaged`] if the file is not a whole
    /// Kronoer Archive, [`StoreError::ArchiveNewer`] if its format is newer than this core reads,
    /// [`StoreError::ArchiveImage`] if an Image to add does not open as a JPEG or is larger than
    /// [`MAX_IMAGE_SIDE`] on a side, and [`StoreError::ArchiveRead`] if the file cannot be read.
    pub fn import_archive<R: Read + Seek>(
        &self,
        input: R,
        mut progress: impl FnMut(ImportProgress) -> bool,
    ) -> Result<ImportSummary> {
        let mut step = |now: ImportProgress| {
            if progress(now) {
                Ok(())
            } else {
                Err(StoreError::Cancelled)
            }
        };
        step(ImportProgress::Checking)?;

        let mut zip = ZipArchive::new(input).map_err(zip_error)?;
        let archive = read_archive(&mut zip)?;
        let counts = ArchiveCounts {
            book_count: archive.books.len() as u32,
            entry_count: archive.entries.len() as u32,
            image_count: archive.image_count,
        };

        let plan = {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            plan(conn, keyring, &archive)?
        };
        let new_book_count = count(&plan.books, |state| *state == BookState::New);
        let new_entry_count = count(&plan.entries, |fate| *fate == Fate::Add);
        let mut done = 0;
        let mut adding = |done: u32| {
            step(ImportProgress::Adding {
                archive: counts,
                new_book_count,
                new_entry_count,
                done,
            })
        };
        adding(done)?;

        // The slow part, with the store free: every Image to add, prepared and in its files.
        let mut written = Written {
            files: &self.files,
            ids: Vec::new(),
        };
        let mut covers = HashMap::new();
        for (book, state) in archive.books.iter().zip(&plan.books) {
            if let (Some(cover), BookState::New) = (book.cover, state) {
                covers.insert(book.id, self.add_image(&mut zip, cover, &mut written)?);
            }
        }
        let mut images: Vec<Option<Vec<ImageRef>>> = Vec::with_capacity(archive.entries.len());
        for (entry, fate) in archive.entries.iter().zip(&plan.entries) {
            if *fate != Fate::Add {
                images.push(None);
                continue;
            }
            let refs = entry
                .images
                .iter()
                .map(|&id| self.add_image(&mut zip, id, &mut written))
                .collect::<Result<Vec<_>>>()?;
            images.push(Some(refs));
            done += 1;
            adding(done)?;
        }
        let mut keys = HashMap::new();
        for (book, state) in archive.books.iter().zip(&plan.books) {
            if *state == BookState::New {
                keys.insert(book.id, BookKey::generate(book.id)?);
            }
        }

        let (summary, used) = self.commit_import(&archive, &plan, counts, covers, images, keys)?;
        // The files of the Images the commit used are the store's now.
        written.ids.retain(|id| !used.contains(id));

        for book in &summary.books {
            if book.added || book.added_entry_count > 0 {
                self.notify(Change {
                    book_id: book.id,
                    entry_id: None,
                });
            }
        }
        Ok(summary)
    }

    /// Reads one Image of the Archive, prepares it, and writes its files.
    fn add_image<R: Read + Seek>(
        &self,
        zip: &mut ZipArchive<R>,
        id: Id,
        written: &mut Written<'_>,
    ) -> Result<ImageRef> {
        let file = zip.by_name(&image_name(id)).map_err(zip_error)?;
        if file.size() > MAX_IMAGE_LEN {
            return Err(StoreError::ArchiveImage("an Image file is too large"));
        }
        let bytes = read_limited(file, MAX_IMAGE_LEN)?;
        let sealed = prepare_image(&bytes)?;
        self.write_images(std::slice::from_ref(&sealed))?;
        written.ids.push(sealed.image.id());
        Ok(sealed.image)
    }

    /// Adds, in one transaction, what is still missing when it runs: the plan is made again in it,
    /// and only what both plans add is added. Returns the summary and the Images it used.
    fn commit_import(
        &self,
        archive: &Archive,
        prepared: &Plan,
        counts: ArchiveCounts,
        mut covers: HashMap<Id, ImageRef>,
        images: Vec<Option<Vec<ImageRef>>>,
        keys: HashMap<Id, BookKey>,
    ) -> Result<(ImportSummary, HashSet<Id>)> {
        let now = now();
        let mut inner = lock(&self.inner);
        let Inner { conn, keyring } = &mut *inner;
        let current = plan(conn, keyring, archive)?;
        let tx = conn.transaction()?;

        let mut summary = ImportSummary {
            archive: counts,
            books: Vec::with_capacity(archive.books.len()),
        };
        let mut used = HashSet::new();
        let mut book_index = HashMap::with_capacity(archive.books.len());
        for (i, book) in archive.books.iter().enumerate() {
            let added = prepared.books[i] == BookState::New && current.books[i] == BookState::New;
            let imported = match &current.books[i] {
                _ if added => {
                    let key = &keys[&book.id];
                    let record = BookRecord {
                        id: book.id,
                        name: book.name.clone(),
                        description: book.description.clone(),
                        cover: covers.remove(&book.id),
                    };
                    used.extend(record.cover.as_ref().map(ImageRef::id));
                    // A new Book is as active as the latest of its Entries, or the Export.
                    let last_activity = archive
                        .entries
                        .iter()
                        .zip(&prepared.entries)
                        .filter(|(entry, fate)| entry.book_id == book.id && **fate == Fate::Add)
                        .map(|(entry, _)| entry.updated_at)
                        .max()
                        .unwrap_or(archive.exported_at);
                    tx.execute(
                        "INSERT INTO book (id, name, description, cover_id, last_activity_at,
                             record, record_key_version)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                        params![
                            book.id,
                            record.name,
                            record.description,
                            record.cover.as_ref().map(ImageRef::id),
                            last_activity,
                            seal_book_record(&record, key)?,
                            key.version()
                        ],
                    )?;
                    tx.execute(
                        "INSERT INTO book_key (book_id, version, wrapped) VALUES (?1, ?2, ?3)",
                        params![
                            book.id,
                            key.version(),
                            wrap_book_key(key, keyring.master())?
                        ],
                    )?;
                    let locked = archive.locked.contains(&book.id);
                    if locked {
                        store_book_lock(
                            &tx,
                            keyring,
                            &LockRecord {
                                book_id: book.id,
                                locked_at: now,
                            },
                        )?;
                    }
                    imported_book(book.id, book.name.clone(), true, locked, false)
                }
                BookState::New => imported_book(book.id, book.name.clone(), false, false, false),
                BookState::Present {
                    name,
                    locked,
                    in_trash,
                } => imported_book(book.id, name.clone(), false, *locked, *in_trash),
            };
            book_index.insert(book.id, i);
            summary.books.push(imported);
        }

        for (i, (entry, refs)) in archive.entries.iter().zip(images).enumerate() {
            let at = book_index[&entry.book_id];
            let book = &mut summary.books[at];
            let book_there = book.added || matches!(current.books[at], BookState::Present { .. });
            match (prepared.entries[i], current.entries[i], refs) {
                (Fate::Add, Fate::Add, Some(refs)) if book_there => {
                    used.extend(refs.iter().map(ImageRef::id));
                    let added = Entry {
                        id: entry.id,
                        book_id: entry.book_id,
                        date: entry.date.clone(),
                        text: entry.text.clone(),
                        images: refs,
                        created_at: entry.created_at,
                        updated_at: entry.updated_at,
                    };
                    let (version, blob) = match keys.get(&entry.book_id) {
                        Some(key) if book.added => (key.version(), seal_entry(&added, key)?),
                        _ => {
                            let version = current_key_version(&tx, entry.book_id)?;
                            let key = book_key(&tx, keyring, entry.book_id, version)?;
                            (version, seal_entry(&added, key)?)
                        }
                    };
                    tx.execute(
                        "INSERT INTO entry
                             (id, book_id, book_key_version, entry_date, created_at, updated_at,
                              blob)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                        params![
                            added.id,
                            added.book_id,
                            version,
                            added.date,
                            added.created_at,
                            added.updated_at,
                            blob
                        ],
                    )?;
                    index_entry(&tx, tx.last_insert_rowid(), &added)?;
                    tx.execute(
                        "UPDATE book SET last_activity_at = max(last_activity_at, ?2) WHERE id = ?1",
                        params![added.book_id, added.updated_at],
                    )?;
                    if archive.starred.contains(&added.id) {
                        store_star(
                            &tx,
                            keyring,
                            &StarRecord {
                                entry_id: added.id,
                                book_id: added.book_id,
                                starred_at: now,
                            },
                        )?;
                    }
                    book.added_entry_count += 1;
                }
                (_, Fate::BookInTrash, _) => book.trashed_entry_count += 1,
                _ => book.existing_entry_count += 1,
            }
        }

        self.fail_if_asked()?;
        tx.commit()?;
        for (id, key) in keys {
            if summary.books.iter().any(|book| book.id == id && book.added) {
                keyring.insert(key);
            }
        }
        Ok((summary, used))
    }
}

fn imported_book(id: Id, name: String, added: bool, locked: bool, in_trash: bool) -> ImportedBook {
    ImportedBook {
        id,
        name,
        added,
        locked,
        in_trash,
        added_entry_count: 0,
        existing_entry_count: 0,
        trashed_entry_count: 0,
    }
}

fn count<T>(items: &[T], test: impl Fn(&T) -> bool) -> u32 {
    items.iter().filter(|item| test(item)).count() as u32
}

/// Looks up what the store has of each Book and Entry of the Archive.
fn plan(conn: &Connection, keyring: &mut super::Keyring, archive: &Archive) -> Result<Plan> {
    let mut books = Vec::with_capacity(archive.books.len());
    for book in &archive.books {
        let exists: bool = conn
            .prepare_cached("SELECT EXISTS (SELECT 1 FROM book WHERE id = ?1)")?
            .query_row([book.id], |row| row.get(0))?;
        books.push(if exists {
            BookState::Present {
                name: open_stored_book_record(conn, keyring, book.id)?.name,
                locked: is_locked(conn, book.id)?,
                in_trash: in_book_trash(conn, book.id)?,
            }
        } else {
            BookState::New
        });
    }
    let state: HashMap<Id, &BookState> = archive
        .books
        .iter()
        .zip(&books)
        .map(|(book, state)| (book.id, state))
        .collect();
    let mut entries = Vec::with_capacity(archive.entries.len());
    let mut exists = conn.prepare_cached("SELECT EXISTS (SELECT 1 FROM entry WHERE id = ?1)")?;
    for entry in &archive.entries {
        entries.push(if exists.query_row([entry.id], |row| row.get(0))? {
            Fate::Exists
        } else if let BookState::Present { in_trash: true, .. } = state[&entry.book_id] {
            Fate::BookInTrash
        } else {
            Fate::Add
        });
    }
    Ok(Plan { books, entries })
}

/// Reads `kronoer.json` and checks it, and that every Image it names has a file.
fn read_archive<R: Read + Seek>(zip: &mut ZipArchive<R>) -> Result<Archive> {
    let data = {
        let file = zip
            .by_name(ARCHIVE_DATA_FILE)
            .map_err(|error| match error {
                ZipError::FileNotFound => StoreError::ArchiveDamaged("there is no kronoer.json"),
                error => zip_error(error),
            })?;
        if file.size() > MAX_DATA_LEN {
            return Err(StoreError::ArchiveDamaged("kronoer.json is too large"));
        }
        read_limited(file, MAX_DATA_LEN)?
    };

    let head: Head = serde_json::from_slice(&data)
        .map_err(|_| StoreError::ArchiveDamaged("kronoer.json is not a Kronoer Archive"))?;
    if head.format != ARCHIVE_FORMAT {
        return Err(StoreError::ArchiveDamaged(
            "kronoer.json is not a Kronoer Archive",
        ));
    }
    if head.format_version > ARCHIVE_FORMAT_VERSION {
        return Err(StoreError::ArchiveNewer(head.format_version));
    }
    if head.format_version != ARCHIVE_FORMAT_VERSION {
        return Err(StoreError::ArchiveDamaged("an unknown format_version"));
    }
    let raw: RawArchive = serde_json::from_slice(&data)
        .map_err(|_| StoreError::ArchiveDamaged("kronoer.json does not have the format's keys"))?;
    drop(data);
    let archive = check(raw)?;

    for book in &archive.books {
        if let Some(cover) = book.cover {
            has_image(zip, cover)?;
        }
    }
    for entry in &archive.entries {
        for &image in &entry.images {
            has_image(zip, image)?;
        }
    }
    Ok(archive)
}

fn has_image<R: Read + Seek>(zip: &ZipArchive<R>, id: Id) -> Result<()> {
    zip.index_for_name(&image_name(id))
        .map(|_| ())
        .ok_or(StoreError::ArchiveDamaged("an Image has no file"))
}

fn image_name(id: Id) -> String {
    format!("images/{}.jpg", id.to_hex())
}

/// Checks every value of `kronoer.json`: its IDs, Entry dates, times, and references.
fn check(raw: RawArchive) -> Result<Archive> {
    fn damaged(reason: &'static str) -> StoreError {
        StoreError::ArchiveDamaged(reason)
    }
    let id = |text: &str| Id::from_hex(text).map_err(|_| damaged("an ID is not valid"));
    let time = |text: &str| parse_utc_time(text).ok_or(damaged("a time is not valid"));
    let mut images = HashSet::new();
    let mut image = |text: &str| -> Result<Id> {
        let image = id(text)?;
        if images.insert(image) {
            Ok(image)
        } else {
            Err(damaged("an Image is used twice"))
        }
    };

    let exported_at = time(&raw.exported_at)?;
    let mut book_ids = HashSet::with_capacity(raw.books.len());
    let mut books = Vec::with_capacity(raw.books.len());
    for book in raw.books {
        let book_id = id(&book.id)?;
        if !book_ids.insert(book_id) {
            return Err(damaged("a Book is listed twice"));
        }
        books.push(ArchivedBook {
            id: book_id,
            name: book.name,
            description: book.description,
            cover: book.cover_image_id.as_deref().map(&mut image).transpose()?,
        });
    }

    let mut entry_ids = HashSet::with_capacity(raw.entries.len());
    let mut entries = Vec::with_capacity(raw.entries.len());
    for entry in raw.entries {
        let entry_id = id(&entry.id)?;
        if !entry_ids.insert(entry_id) {
            return Err(damaged("an Entry is listed twice"));
        }
        let book_id = id(&entry.book_id)?;
        if !book_ids.contains(&book_id) {
            return Err(damaged("an Entry's Book is not in the Archive"));
        }
        entries.push(ArchivedEntry {
            id: entry_id,
            book_id,
            date: EntryDate::parse(&entry.entry_date)
                .map_err(|_| damaged("an Entry date is not valid"))?,
            text: entry.text,
            images: entry
                .image_ids
                .iter()
                .map(|text| image(text))
                .collect::<Result<_>>()?,
            created_at: time(&entry.created_at)?,
            updated_at: time(&entry.updated_at)?,
        });
    }

    let listed = |texts: &[String], known: &HashSet<Id>| -> Result<HashSet<Id>> {
        let mut ids = HashSet::with_capacity(texts.len());
        for text in texts {
            let listed = id(text)?;
            if !known.contains(&listed) {
                return Err(damaged("a locked or starred ID has no match"));
            }
            if !ids.insert(listed) {
                return Err(damaged("an ID is listed twice"));
            }
        }
        Ok(ids)
    };
    let locked = listed(&raw.locked_book_ids, &book_ids)?;
    let starred = listed(&raw.starred_entry_ids, &entry_ids)?;
    Ok(Archive {
        exported_at,
        books,
        locked,
        starred,
        entries,
        image_count: images.len() as u32,
    })
}

/// Reads at most `limit` bytes; a file that has more is damaged.
fn read_limited(file: impl Read, limit: u64) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    file.take(limit + 1)
        .read_to_end(&mut bytes)
        .map_err(read_error)?;
    if bytes.len() as u64 > limit {
        return Err(StoreError::ArchiveDamaged(
            "a file is larger than the ZIP says",
        ));
    }
    Ok(bytes)
}

/// An Image from the Archive, ready to store: its JPEG without metadata, and a thumbnail made from
/// it, sealed.
fn prepare_image(bytes: &[u8]) -> Result<SealedImage> {
    let (full, width, height) =
        strip_jpeg(bytes).ok_or(StoreError::ArchiveImage("an Image is not a JPEG"))?;
    if width == 0 || height == 0 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE {
        return Err(StoreError::ArchiveImage(
            "an Image is larger than 2048 pixels on a side",
        ));
    }
    let thumbnail = make_thumbnail(&full)?;
    Ok(seal_image(&full, &thumbnail)?)
}

/// Decodes a JPEG and encodes it again, at most [`THUMBNAIL_SIDE`] on its longest side.
fn make_thumbnail(jpeg: &[u8]) -> Result<Vec<u8>> {
    let mut reader = ImageReader::with_format(Cursor::new(jpeg), ImageFormat::Jpeg);
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_IMAGE_SIDE);
    limits.max_image_height = Some(MAX_IMAGE_SIDE);
    reader.limits(limits);
    let image = reader
        .decode()
        .map_err(|_| StoreError::ArchiveImage("an Image does not open"))?;
    let image = if image.width().max(image.height()) > THUMBNAIL_SIDE {
        image.thumbnail(THUMBNAIL_SIDE, THUMBNAIL_SIDE)
    } else {
        image
    };
    let mut out = Vec::new();
    JpegEncoder::new_with_quality(&mut out, THUMBNAIL_QUALITY)
        .encode_image(&image.into_rgb8())
        .map_err(|_| StoreError::ArchiveImage("a thumbnail could not be made"))?;
    Ok(out)
}

/// A JPEG without its metadata segments, and its width and height from its frame header; `None`
/// if it is not a JPEG whose segments hold together.
///
/// The picture is copied as it is, without decoding it again. Dropped: APP1 (EXIF and XMP), APP2
/// unless it is an ICC profile, APP3 to APP13 (IPTC among them), APP15, comments, and whatever
/// follows the end of the image. Kept: APP0 (JFIF), the ICC profile and APP14 (Adobe), which
/// say how to read the colors, and every other segment.
fn strip_jpeg(bytes: &[u8]) -> Option<(Vec<u8>, u32, u32)> {
    const SOI: u8 = 0xD8;
    const EOI: u8 = 0xD9;
    const SOS: u8 = 0xDA;
    const COM: u8 = 0xFE;
    if bytes.get(..2)? != [0xFF, SOI] {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len());
    out.extend_from_slice(&[0xFF, SOI]);
    let mut size = None;
    let mut i = 2;
    loop {
        if *bytes.get(i)? != 0xFF {
            return None;
        }
        while *bytes.get(i)? == 0xFF {
            i += 1;
        }
        let marker = bytes[i];
        i += 1;
        match marker {
            EOI => {
                out.extend_from_slice(&[0xFF, EOI]);
                let (width, height) = size?;
                return Some((out, width, height));
            }
            0x00 | SOI => return None,
            0x01 | 0xD0..=0xD7 => {
                out.extend_from_slice(&[0xFF, marker]);
                continue;
            }
            _ => {}
        }
        let len = usize::from(u16::from_be_bytes([*bytes.get(i)?, *bytes.get(i + 1)?]));
        let segment = bytes.get(i..i + len).filter(|_| len >= 2)?;
        // Frame headers: SOF0 to SOF15, but DHT (C4), JPG (C8), and DAC (CC).
        if matches!(marker, 0xC0..=0xCF) && !matches!(marker, 0xC4 | 0xC8 | 0xCC) {
            if segment.len() < 7 {
                return None;
            }
            let height = u32::from(u16::from_be_bytes([segment[3], segment[4]]));
            let width = u32::from(u16::from_be_bytes([segment[5], segment[6]]));
            size = Some((width, height));
        }
        let metadata = match marker {
            0xE2 => !segment[2..].starts_with(b"ICC_PROFILE\0"),
            0xE0 | 0xEE => false,
            0xE1..=0xEF | COM => true,
            _ => false,
        };
        if !metadata {
            out.extend_from_slice(&[0xFF, marker]);
            out.extend_from_slice(segment);
        }
        i += len;
        if marker == SOS {
            // The scan's data runs to the next marker that is not a stuffed 0xFF or a restart.
            let start = i;
            loop {
                if *bytes.get(i)? != 0xFF {
                    i += 1;
                    continue;
                }
                let mut next = i + 1;
                while *bytes.get(next)? == 0xFF {
                    next += 1;
                }
                if bytes[next] == 0x00 || (0xD0..=0xD7).contains(&bytes[next]) {
                    i = next + 1;
                    continue;
                }
                break;
            }
            out.extend_from_slice(&bytes[start..i]);
        }
    }
}

fn read_error(error: io::Error) -> StoreError {
    match error.kind() {
        // The ZIP reader says so when a file's data does not match its checksum or ends early.
        io::ErrorKind::InvalidData | io::ErrorKind::UnexpectedEof | io::ErrorKind::Other => {
            StoreError::ArchiveDamaged("a file in the ZIP is damaged")
        }
        _ => StoreError::ArchiveRead(error),
    }
}

fn zip_error(error: ZipError) -> StoreError {
    match error {
        ZipError::Io(error) => read_error(error),
        ZipError::FileNotFound => StoreError::ArchiveDamaged("a file is missing"),
        _ => StoreError::ArchiveDamaged("the file is not a whole ZIP"),
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{jpeg, jpeg_with_metadata};
    use super::*;

    #[test]
    fn strips_metadata_and_keeps_the_picture() {
        let plain = jpeg(40, 30);
        let with = jpeg_with_metadata(40, 30);
        let (stripped, width, height) = strip_jpeg(&with).unwrap();
        assert_eq!((width, height), (40, 30));
        assert_eq!(stripped, plain);
        assert!(!stripped.windows(4).any(|w| w == b"Exif"));
        let (again, ..) = strip_jpeg(&plain).unwrap();
        assert_eq!(again, plain, "a JPEG without metadata stays as it is");
    }

    #[test]
    fn refuses_what_is_not_a_whole_jpeg() {
        let plain = jpeg(40, 30);
        assert!(strip_jpeg(b"not a jpeg").is_none());
        assert!(strip_jpeg(&plain[..plain.len() / 2]).is_none());
        assert!(strip_jpeg(&plain[..2]).is_none());
    }

    #[test]
    fn makes_a_thumbnail_no_larger_than_its_side() {
        let thumbnail = make_thumbnail(&jpeg(1200, 600)).unwrap();
        let image = image::load_from_memory_with_format(&thumbnail, ImageFormat::Jpeg).unwrap();
        assert_eq!((image.width(), image.height()), (512, 256));
        let small = make_thumbnail(&jpeg(100, 80)).unwrap();
        let image = image::load_from_memory_with_format(&small, ImageFormat::Jpeg).unwrap();
        assert_eq!((image.width(), image.height()), (100, 80));
    }
}
