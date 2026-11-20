//! The device's store: Books, Entries, and Images in one SQLCipher database, plus a folder of
//! encrypted image files.
//!
//! Every Entry is kept as its sealed blob, in the same format the server stores. The plaintext
//! columns and the search index next to it only exist so lists, ordering, and search do not have
//! to open every blob; [`Store::rebuild_index`] rebuilds them from the blobs. Callers send and
//! receive plaintext content and IDs only: keys stay in the store's [`Keyring`].

mod error;
mod files;
mod keyring;
mod master_key;
mod schema;
mod search;

use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::types::{FromSql, FromSqlError, FromSqlResult, ToSql, ToSqlOutput, ValueRef};
use rusqlite::{Connection, ErrorCode, OptionalExtension, params};
use zeroize::Zeroizing;

pub use error::StoreError;
pub use keyring::Keyring;
pub use master_key::{DeviceError, MASTER_KEY_LEN, MasterKeyStore, PlatformKeyError};
pub use search::{MATCH_END, MATCH_START, match_ranges};

use self::files::ImageFiles;
use crate::{
    BookKey, BookRecord, Entry, EntryDate, Error, Id, ImageRef, ImageVariant, SealedImage, hex,
    open_book_record, open_entry, open_image, seal_book_record, seal_entry, seal_image,
    unwrap_book_key, wrap_book_key,
};

const DATABASE_FILE: &str = "kronoer.db";
const IMAGES_DIR: &str = "images";
/// Image files not referenced by any Entry are removed once they are this old. Younger ones may
/// belong to a save that has not committed yet.
const ORPHAN_AGE: Duration = Duration::from_secs(60 * 60);
/// How many words a search snippet shows around the match.
const SNIPPET_WORDS: u32 = 12;

type Result<T> = std::result::Result<T, StoreError>;

/// A Book, as lists show it.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct BookInfo {
    /// The Book's ID.
    pub id: Id,
    /// The Book's name.
    pub name: String,
    /// When an Entry in the Book was last written or changed, or the Book created, in
    /// milliseconds since the Unix epoch.
    pub last_activity_at: i64,
    /// The text of the Entry changed most recently, if the Book has any.
    pub last_entry_text: Option<String>,
}

/// An Entry as callers see it: its content and the IDs of its Images, never its keys.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct StoredEntry {
    /// The Entry's ID.
    pub id: Id,
    /// The Book the Entry belongs to.
    pub book_id: Id,
    /// The date and time the Entry is about.
    pub date: EntryDate,
    /// The Entry's plain text.
    pub text: String,
    /// The IDs of the Entry's Images, in the order they are shown.
    pub image_ids: Vec<Id>,
    /// When the Entry was first written, in milliseconds since the Unix epoch.
    pub created_at: i64,
    /// When the Entry was last changed, in milliseconds since the Unix epoch.
    pub updated_at: i64,
}

/// One Image of an Entry being saved.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum ImageInput {
    /// An Image the Entry already has, by Image ID. It is kept as it is, without sealing it again.
    Keep(Id),
    /// A new Image, from the bytes of its full-size image and its thumbnail.
    New {
        /// The full-size image.
        full: Vec<u8>,
        /// The thumbnail.
        thumbnail: Vec<u8>,
    },
}

/// An Entry to save: a new one when `id` is `None`, otherwise a change to an existing one.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct EntryDraft {
    /// The ID of the Entry to change, or `None` for a new Entry.
    pub id: Option<Id>,
    /// The Book the Entry belongs to. An existing Entry cannot move to another Book.
    pub book_id: Id,
    /// The date and time the Entry is about.
    pub date: EntryDate,
    /// The Entry's plain text.
    pub text: String,
    /// The Entry's Images, in order. Images the Entry had that are not kept here are deleted.
    pub images: Vec<ImageInput>,
}

/// Where a page of Entries ends: the next page starts after this Entry.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct EntryCursor {
    /// The date of the last Entry on the page.
    pub date: EntryDate,
    /// The ID of the last Entry on the page.
    pub id: Id,
}

impl From<&StoredEntry> for EntryCursor {
    fn from(entry: &StoredEntry) -> EntryCursor {
        EntryCursor {
            date: entry.date.clone(),
            id: entry.id,
        }
    }
}

/// One Entry found by a search.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct SearchHit {
    /// The Entry.
    pub entry: StoredEntry,
    /// A short part of the text around the match, with each matching word between
    /// [`MATCH_START`] and [`MATCH_END`].
    pub snippet: String,
}

/// How many Entries of one Book match a search.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct BookCount {
    /// The Book.
    pub book_id: Id,
    /// How many of its Entries match.
    pub count: u32,
}

/// A page of search results.
#[derive(Clone, PartialEq, Eq, Debug, Default)]
pub struct SearchResults {
    /// The matching Entries on this page, newest Entry date first.
    pub hits: Vec<SearchHit>,
    /// How many Entries match in all, within the Book searched if one was given.
    pub total: u32,
    /// How many Entries match in each Book, ignoring the Book searched: most matches first.
    pub per_book: Vec<BookCount>,
}

/// What a commit changed, sent to every listener after it.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Change {
    /// The Book that changed, or whose Entry changed.
    pub book_id: Id,
    /// The Entry that changed, or `None` when the Book itself changed.
    pub entry_id: Option<Id>,
}

type Listener = Arc<dyn Fn(Change) + Send + Sync>;

#[derive(Default)]
struct Listeners {
    next: u64,
    all: Vec<(u64, Listener)>,
}

struct Inner {
    conn: Connection,
    keyring: Keyring,
}

/// The device's Books, Entries, and Images. One store per database; it is safe to share between
/// threads, and runs one operation at a time.
pub struct Store {
    inner: Mutex<Inner>,
    files: ImageFiles,
    listeners: Mutex<Listeners>,
    #[cfg(test)]
    fail_before_commit: std::sync::atomic::AtomicBool,
    #[cfg(test)]
    fail_image_write: std::sync::atomic::AtomicBool,
}

/// An [`EntryDraft`] whose new Images are already sealed.
struct SealedDraft {
    id: Option<Id>,
    book_id: Id,
    date: EntryDate,
    text: String,
    images: Vec<ImageSlot>,
}

enum ImageSlot {
    Keep(Id),
    New(ImageRef),
}

impl Store {
    /// Opens the store in `dir`, creating it if it does not exist, with a keyring holding the
    /// device's master key.
    ///
    /// Brings the database to the current schema, and removes image files left behind by a save
    /// or delete that did not finish. Fails with [`StoreError::WrongKey`] if the database was
    /// created with another master key.
    pub fn open(dir: &Path, keyring: Keyring) -> Result<Store> {
        fs::create_dir_all(dir)?;
        let mut conn = Connection::open(dir.join(DATABASE_FILE))?;
        set_key(&conn, &keyring)?;
        conn.pragma_update_and_check(None, "journal_mode", "WAL", |row| row.get::<_, String>(0))?;
        conn.pragma_update(None, "foreign_keys", true)?;
        schema::migrate(&mut conn)?;

        let store = Store {
            inner: Mutex::new(Inner { conn, keyring }),
            files: ImageFiles::open(dir.join(IMAGES_DIR))?,
            listeners: Mutex::default(),
            #[cfg(test)]
            fail_before_commit: std::sync::atomic::AtomicBool::new(false),
            #[cfg(test)]
            fail_image_write: std::sync::atomic::AtomicBool::new(false),
        };
        store.remove_orphan_files()?;
        Ok(store)
    }

    /// Calls `listener` after every commit, until [`Store::unsubscribe`] is called with the
    /// returned number. Listeners run on the thread that committed, after the store is free again.
    pub fn subscribe(&self, listener: impl Fn(Change) + Send + Sync + 'static) -> u64 {
        let mut listeners = lock(&self.listeners);
        let id = listeners.next;
        listeners.next += 1;
        listeners.all.push((id, Arc::new(listener)));
        id
    }

    /// Stops calling a listener.
    pub fn unsubscribe(&self, subscription: u64) {
        lock(&self.listeners)
            .all
            .retain(|(id, _)| *id != subscription);
    }

    /// Creates a personal Book with a new Book key.
    pub fn create_book(&self, name: &str) -> Result<BookInfo> {
        let id = Id::random()?;
        let key = BookKey::generate(id)?;
        let record = seal_book_record(
            &BookRecord {
                id,
                name: name.to_owned(),
            },
            &key,
        )?;
        let now = now();
        {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let wrapped = wrap_book_key(&key, keyring.master())?;
            let tx = conn.transaction()?;
            tx.execute(
                "INSERT INTO book (id, name, last_activity_at, record, record_key_version)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![id, name, now, record, key.version()],
            )?;
            tx.execute(
                "INSERT INTO book_key (book_id, version, wrapped) VALUES (?1, ?2, ?3)",
                params![id, key.version(), wrapped],
            )?;
            tx.commit()?;
            keyring.insert(key);
        }
        self.notify(Change {
            book_id: id,
            entry_id: None,
        });
        Ok(BookInfo {
            id,
            name: name.to_owned(),
            last_activity_at: now,
            last_entry_text: None,
        })
    }

    /// Renames a Book.
    pub fn rename_book(&self, id: Id, name: &str) -> Result<()> {
        {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let version = current_key_version(conn, id)?;
            let key = book_key(conn, keyring, id, version)?;
            let record = seal_book_record(
                &BookRecord {
                    id,
                    name: name.to_owned(),
                },
                key,
            )?;
            conn.execute(
                "UPDATE book SET name = ?2, record = ?3, record_key_version = ?4 WHERE id = ?1",
                params![id, name, record, version],
            )?;
        }
        self.notify(Change {
            book_id: id,
            entry_id: None,
        });
        Ok(())
    }

    /// Deletes a Book with all its Entries and Images. Deleting a Book that does not exist does
    /// nothing.
    pub fn delete_book(&self, id: Id) -> Result<()> {
        let images = {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let tx = conn.transaction()?;
            let images = ids(
                &tx,
                "SELECT i.image_id FROM entry_image i JOIN entry e ON e.id = i.entry_id
                 WHERE e.book_id = ?1",
                id,
            )?;
            tx.execute(
                "DELETE FROM entry_search WHERE rowid IN (SELECT seq FROM entry WHERE book_id = ?1)",
                [id],
            )?;
            if tx.execute("DELETE FROM book WHERE id = ?1", [id])? == 0 {
                return Ok(());
            }
            tx.commit()?;
            keyring.forget_book(id);
            images
        };
        for image in images {
            self.files.remove(image);
        }
        self.notify(Change {
            book_id: id,
            entry_id: None,
        });
        Ok(())
    }

    /// Every Book, the one with the latest activity first.
    pub fn list_books(&self) -> Result<Vec<BookInfo>> {
        let inner = lock(&self.inner);
        let mut statement = inner.conn.prepare(&format!(
            "{SELECT_BOOK} ORDER BY b.last_activity_at DESC, b.id DESC"
        ))?;
        let books = statement
            .query_map([], read_book)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(books)
    }

    /// One Book.
    pub fn get_book(&self, id: Id) -> Result<BookInfo> {
        let inner = lock(&self.inner);
        Ok(inner
            .conn
            .query_row(&format!("{SELECT_BOOK} WHERE b.id = ?1"), [id], read_book)?)
    }

    /// Saves a new Entry or a change to one, with its Images, and returns it as stored.
    ///
    /// New Images are sealed and written to their files before the database changes; if the
    /// change fails, those files are deleted again. Images the Entry no longer has are deleted
    /// after the change commits.
    ///
    /// Fails with [`StoreError::Invalid`] if the draft keeps the same Image twice or moves an
    /// existing Entry to another Book, and with [`StoreError::NotFound`] if it keeps an Image the
    /// Entry does not have.
    pub fn save_entry(&self, draft: EntryDraft) -> Result<StoredEntry> {
        let kept: Vec<Id> = draft
            .images
            .iter()
            .filter_map(|input| match input {
                ImageInput::Keep(id) => Some(*id),
                ImageInput::New { .. } => None,
            })
            .collect();
        if kept
            .iter()
            .enumerate()
            .any(|(i, id)| kept[..i].contains(id))
        {
            return Err(StoreError::Invalid("an Image is kept twice"));
        }

        // Sealing and writing new Images takes the longest, so it happens before the store is
        // locked. Nothing refers to the files until the commit.
        let mut slots = Vec::with_capacity(draft.images.len());
        let mut new_images = Vec::new();
        for input in draft.images {
            match input {
                ImageInput::Keep(id) => slots.push(ImageSlot::Keep(id)),
                ImageInput::New { full, thumbnail } => {
                    let sealed = seal_image(&full, &thumbnail)?;
                    slots.push(ImageSlot::New(sealed.image.clone()));
                    new_images.push(sealed);
                }
            }
        }
        self.write_images(&new_images)?;

        let draft = SealedDraft {
            id: draft.id,
            book_id: draft.book_id,
            date: draft.date,
            text: draft.text,
            images: slots,
        };
        let (entry, dropped) = match self.commit_draft(draft) {
            Ok(saved) => saved,
            Err(error) => {
                for sealed in &new_images {
                    self.files.remove(sealed.image.id());
                }
                return Err(error);
            }
        };

        for image in dropped {
            self.files.remove(image);
        }
        self.notify(Change {
            book_id: entry.book_id,
            entry_id: Some(entry.id),
        });
        Ok(stored(entry))
    }

    /// One Entry, opened from its blob.
    pub fn get_entry(&self, id: Id) -> Result<StoredEntry> {
        let mut inner = lock(&self.inner);
        let Inner { conn, keyring } = &mut *inner;
        Ok(stored(open_stored_entry(conn, keyring, id)?))
    }

    /// A page of a Book's Entries, newest Entry date first, starting after `after`.
    pub fn list_entries(
        &self,
        book_id: Id,
        after: Option<&EntryCursor>,
        limit: u32,
    ) -> Result<Vec<StoredEntry>> {
        let inner = lock(&self.inner);
        let conn = &inner.conn;
        // Two statements rather than one with `?2 IS NULL OR ...`: SQLite only seeks the index to
        // the cursor when the condition is not behind an OR, so later pages would rescan earlier ones.
        let mut entries = match after {
            None => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE e.book_id = ?1
                     ORDER BY e.entry_date DESC, e.id DESC LIMIT ?2"
                ))?
                .query_map(params![book_id, limit], read_entry)?
                .collect::<rusqlite::Result<Vec<_>>>()?,
            Some(cursor) => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE e.book_id = ?1 AND (e.entry_date, e.id) < (?2, ?3)
                     ORDER BY e.entry_date DESC, e.id DESC LIMIT ?4"
                ))?
                .query_map(params![book_id, cursor.date, cursor.id, limit], read_entry)?
                .collect::<rusqlite::Result<Vec<_>>>()?,
        };
        for entry in &mut entries {
            entry.image_ids = image_ids(conn, entry.id)?;
        }
        Ok(entries)
    }

    /// Deletes an Entry and its Images. Deleting an Entry that does not exist does nothing.
    pub fn delete_entry(&self, id: Id) -> Result<()> {
        let (book_id, images) = {
            let mut inner = lock(&self.inner);
            let tx = inner.conn.transaction()?;
            let Some((seq, book_id)) = tx
                .query_row(
                    "SELECT seq, book_id FROM entry WHERE id = ?1",
                    [id],
                    |row| Ok((row.get::<_, i64>(0)?, row.get::<_, Id>(1)?)),
                )
                .optional()?
            else {
                return Ok(());
            };
            let images = ids(
                &tx,
                "SELECT image_id FROM entry_image WHERE entry_id = ?1",
                id,
            )?;
            tx.execute("DELETE FROM entry_search WHERE rowid = ?1", [seq])?;
            tx.execute("DELETE FROM entry WHERE id = ?1", [id])?;
            tx.execute(
                "UPDATE book SET last_activity_at = coalesce(
                     (SELECT max(updated_at) FROM entry WHERE book_id = ?1), last_activity_at)
                 WHERE id = ?1",
                [book_id],
            )?;
            tx.commit()?;
            (book_id, images)
        };
        for image in images {
            self.files.remove(image);
        }
        self.notify(Change {
            book_id,
            entry_id: Some(id),
        });
        Ok(())
    }

    /// One variant of an Entry's Image, opened: the image bytes as they were given.
    pub fn get_image(&self, entry_id: Id, image_id: Id, variant: ImageVariant) -> Result<Vec<u8>> {
        let entry = {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            open_stored_entry(conn, keyring, entry_id)?
        };
        let image = entry
            .images
            .iter()
            .find(|image| image.id() == image_id)
            .ok_or(StoreError::NotFound)?;
        let blob = self
            .files
            .read(image_id, variant)
            .map_err(|error| match error.kind() {
                std::io::ErrorKind::NotFound => StoreError::ImageMissing,
                _ => error.into(),
            })?;
        Ok(open_image(&blob, image, variant)?)
    }

    /// Entries in which every word typed starts a word, newest Entry date first, within one Book
    /// if `book_id` is given. Letters match with or without diacritics.
    pub fn search(
        &self,
        typed: &str,
        book_id: Option<Id>,
        limit: u32,
        offset: u32,
    ) -> Result<SearchResults> {
        let Some(query) = search::match_query(typed) else {
            return Ok(SearchResults::default());
        };
        let inner = lock(&self.inner);
        let conn = &inner.conn;

        let per_book = conn
            .prepare_cached(
                "SELECT e.book_id, count(*) FROM entry_search
                 JOIN entry e ON e.seq = entry_search.rowid
                 WHERE entry_search MATCH ?1
                 GROUP BY e.book_id ORDER BY count(*) DESC, e.book_id",
            )?
            .query_map([&query], |row| {
                Ok(BookCount {
                    book_id: row.get(0)?,
                    count: row.get(1)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let total = per_book
            .iter()
            .filter(|count| book_id.is_none_or(|id| id == count.book_id))
            .map(|count| count.count)
            .sum();

        let mut statement = conn.prepare_cached(&format!(
            "SELECT e.id, e.book_id, e.entry_date, e.created_at, e.updated_at, entry_search.text,
                    snippet(entry_search, 0, '{MATCH_START}', '{MATCH_END}', '…', {SNIPPET_WORDS})
             FROM entry_search JOIN entry e ON e.seq = entry_search.rowid
             WHERE entry_search MATCH ?1 AND (?2 IS NULL OR e.book_id = ?2)
             ORDER BY e.entry_date DESC, e.id DESC LIMIT ?3 OFFSET ?4"
        ))?;
        let mut hits = statement
            .query_map(params![query, book_id, limit, offset], |row| {
                Ok(SearchHit {
                    entry: read_entry(row)?,
                    snippet: row.get(6)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        for hit in &mut hits {
            hit.entry.image_ids = image_ids(conn, hit.entry.id)?;
        }

        Ok(SearchResults {
            hits,
            total,
            per_book,
        })
    }

    /// Rebuilds every plaintext column and the search index from the blobs, in one transaction.
    ///
    /// Fails, changing nothing, if any Book record or Entry blob does not open.
    pub fn rebuild_index(&self) -> Result<()> {
        let mut inner = lock(&self.inner);
        let Inner { conn, keyring } = &mut *inner;

        let wrapped_keys = {
            let mut statement = conn.prepare("SELECT book_id, wrapped FROM book_key")?;
            statement
                .query_map([], |row| {
                    Ok((row.get::<_, Id>(0)?, row.get::<_, Vec<u8>>(1)?))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        for (book_id, wrapped) in wrapped_keys {
            let key = unwrap_book_key(&wrapped, book_id, keyring.master())?;
            keyring.insert(key);
        }

        let tx = conn.transaction()?;
        tx.execute_batch("DELETE FROM entry_search; DELETE FROM entry_image;")?;

        let books = {
            let mut statement = tx.prepare("SELECT id, record_key_version, record FROM book")?;
            statement
                .query_map([], |row| {
                    Ok((
                        row.get::<_, Id>(0)?,
                        row.get::<_, u32>(1)?,
                        row.get::<_, Vec<u8>>(2)?,
                    ))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        for (id, version, record) in books {
            let key = keyring
                .book_key(id, version)
                .ok_or(Error::WrongKeyVersion)?;
            let record = open_book_record(&record, key)?;
            tx.execute(
                "UPDATE book SET name = ?2 WHERE id = ?1",
                params![id, record.name],
            )?;
        }

        let seqs = {
            let mut statement = tx.prepare("SELECT seq FROM entry")?;
            statement
                .query_map([], |row| row.get::<_, i64>(0))?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        for seq in seqs {
            let (id, book_id, version, blob) = tx.query_row(
                "SELECT id, book_id, book_key_version, blob FROM entry WHERE seq = ?1",
                [seq],
                |row| {
                    Ok((
                        row.get::<_, Id>(0)?,
                        row.get::<_, Id>(1)?,
                        row.get::<_, u32>(2)?,
                        row.get::<_, Vec<u8>>(3)?,
                    ))
                },
            )?;
            let key = keyring
                .book_key(book_id, version)
                .ok_or(Error::WrongKeyVersion)?;
            let entry = open_entry(&blob, id, key)?;
            tx.execute(
                "UPDATE entry SET entry_date = ?2, created_at = ?3, updated_at = ?4 WHERE seq = ?1",
                params![seq, entry.date, entry.created_at, entry.updated_at],
            )?;
            index_entry(&tx, seq, &entry)?;
        }

        tx.execute(
            "UPDATE book SET last_activity_at = coalesce(
                 (SELECT max(updated_at) FROM entry WHERE book_id = book.id), last_activity_at)",
            [],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// Seals a draft whose new Images are already written, and commits it. Returns the Entry
    /// saved and the Images it no longer has.
    fn commit_draft(&self, draft: SealedDraft) -> Result<(Entry, Vec<Id>)> {
        let now = now();
        let mut inner = lock(&self.inner);
        let Inner { conn, keyring } = &mut *inner;

        let existing = match draft.id {
            Some(id) => {
                let existing = open_stored_entry(conn, keyring, id)?;
                if existing.book_id != draft.book_id {
                    return Err(StoreError::Invalid("an Entry cannot move to another Book"));
                }
                Some(existing)
            }
            None => None,
        };
        let version = current_key_version(conn, draft.book_id)?;
        let key = book_key(conn, keyring, draft.book_id, version)?;

        let images = draft
            .images
            .into_iter()
            .map(|slot| match slot {
                ImageSlot::New(image) => Ok(image),
                ImageSlot::Keep(image_id) => existing
                    .iter()
                    .flat_map(|entry| &entry.images)
                    .find(|image| image.id() == image_id)
                    .cloned()
                    .ok_or(StoreError::NotFound),
            })
            .collect::<Result<Vec<_>>>()?;
        let entry = Entry {
            id: match draft.id {
                Some(id) => id,
                None => Id::random()?,
            },
            book_id: draft.book_id,
            date: draft.date,
            text: draft.text,
            images,
            created_at: existing.as_ref().map_or(now, |entry| entry.created_at),
            updated_at: now,
        };
        let blob = seal_entry(&entry, key)?;
        let dropped = existing
            .iter()
            .flat_map(|old| &old.images)
            .map(|image| image.id())
            .filter(|id| !entry.images.iter().any(|image| image.id() == *id))
            .collect();

        self.commit_entry(conn, &entry, version, &blob, existing.is_some())?;
        Ok((entry, dropped))
    }

    fn write_images(&self, images: &[SealedImage]) -> Result<()> {
        let written = images.iter().try_for_each(|sealed| {
            let id = sealed.image.id();
            self.files.write(id, ImageVariant::Full, &sealed.full)?;
            #[cfg(test)]
            if self
                .fail_image_write
                .swap(false, std::sync::atomic::Ordering::SeqCst)
            {
                return Err(std::io::Error::other("failure injected while writing"));
            }
            self.files
                .write(id, ImageVariant::Thumbnail, &sealed.thumbnail)
        });
        if let Err(error) = written {
            for sealed in images {
                self.files.remove(sealed.image.id());
            }
            return Err(error.into());
        }
        Ok(())
    }

    fn commit_entry(
        &self,
        conn: &mut Connection,
        entry: &Entry,
        book_key_version: u32,
        blob: &[u8],
        exists: bool,
    ) -> Result<()> {
        let tx = conn.transaction()?;
        let seq: i64 = if exists {
            let seq = tx.query_row(
                "UPDATE entry SET book_key_version = ?2, entry_date = ?3, updated_at = ?4, blob = ?5
                 WHERE id = ?1 RETURNING seq",
                params![
                    entry.id,
                    book_key_version,
                    entry.date,
                    entry.updated_at,
                    blob
                ],
                |row| row.get(0),
            )?;
            tx.execute("DELETE FROM entry_search WHERE rowid = ?1", [seq])?;
            tx.execute("DELETE FROM entry_image WHERE entry_id = ?1", [entry.id])?;
            seq
        } else {
            tx.execute(
                "INSERT INTO entry
                     (id, book_id, book_key_version, entry_date, created_at, updated_at, blob)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    entry.id,
                    entry.book_id,
                    book_key_version,
                    entry.date,
                    entry.created_at,
                    entry.updated_at,
                    blob
                ],
            )?;
            tx.last_insert_rowid()
        };
        index_entry(&tx, seq, entry)?;
        tx.execute(
            "UPDATE book SET last_activity_at = max(last_activity_at, ?2) WHERE id = ?1",
            params![entry.book_id, entry.updated_at],
        )?;
        #[cfg(test)]
        if self
            .fail_before_commit
            .swap(false, std::sync::atomic::Ordering::SeqCst)
        {
            return Err(std::io::Error::other("failure injected before commit").into());
        }
        tx.commit()?;
        Ok(())
    }

    fn remove_orphan_files(&self) -> Result<()> {
        let referenced: HashSet<Id> = {
            let inner = lock(&self.inner);
            let mut statement = inner.conn.prepare("SELECT image_id FROM entry_image")?;
            statement
                .query_map([], |row| row.get(0))?
                .collect::<rusqlite::Result<_>>()?
        };
        self.files
            .remove_orphans(|id| referenced.contains(&id), ORPHAN_AGE)?;
        Ok(())
    }

    fn notify(&self, change: Change) {
        let listeners: Vec<Listener> = lock(&self.listeners)
            .all
            .iter()
            .map(|(_, listener)| Arc::clone(listener))
            .collect();
        for listener in listeners {
            listener(change);
        }
    }
}

impl std::fmt::Debug for Store {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Store").finish_non_exhaustive()
    }
}

/// Locks a mutex, going on after a panic elsewhere: a transaction that was cut short has already
/// rolled back, so the data is still whole.
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Gives SQLCipher the database key as a raw key, and checks that it opens the database.
///
/// The cipher settings are pinned to SQLCipher 4's, so a later SQLCipher with other defaults still
/// opens databases written now.
fn set_key(conn: &Connection, keyring: &Keyring) -> Result<()> {
    let key = Zeroizing::new(hex::encode(keyring.database_key().as_slice()));
    let pragma = Zeroizing::new(format!("PRAGMA key = \"x'{}'\"", key.as_str()));
    run_pragma(conn, &pragma)?;
    run_pragma(conn, "PRAGMA cipher_compatibility = 4")?;
    conn.query_row("SELECT count(*) FROM sqlite_master", [], |_| Ok(()))
        .map_err(|error| match error.sqlite_error_code() {
            Some(ErrorCode::NotADatabase) => StoreError::WrongKey,
            _ => error.into(),
        })
}

/// Runs a pragma, reading and ignoring any rows it returns.
fn run_pragma(conn: &Connection, sql: &str) -> Result<()> {
    let mut statement = conn.prepare(sql)?;
    let mut rows = statement.query([])?;
    while rows.next()?.is_some() {}
    Ok(())
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_millis() as i64)
}

fn current_key_version(conn: &Connection, book_id: Id) -> Result<u32> {
    conn.query_row(
        "SELECT max(version) FROM book_key WHERE book_id = ?1",
        [book_id],
        |row| row.get::<_, Option<u32>>(0),
    )?
    .ok_or(StoreError::NotFound)
}

/// A Book key from the keyring, unwrapping it from the database the first time it is needed.
fn book_key<'k>(
    conn: &Connection,
    keyring: &'k mut Keyring,
    book_id: Id,
    version: u32,
) -> Result<&'k BookKey> {
    if keyring.book_key(book_id, version).is_none() {
        let wrapped: Vec<u8> = conn.query_row(
            "SELECT wrapped FROM book_key WHERE book_id = ?1 AND version = ?2",
            params![book_id, version],
            |row| row.get(0),
        )?;
        let key = unwrap_book_key(&wrapped, book_id, keyring.master())?;
        if key.version() != version {
            return Err(Error::WrongKeyVersion.into());
        }
        keyring.insert(key);
    }
    Ok(keyring
        .book_key(book_id, version)
        .expect("the key was just inserted"))
}

fn open_stored_entry(conn: &Connection, keyring: &mut Keyring, id: Id) -> Result<Entry> {
    let (book_id, version, blob) = conn.query_row(
        "SELECT book_id, book_key_version, blob FROM entry WHERE id = ?1",
        [id],
        |row| {
            Ok((
                row.get::<_, Id>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, Vec<u8>>(2)?,
            ))
        },
    )?;
    let key = book_key(conn, keyring, book_id, version)?;
    Ok(open_entry(&blob, id, key)?)
}

/// Writes the rows that index an Entry: its Images and its text for search.
fn index_entry(conn: &Connection, seq: i64, entry: &Entry) -> Result<()> {
    let mut statement = conn.prepare_cached(
        "INSERT INTO entry_image (entry_id, position, image_id) VALUES (?1, ?2, ?3)",
    )?;
    for (position, image) in entry.images.iter().enumerate() {
        statement.execute(params![entry.id, position as i64, image.id()])?;
    }
    conn.execute(
        "INSERT INTO entry_search (rowid, text) VALUES (?1, ?2)",
        params![seq, entry.text],
    )?;
    Ok(())
}

fn ids(conn: &Connection, sql: &str, param: Id) -> Result<Vec<Id>> {
    let mut statement = conn.prepare_cached(sql)?;
    let ids = statement
        .query_map([param], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    Ok(ids)
}

fn image_ids(conn: &Connection, entry_id: Id) -> Result<Vec<Id>> {
    ids(
        conn,
        "SELECT image_id FROM entry_image WHERE entry_id = ?1 ORDER BY position",
        entry_id,
    )
}

fn stored(entry: Entry) -> StoredEntry {
    StoredEntry {
        image_ids: entry.images.iter().map(|image| image.id()).collect(),
        id: entry.id,
        book_id: entry.book_id,
        date: entry.date,
        text: entry.text,
        created_at: entry.created_at,
        updated_at: entry.updated_at,
    }
}

const SELECT_BOOK: &str = "SELECT b.id, b.name, b.last_activity_at,
        (SELECT s.text FROM entry e JOIN entry_search s ON s.rowid = e.seq
         WHERE e.book_id = b.id ORDER BY e.updated_at DESC, e.id DESC LIMIT 1)
    FROM book b";

fn read_book(row: &rusqlite::Row<'_>) -> rusqlite::Result<BookInfo> {
    Ok(BookInfo {
        id: row.get(0)?,
        name: row.get(1)?,
        last_activity_at: row.get(2)?,
        last_entry_text: row.get(3)?,
    })
}

const SELECT_ENTRY: &str =
    "SELECT e.id, e.book_id, e.entry_date, e.created_at, e.updated_at, s.text
    FROM entry e JOIN entry_search s ON s.rowid = e.seq";

/// An Entry from its plaintext columns, without its Image IDs.
fn read_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<StoredEntry> {
    Ok(StoredEntry {
        id: row.get(0)?,
        book_id: row.get(1)?,
        date: row.get(2)?,
        created_at: row.get(3)?,
        updated_at: row.get(4)?,
        text: row.get(5)?,
        image_ids: Vec::new(),
    })
}

impl ToSql for Id {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(ToSqlOutput::from(&self.as_bytes()[..]))
    }
}

impl FromSql for Id {
    fn column_result(value: ValueRef<'_>) -> FromSqlResult<Id> {
        let bytes = value.as_blob()?;
        let bytes: [u8; Id::LEN] = bytes
            .try_into()
            .map_err(|_| FromSqlError::InvalidBlobSize {
                expected_size: Id::LEN,
                blob_size: bytes.len(),
            })?;
        Ok(Id::from_bytes(bytes))
    }
}

impl ToSql for EntryDate {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(ToSqlOutput::from(self.as_str()))
    }
}

impl FromSql for EntryDate {
    fn column_result(value: ValueRef<'_>) -> FromSqlResult<EntryDate> {
        EntryDate::parse(value.as_str()?).map_err(|error| FromSqlError::Other(Box::new(error)))
    }
}

#[cfg(test)]
mod tests;
