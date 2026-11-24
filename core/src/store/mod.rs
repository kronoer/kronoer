//! The device's store: Books, Entries, and Images in one SQLCipher database, plus a folder of
//! encrypted image files.
//!
//! Every Entry is kept as its sealed blob, in the same format the server stores. The plaintext
//! columns and the search index next to it only exist so lists, ordering, and search do not have
//! to open every blob; [`Store::rebuild_index`] rebuilds them from the blobs. Callers send and
//! receive plaintext content and IDs only: keys stay in the store's [`Keyring`].

mod error;
mod export;
mod files;
mod import;
mod insight;
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
use rusqlite::{Connection, ErrorCode, OptionalExtension, Transaction, params};
use zeroize::Zeroizing;

pub use error::StoreError;
pub use export::{
    ARCHIVE_DATA_FILE, ARCHIVE_FORMAT, ARCHIVE_FORMAT_VERSION, ARCHIVE_README_FILE, ExportActivity,
    ExportProgress, ExportSummary,
};
pub use import::{
    ArchiveCounts, ImportProgress, ImportSummary, ImportedBook, MAX_IMAGE_SIDE, THUMBNAIL_SIDE,
};
pub use insight::{BookInsight, count_words};
pub use keyring::Keyring;
pub use master_key::{DeviceError, MASTER_KEY_LEN, MasterKeyStore, PlatformKeyError};
pub use search::{MATCH_END, MATCH_START, match_ranges};

use self::files::ImageFiles;
use crate::book::open_book_record_name_only;
use crate::{
    BookKey, BookRecord, Entry, EntryDate, Error, Id, ImageRef, ImageVariant, LockRecord,
    SealedImage, StarRecord, hex, lock_record_id, open_book_record, open_entry, open_image,
    open_lock_record, open_star_record, seal_book_record, seal_entry, seal_image, seal_lock_record,
    seal_star_record, star_record_id, unwrap_book_key, wrap_book_key,
};

const DATABASE_FILE: &str = "kronoer.db";
const IMAGES_DIR: &str = "images";
/// Image files not referenced by any Entry are removed once they are this old. Younger ones may
/// belong to a save that has not committed yet.
const ORPHAN_AGE: Duration = Duration::from_secs(60 * 60);
/// How many words a search snippet shows around the match.
const SNIPPET_WORDS: u32 = 12;
/// How many Books can be pinned at once.
pub const MAX_PINNED_BOOKS: u32 = 3;
/// How many days a Book or an Entry stays in the Trash, counted from when it was deleted, until
/// the user chooses otherwise.
pub const DEFAULT_TRASH_DAYS: u32 = 30;
/// The numbers of days the user can choose for the Trash to keep what is deleted.
pub const TRASH_DAY_CHOICES: [u32; 3] = [7, 30, 90];
const DAY_MS: i64 = 24 * 60 * 60 * 1000;

type Result<T> = std::result::Result<T, StoreError>;

/// A Book, as lists show it.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct BookInfo {
    /// The Book's ID.
    pub id: Id,
    /// The Book's name.
    pub name: String,
    /// The Book's Description. It is empty when the Book has none.
    pub description: String,
    /// The Image ID of the Book's Cover, or `None` when it has none. A new Cover has a new ID.
    pub cover_id: Option<Id>,
    /// When an Entry in the Book was last written or changed, or the Book created, in
    /// milliseconds since the Unix epoch.
    pub last_activity_at: i64,
    /// The text of the Entry changed most recently, if the Book has any. It is empty, not
    /// `None`, when that Entry has only Images.
    pub last_entry_text: Option<String>,
    /// How many Images the Entry changed most recently has; 0 when the Book has no Entries.
    pub last_entry_image_count: u32,
    /// How many Entries the Book has.
    pub entry_count: u32,
    /// Whether the user pinned the Book on this device.
    pub pinned: bool,
    /// Whether the Book's Entries show in the Timeline on this device: true unless the user keeps
    /// it out.
    pub in_timeline: bool,
    /// Whether the user locked the Book: a Locked Book is left out of [`Store::list_books`].
    pub locked: bool,
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
    /// Whether the user starred the Entry.
    pub starred: bool,
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
    /// The Book the Entry belongs to. Saving cannot move an existing Entry to another Book:
    /// [`Store::move_entries`] does.
    pub book_id: Id,
    /// The date and time the Entry is about.
    pub date: EntryDate,
    /// The Entry's plain text.
    pub text: String,
    /// The Entry's Images, in order. Images the Entry had that are not kept here are deleted.
    pub images: Vec<ImageInput>,
}

/// The order a list of Entries comes in: by Entry date, Entries with the same date in the order
/// they were written, then by ID. Search results always come newest first.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum EntryOrder {
    /// The latest Entry date first; of the same date, the one written last first.
    #[default]
    NewestFirst,
    /// The earliest Entry date first; of the same date, the one written first first.
    OldestFirst,
}

impl EntryOrder {
    /// The `ORDER BY` terms. One index serves both orders: SQLite reads it backwards for one.
    fn sql(self) -> &'static str {
        match self {
            EntryOrder::NewestFirst => "e.entry_date DESC, e.created_at DESC, e.id DESC",
            EntryOrder::OldestFirst => "e.entry_date, e.created_at, e.id",
        }
    }

    /// How an Entry further down the list compares with one above it.
    fn past(self) -> &'static str {
        match self {
            EntryOrder::NewestFirst => "<",
            EntryOrder::OldestFirst => ">",
        }
    }
}

/// Where a page of Entries ends: the next page starts after this Entry.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct EntryCursor {
    /// The date of the last Entry on the page.
    pub date: EntryDate,
    /// When the last Entry on the page was first written, in milliseconds since the Unix epoch.
    pub created_at: i64,
    /// The ID of the last Entry on the page.
    pub id: Id,
}

impl From<&StoredEntry> for EntryCursor {
    fn from(entry: &StoredEntry) -> EntryCursor {
        EntryCursor {
            date: entry.date.clone(),
            created_at: entry.created_at,
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

/// A Book or an Entry in the Trash.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct TrashItem {
    /// When it was deleted, in milliseconds since the Unix epoch.
    pub deleted_at: i64,
    /// When it is deleted for good, in milliseconds since the Unix epoch: [`Store::trash_days`]
    /// after it was deleted.
    pub purge_at: i64,
    /// What it is.
    pub content: TrashContent,
}

/// What is in the Trash.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum TrashContent {
    /// A Book. Its Entry count counts the Entries that went to the Trash with it, which come back
    /// with it; Entries deleted from it before are items of their own.
    Book(BookInfo),
    /// An Entry deleted on its own.
    Entry {
        /// The Entry.
        entry: StoredEntry,
        /// The name of its Book.
        book_name: String,
        /// Whether its Book is in the Trash too.
        book_in_trash: bool,
        /// Whether its Book is a Locked Book.
        book_locked: bool,
    },
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
    /// Brings the database to the current schema, deletes for good what has been in the Trash for
    /// [`Store::trash_days`], and removes image files left behind by a save or delete that did not
    /// finish. Fails with [`StoreError::WrongKey`] if the database was created with another
    /// master key.
    pub fn open(dir: &Path, mut keyring: Keyring) -> Result<Store> {
        fs::create_dir_all(dir)?;
        let mut conn = Connection::open(dir.join(DATABASE_FILE))?;
        set_key(&conn, &keyring)?;
        conn.pragma_update_and_check(None, "journal_mode", "WAL", |row| row.get::<_, String>(0))?;
        conn.pragma_update(None, "foreign_keys", true)?;
        schema::migrate(&mut conn, &mut keyring)?;

        let store = Store {
            inner: Mutex::new(Inner { conn, keyring }),
            files: ImageFiles::open(dir.join(IMAGES_DIR))?,
            listeners: Mutex::default(),
            #[cfg(test)]
            fail_before_commit: std::sync::atomic::AtomicBool::new(false),
            #[cfg(test)]
            fail_image_write: std::sync::atomic::AtomicBool::new(false),
        };
        store.purge_trash(now())?;
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
                description: String::new(),
                cover: None,
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
            description: String::new(),
            cover_id: None,
            last_activity_at: now,
            last_entry_text: None,
            last_entry_image_count: 0,
            entry_count: 0,
            pinned: false,
            in_timeline: true,
            locked: false,
        })
    }

    /// Renames a Book.
    pub fn rename_book(&self, id: Id, name: &str) -> Result<()> {
        self.change_book(id, |record| record.name = name.to_owned())?;
        self.notify_book(id);
        Ok(())
    }

    /// Sets a Book's Description. An empty one removes it.
    pub fn set_book_description(&self, id: Id, description: &str) -> Result<()> {
        self.change_book(id, |record| record.description = description.to_owned())?;
        self.notify_book(id);
        Ok(())
    }

    /// Gives a Book a new Cover, from the bytes of its full-size image and its thumbnail, in place
    /// of the Cover it had.
    ///
    /// The Cover is sealed and written to its files before the database changes; if the change
    /// fails, those files are deleted again. The old Cover's files are deleted after it commits.
    pub fn set_book_cover(&self, id: Id, full: &[u8], thumbnail: &[u8]) -> Result<()> {
        let sealed = seal_image(full, thumbnail)?;
        self.write_images(std::slice::from_ref(&sealed))?;
        let old = match self.change_book(id, |record| record.cover = Some(sealed.image.clone())) {
            Ok(old) => old,
            Err(error) => {
                self.files.remove(sealed.image.id());
                return Err(error);
            }
        };
        if let Some(cover) = old.cover {
            self.files.remove(cover.id());
        }
        self.notify_book(id);
        Ok(())
    }

    /// Removes a Book's Cover and deletes its files. Removing a Cover the Book does not have
    /// changes nothing.
    pub fn remove_book_cover(&self, id: Id) -> Result<()> {
        let old = self.change_book(id, |record| record.cover = None)?;
        if let Some(cover) = old.cover {
            self.files.remove(cover.id());
            self.notify_book(id);
        }
        Ok(())
    }

    /// One variant of a Book's Cover, opened: the image bytes as they were given. Fails with
    /// [`StoreError::NotFound`] if the Book has no Cover.
    pub fn get_book_cover(&self, id: Id, variant: ImageVariant) -> Result<Vec<u8>> {
        let record = {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            open_stored_book_record(conn, keyring, id)?
        };
        let cover = record.cover.ok_or(StoreError::NotFound)?;
        self.open_image_file(&cover, variant)
    }

    /// Moves a Book to the Trash, with the Entries it has. It is hidden everywhere until it is
    /// restored, and deleted for good after [`Store::trash_days`].
    ///
    /// The Book is no longer pinned or kept out of the Timeline: restoring it does not bring
    /// those choices back. Moving a Book that does not exist, or is in the Trash, does nothing.
    pub fn trash_book(&self, id: Id) -> Result<()> {
        {
            let mut inner = lock(&self.inner);
            let tx = inner.conn.transaction()?;
            if tx.execute(
                "INSERT OR IGNORE INTO book_trash (book_id, deleted_at)
                 SELECT id, ?2 FROM book WHERE id = ?1",
                params![id, now()],
            )? == 0
            {
                return Ok(());
            }
            tx.execute("DELETE FROM book_pin WHERE book_id = ?1", [id])?;
            tx.execute("DELETE FROM book_out_of_timeline WHERE book_id = ?1", [id])?;
            self.fail_if_asked()?;
            tx.commit()?;
        }
        self.notify_book(id);
        Ok(())
    }

    /// Moves Entries to the Trash, in one transaction: all of them or none. They are hidden
    /// everywhere until they are restored, and deleted for good after [`Store::trash_days`]; each keeps
    /// its Images and star meanwhile.
    ///
    /// Entries that do not exist, are in the Trash, or whose Book is, are left out. Their Books
    /// take their last activity from the Entries they still show.
    pub fn trash_entries(&self, ids: &[Id]) -> Result<()> {
        let trashed = {
            let mut inner = lock(&self.inner);
            let tx = inner.conn.transaction()?;
            let now = now();
            let mut trashed = Vec::new();
            for &id in ids {
                let Some(book_id) = tx
                    .query_row(
                        "SELECT e.book_id FROM entry e WHERE e.id = ?1
                           AND NOT EXISTS (SELECT 1 FROM book_trash y WHERE y.book_id = e.book_id)",
                        [id],
                        |row| row.get::<_, Id>(0),
                    )
                    .optional()?
                else {
                    continue;
                };
                if tx.execute(
                    "INSERT OR IGNORE INTO entry_trash (entry_id, deleted_at) VALUES (?1, ?2)",
                    params![id, now],
                )? == 0
                {
                    continue;
                }
                trashed.push(Change {
                    book_id,
                    entry_id: Some(id),
                });
            }
            for book_id in books_of(&trashed) {
                recompute_last_activity(&tx, book_id)?;
            }
            self.fail_if_asked()?;
            tx.commit()?;
            trashed
        };
        for change in trashed {
            self.notify(change);
        }
        Ok(())
    }

    /// Takes Books and Entries out of the Trash, in one transaction: all of them or none. Each
    /// comes back as it was, with the same ID, Images, Cover, and star.
    ///
    /// A Book comes back with the Entries that went to the Trash with it; Entries deleted from it
    /// before stay in the Trash. An Entry whose Book is in the Trash and not restored here goes
    /// to the Book `others_to`, as [`Store::move_entries`] moves it; with no `others_to`, its
    /// Book is restored too. Items not in the Trash are left out.
    ///
    /// Fails, restoring nothing, with [`StoreError::NotFound`] if `others_to` does not exist, and
    /// with [`StoreError::Invalid`] if it is in the Trash.
    pub fn restore(&self, book_ids: &[Id], entry_ids: &[Id], others_to: Option<Id>) -> Result<()> {
        let changes = {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let target = match others_to {
                Some(to) => {
                    if in_book_trash(conn, to)? {
                        return Err(StoreError::Invalid(
                            "a Book in the Trash cannot take Entries",
                        ));
                    }
                    let version = current_key_version(conn, to)?;
                    book_key(conn, keyring, to, version)?;
                    Some((to, version))
                }
                None => None,
            };
            let tx = conn.transaction()?;
            let mut changes = Vec::new();
            for &id in book_ids {
                if tx.execute("DELETE FROM book_trash WHERE book_id = ?1", [id])? > 0 {
                    changes.push(Change {
                        book_id: id,
                        entry_id: None,
                    });
                }
            }
            let mut touched = Vec::new();
            for &id in entry_ids {
                let Some(book_id) = tx
                    .query_row(
                        "SELECT e.book_id FROM entry e JOIN entry_trash x ON x.entry_id = e.id
                         WHERE e.id = ?1",
                        [id],
                        |row| row.get::<_, Id>(0),
                    )
                    .optional()?
                else {
                    continue;
                };
                tx.execute("DELETE FROM entry_trash WHERE entry_id = ?1", [id])?;
                let mut book = book_id;
                if in_book_trash(&tx, book_id)? {
                    match target {
                        Some((to, version)) => {
                            move_entry(&tx, keyring, id, to, version)?;
                            book = to;
                        }
                        None => {
                            tx.execute("DELETE FROM book_trash WHERE book_id = ?1", [book_id])?;
                            changes.push(Change {
                                book_id,
                                entry_id: None,
                            });
                        }
                    }
                }
                changes.push(Change {
                    book_id,
                    entry_id: Some(id),
                });
                if book != book_id {
                    changes.push(Change {
                        book_id: book,
                        entry_id: Some(id),
                    });
                }
                touched.push(Change {
                    book_id: book,
                    entry_id: Some(id),
                });
            }
            for book_id in books_of(&touched) {
                recompute_last_activity(&tx, book_id)?;
            }
            self.fail_if_asked()?;
            tx.commit()?;
            changes
        };
        for change in changes {
            self.notify(change);
        }
        Ok(())
    }

    /// Deletes Books and Entries for good, in one transaction: all of them or none, whether they
    /// are in the Trash or not. A Book goes with all its Entries, those in the Trash on their own
    /// too, their Images, and its Cover; an Entry with its Images and star. Items that do not
    /// exist are left out.
    ///
    /// The rows go first; the Images' files are deleted after the commit.
    pub fn delete_forever(&self, book_ids: &[Id], entry_ids: &[Id]) -> Result<()> {
        let (changes, images) = {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let tx = conn.transaction()?;
            let mut changes = Vec::new();
            let mut images = Vec::new();
            let mut books = Vec::new();
            for &id in book_ids {
                if let Some(book_images) = delete_book_rows(&tx, id)? {
                    images.extend(book_images);
                    books.push(id);
                    changes.push(Change {
                        book_id: id,
                        entry_id: None,
                    });
                }
            }
            let mut entries = Vec::new();
            for &id in entry_ids {
                if let Some((book_id, entry_images)) = delete_entry_rows(&tx, id)? {
                    images.extend(entry_images);
                    entries.push(Change {
                        book_id,
                        entry_id: Some(id),
                    });
                }
            }
            for book_id in books_of(&entries) {
                recompute_last_activity(&tx, book_id)?;
            }
            self.fail_if_asked()?;
            tx.commit()?;
            for id in books {
                keyring.forget_book(id);
            }
            changes.extend(entries);
            (changes, images)
        };
        for image in images {
            self.files.remove(image);
        }
        for change in changes {
            self.notify(change);
        }
        Ok(())
    }

    /// Deletes everything in the Trash for good, as [`Store::delete_forever`] does.
    pub fn empty_trash(&self) -> Result<()> {
        let (books, entries) = {
            let inner = lock(&self.inner);
            trashed_ids(&inner.conn, i64::MAX)?
        };
        self.delete_forever(&books, &entries)
    }

    /// Every Book and Entry in the Trash, the one deleted most recently first.
    pub fn list_trash(&self) -> Result<Vec<TrashItem>> {
        let inner = lock(&self.inner);
        let conn = &inner.conn;
        let keep = i64::from(trash_days(conn)?) * DAY_MS;
        let rows = conn
            .prepare_cached(
                "SELECT 1, book_id, deleted_at FROM book_trash
                 UNION ALL SELECT 0, entry_id, deleted_at FROM entry_trash
                 ORDER BY 3 DESC, 2 DESC",
            )?
            .query_map([], |row| {
                Ok((
                    row.get::<_, bool>(0)?,
                    row.get::<_, Id>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut items = Vec::with_capacity(rows.len());
        for (is_book, id, deleted_at) in rows {
            let content = if is_book {
                TrashContent::Book(conn.query_row(
                    &format!("{SELECT_BOOK} WHERE b.id = ?1"),
                    [id],
                    read_book,
                )?)
            } else {
                let mut entry =
                    conn.query_row(&format!("{SELECT_ENTRY} WHERE e.id = ?1"), [id], read_entry)?;
                entry.image_ids = image_ids(conn, id)?;
                let book_name = conn.query_row(
                    "SELECT name FROM book WHERE id = ?1",
                    [entry.book_id],
                    |row| row.get(0),
                )?;
                TrashContent::Entry {
                    book_in_trash: in_book_trash(conn, entry.book_id)?,
                    book_locked: conn.query_row(
                        "SELECT EXISTS (SELECT 1 FROM book_lock WHERE book_id = ?1)",
                        [entry.book_id],
                        |row| row.get(0),
                    )?,
                    entry,
                    book_name,
                }
            };
            items.push(TrashItem {
                deleted_at,
                purge_at: deleted_at.saturating_add(keep),
                content,
            });
        }
        Ok(items)
    }

    /// How many days the Trash keeps what is deleted, counted from when each was deleted: one of
    /// [`TRASH_DAY_CHOICES`], [`DEFAULT_TRASH_DAYS`] until the user chooses.
    pub fn trash_days(&self) -> Result<u32> {
        trash_days(&lock(&self.inner).conn)
    }

    /// Sets how many days the Trash keeps what is deleted, one of [`TRASH_DAY_CHOICES`]; other
    /// numbers fail with [`StoreError::Invalid`]. What was deleted longer ago than that is then
    /// deleted for good at once, as [`Store::delete_forever`] does, and tells the listeners so.
    /// The new days alone send no [`Change`]: no Book or Entry changed.
    ///
    /// If deleting fails, the new days stay, and what is past them goes at the next open.
    pub fn set_trash_days(&self, days: u32) -> Result<()> {
        if !TRASH_DAY_CHOICES.contains(&days) {
            return Err(StoreError::Invalid("not a number of days the Trash offers"));
        }
        lock(&self.inner).conn.execute(
            "INSERT INTO trash_setting (id, days) VALUES (1, ?1)
             ON CONFLICT (id) DO UPDATE SET days = excluded.days",
            [days],
        )?;
        self.purge_trash(now())
    }

    /// How many items the Trash holds: its Books, and the Entries deleted on their own.
    pub fn trash_count(&self) -> Result<u32> {
        let inner = lock(&self.inner);
        Ok(inner.conn.query_row(
            "SELECT (SELECT count(*) FROM book_trash) + (SELECT count(*) FROM entry_trash)",
            [],
            |row| row.get(0),
        )?)
    }

    /// Pins or unpins Books on this device. Pinning a pinned Book, or unpinning one that is not,
    /// changes nothing.
    ///
    /// Fails, changing nothing, with [`StoreError::TooManyPinned`] if that would make more than
    /// [`MAX_PINNED_BOOKS`] Pinned Books, and with [`StoreError::NotFound`] if a Book does not
    /// exist.
    pub fn set_books_pinned(&self, ids: &[Id], pinned: bool) -> Result<()> {
        {
            let mut inner = lock(&self.inner);
            let tx = inner.conn.transaction()?;
            for &id in ids {
                let exists: bool = tx.query_row(
                    "SELECT EXISTS (SELECT 1 FROM book WHERE id = ?1)",
                    [id],
                    |row| row.get(0),
                )?;
                if !exists {
                    return Err(StoreError::NotFound);
                }
                if pinned {
                    tx.execute("INSERT OR IGNORE INTO book_pin (book_id) VALUES (?1)", [id])?;
                } else {
                    tx.execute("DELETE FROM book_pin WHERE book_id = ?1", [id])?;
                }
            }
            let count: u32 = tx.query_row("SELECT count(*) FROM book_pin", [], |row| row.get(0))?;
            if count > MAX_PINNED_BOOKS {
                return Err(StoreError::TooManyPinned);
            }
            tx.commit()?;
        }
        for &id in ids {
            self.notify_book(id);
        }
        Ok(())
    }

    /// Keeps a Book out of the Timeline on this device, or puts it back in. Its Entries stay in
    /// its own list and in search. Setting what is already set changes nothing.
    ///
    /// Fails with [`StoreError::NotFound`] if the Book does not exist.
    pub fn set_book_in_timeline(&self, id: Id, in_timeline: bool) -> Result<()> {
        {
            let inner = lock(&self.inner);
            let exists: bool = inner.conn.query_row(
                "SELECT EXISTS (SELECT 1 FROM book WHERE id = ?1)",
                [id],
                |row| row.get(0),
            )?;
            if !exists {
                return Err(StoreError::NotFound);
            }
            if in_timeline {
                inner
                    .conn
                    .execute("DELETE FROM book_out_of_timeline WHERE book_id = ?1", [id])?;
            } else {
                inner.conn.execute(
                    "INSERT OR IGNORE INTO book_out_of_timeline (book_id) VALUES (?1)",
                    [id],
                )?;
            }
        }
        self.notify_book(id);
        Ok(())
    }

    /// Every Book not in the Trash and not locked: the Pinned Books first, then the rest, each
    /// with the latest activity first.
    pub fn list_books(&self) -> Result<Vec<BookInfo>> {
        self.query_books(
            "k.book_id IS NULL
             ORDER BY p.book_id IS NULL, b.last_activity_at DESC, b.id DESC",
        )
    }

    /// Every Locked Book not in the Trash, with the latest activity first.
    pub fn list_locked_books(&self) -> Result<Vec<BookInfo>> {
        self.query_books("k.book_id IS NOT NULL ORDER BY b.last_activity_at DESC, b.id DESC")
    }

    /// The Books not in the Trash that meet `condition`, in its order.
    fn query_books(&self, condition: &str) -> Result<Vec<BookInfo>> {
        let inner = lock(&self.inner);
        let mut statement = inner.conn.prepare(&format!(
            "{SELECT_BOOK}
             WHERE NOT EXISTS (SELECT 1 FROM book_trash y WHERE y.book_id = b.id)
               AND {condition}"
        ))?;
        let books = statement
            .query_map([], read_book)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(books)
    }

    /// Locks or unlocks Books, in one transaction: all of them or none. Locking a Locked Book, or
    /// unlocking one that is not, changes nothing.
    ///
    /// A lock is a Lock record sealed with the master key; unlocking deletes it. Locking also
    /// unpins the Book. Whether it is in the Timeline is kept. A lock is not encryption: the
    /// Book's Entries are sealed the same either way.
    ///
    /// Fails, changing nothing, with [`StoreError::NotFound`] if a Book does not exist.
    pub fn set_books_locked(&self, ids: &[Id], locked: bool) -> Result<()> {
        {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let tx = conn.transaction()?;
            let now = now();
            for &id in ids {
                let exists: bool = tx.query_row(
                    "SELECT EXISTS (SELECT 1 FROM book WHERE id = ?1)",
                    [id],
                    |row| row.get(0),
                )?;
                if !exists {
                    return Err(StoreError::NotFound);
                }
                if is_locked(&tx, id)? == locked {
                    continue;
                }
                if locked {
                    store_book_lock(
                        &tx,
                        keyring,
                        &LockRecord {
                            book_id: id,
                            locked_at: now,
                        },
                    )?;
                    tx.execute("DELETE FROM book_pin WHERE book_id = ?1", [id])?;
                } else {
                    tx.execute("DELETE FROM book_lock WHERE book_id = ?1", [id])?;
                }
            }
            self.fail_if_asked()?;
            tx.commit()?;
        }
        for &id in ids {
            self.notify_book(id);
        }
        Ok(())
    }

    /// One Book, in the Trash or not.
    pub fn get_book(&self, id: Id) -> Result<BookInfo> {
        let inner = lock(&self.inner);
        Ok(inner
            .conn
            .query_row(&format!("{SELECT_BOOK} WHERE b.id = ?1"), [id], read_book)?)
    }

    /// How many Entries, words, and Images a Book holds, counted from the index without opening a
    /// blob. Entries in the Trash on their own do not count; for a Book in the Trash, the Entries
    /// that went with it do.
    pub fn book_insight(&self, id: Id) -> Result<BookInsight> {
        let inner = lock(&self.inner);
        let (entry_count, image_count) = inner.conn.query_row(
            &format!(
                "SELECT (SELECT count(*) FROM entry e WHERE e.book_id = b.id AND {NOT_TRASHED_ALONE}),
                        (SELECT count(*) FROM entry_image i JOIN entry e ON e.id = i.entry_id
                         WHERE e.book_id = b.id AND {NOT_TRASHED_ALONE})
                 FROM book b WHERE b.id = ?1"
            ),
            [id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;
        let mut statement = inner.conn.prepare(&format!(
            "SELECT s.text FROM entry e JOIN entry_search s ON s.rowid = e.seq
             WHERE e.book_id = ?1 AND {NOT_TRASHED_ALONE}"
        ))?;
        let mut rows = statement.query([id])?;
        let mut word_count = 0u32;
        while let Some(row) = rows.next()? {
            let text: String = row.get(0)?;
            word_count = word_count.saturating_add(count_words(&text));
        }
        Ok(BookInsight {
            entry_count,
            word_count,
            image_count,
        })
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
        let starred = is_starred(&lock(&self.inner).conn, entry.id)?;
        Ok(stored(entry, starred))
    }

    /// One Entry, opened from its blob.
    pub fn get_entry(&self, id: Id) -> Result<StoredEntry> {
        let mut inner = lock(&self.inner);
        let Inner { conn, keyring } = &mut *inner;
        let entry = open_stored_entry(conn, keyring, id)?;
        Ok(stored(entry, is_starred(conn, id)?))
    }

    /// Stars or unstars Entries, in one transaction: all of them or none. Entries that already
    /// are as asked stay as they are.
    ///
    /// Starring is not editing: the Entries, their times, and their Books' activity do not
    /// change. A star is a Star record sealed with the master key; unstarring deletes it.
    ///
    /// Fails, changing nothing, with [`StoreError::NotFound`] if an Entry does not exist.
    pub fn set_entries_starred(&self, ids: &[Id], starred: bool) -> Result<()> {
        let changed = {
            let now = now();
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let tx = conn.transaction()?;
            let mut changed = Vec::new();
            for &id in ids {
                let book_id: Id =
                    tx.query_row("SELECT book_id FROM entry WHERE id = ?1", [id], |row| {
                        row.get(0)
                    })?;
                if is_starred(&tx, id)? == starred {
                    continue;
                }
                if starred {
                    store_star(
                        &tx,
                        keyring,
                        &StarRecord {
                            entry_id: id,
                            book_id,
                            starred_at: now,
                        },
                    )?;
                } else {
                    tx.execute("DELETE FROM star WHERE entry_id = ?1", [id])?;
                }
                changed.push(Change {
                    book_id,
                    entry_id: Some(id),
                });
            }
            self.fail_if_asked()?;
            tx.commit()?;
            changed
        };
        for change in changed {
            self.notify(change);
        }
        Ok(())
    }

    /// A page of a Book's Starred Entries not in the Trash, newest Entry date first, starting
    /// after `after`.
    pub fn list_starred_entries(
        &self,
        book_id: Id,
        after: Option<&EntryCursor>,
        limit: u32,
    ) -> Result<Vec<StoredEntry>> {
        let inner = lock(&self.inner);
        let conn = &inner.conn;
        let order = EntryOrder::NewestFirst;
        let (by, past) = (order.sql(), order.past());
        let starred = format!(
            "e.id IN (SELECT entry_id FROM star WHERE book_id = ?1) AND {NOT_TRASHED_ALONE}"
        );
        let mut entries = match after {
            None => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE e.book_id = ?1 AND {starred} ORDER BY {by} LIMIT ?2"
                ))?
                .query_map(params![book_id, limit], read_entry)?
                .collect::<rusqlite::Result<Vec<_>>>()?,
            Some(cursor) => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE e.book_id = ?1 AND {starred}
                       AND (e.entry_date, e.created_at, e.id) {past} (?2, ?3, ?4)
                     ORDER BY {by} LIMIT ?5"
                ))?
                .query_map(
                    params![book_id, cursor.date, cursor.created_at, cursor.id, limit],
                    read_entry,
                )?
                .collect::<rusqlite::Result<Vec<_>>>()?,
        };
        for entry in &mut entries {
            entry.image_ids = image_ids(conn, entry.id)?;
        }
        Ok(entries)
    }

    /// A page of a Book's Entries in `order`, starting after `after`. Entries in the Trash on
    /// their own are left out.
    pub fn list_entries(
        &self,
        book_id: Id,
        order: EntryOrder,
        after: Option<&EntryCursor>,
        limit: u32,
    ) -> Result<Vec<StoredEntry>> {
        let inner = lock(&self.inner);
        let conn = &inner.conn;
        let (by, past) = (order.sql(), order.past());
        // Two statements rather than one with `?2 IS NULL OR ...`: SQLite only seeks the index to
        // the cursor when the condition is not behind an OR, so later pages would rescan earlier ones.
        let mut entries = match after {
            None => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE e.book_id = ?1 AND {NOT_TRASHED_ALONE}
                     ORDER BY {by} LIMIT ?2"
                ))?
                .query_map(params![book_id, limit], read_entry)?
                .collect::<rusqlite::Result<Vec<_>>>()?,
            Some(cursor) => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE e.book_id = ?1 AND {NOT_TRASHED_ALONE}
                       AND (e.entry_date, e.created_at, e.id) {past} (?2, ?3, ?4)
                     ORDER BY {by} LIMIT ?5"
                ))?
                .query_map(
                    params![book_id, cursor.date, cursor.created_at, cursor.id, limit],
                    read_entry,
                )?
                .collect::<rusqlite::Result<Vec<_>>>()?,
        };
        for entry in &mut entries {
            entry.image_ids = image_ids(conn, entry.id)?;
        }
        Ok(entries)
    }

    /// A page of the Entries in every Book in `order`, starting after `after`: the Timeline. The
    /// Entries of Books kept out of the Timeline or locked, and those in the Trash, are left out.
    pub fn list_all_entries(
        &self,
        order: EntryOrder,
        after: Option<&EntryCursor>,
        limit: u32,
    ) -> Result<Vec<StoredEntry>> {
        let inner = lock(&self.inner);
        let conn = &inner.conn;
        let (by, past) = (order.sql(), order.past());
        // Two statements for the same reason as in `list_entries`.
        let mut entries = match after {
            None => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE {IN_TIMELINE} AND {NOT_IN_TRASH} ORDER BY {by} LIMIT ?1"
                ))?
                .query_map(params![limit], read_entry)?
                .collect::<rusqlite::Result<Vec<_>>>()?,
            Some(cursor) => conn
                .prepare_cached(&format!(
                    "{SELECT_ENTRY} WHERE {IN_TIMELINE} AND {NOT_IN_TRASH}
                       AND (e.entry_date, e.created_at, e.id) {past} (?1, ?2, ?3)
                     ORDER BY {by} LIMIT ?4"
                ))?
                .query_map(
                    params![cursor.date, cursor.created_at, cursor.id, limit],
                    read_entry,
                )?
                .collect::<rusqlite::Result<Vec<_>>>()?,
        };
        for entry in &mut entries {
            entry.image_ids = image_ids(conn, entry.id)?;
        }
        Ok(entries)
    }

    /// The earliest day with an Entry in the Timeline, as `YYYY-MM-DD` in local time
    /// `utc_offset_minutes` east of UTC, such as the device's; `None` when the Timeline has no
    /// Entry. Books kept out of the Timeline or locked, and Entries in the Trash, do not count.
    /// It reads no Entry content.
    pub fn oldest_timeline_day(&self, utc_offset_minutes: i32) -> Result<Option<String>> {
        let offset = offset_modifier(utc_offset_minutes)?;
        let inner = lock(&self.inner);
        // An Entry's day as written is at most a day from its day in UTC, and that at most a day
        // from its day at `offset`. So the earliest day at `offset` is among the Entries written
        // less than five days after the earliest Entry date, which the index finds at once.
        Ok(inner
            .conn
            .prepare_cached(&format!(
                "SELECT min(date(e.entry_date, ?1)) FROM entry e
                 WHERE {IN_TIMELINE} AND {NOT_IN_TRASH} AND e.entry_date < (
                     SELECT date(e.entry_date, '+5 days') FROM entry e
                     WHERE {IN_TIMELINE} AND {NOT_IN_TRASH} ORDER BY e.entry_date LIMIT 1)"
            ))?
            .query_row(params![offset], |row| row.get(0))?)
    }

    /// The days from `from` to `to`, both `YYYY-MM-DD` and both included, that have an Entry in
    /// the Timeline, in local time `utc_offset_minutes` east of UTC, earliest first. Books kept
    /// out of the Timeline or locked, and Entries in the Trash, do not count. It reads no Entry
    /// content.
    pub fn timeline_days(
        &self,
        from: &str,
        to: &str,
        utc_offset_minutes: i32,
    ) -> Result<Vec<String>> {
        let offset = offset_modifier(utc_offset_minutes)?;
        for day in [from, to] {
            EntryDate::parse(&format!("{day}T00:00:00+00:00"))
                .map_err(|_| StoreError::Invalid("a day is not in the form YYYY-MM-DD"))?;
        }
        let inner = lock(&self.inner);
        // For the reason in `oldest_timeline_day`, an Entry on a day in the range was written at
        // most two days before or after it, so the index narrows the Entries to look at.
        let days = inner
            .conn
            .prepare_cached(&format!(
                "SELECT DISTINCT date(e.entry_date, ?3) AS day FROM entry e
                 WHERE e.entry_date >= date(?1, '-2 days') AND e.entry_date < date(?2, '+3 days')
                   AND {IN_TIMELINE} AND {NOT_IN_TRASH} AND date(e.entry_date, ?3) BETWEEN ?1 AND ?2
                 ORDER BY day"
            ))?
            .query_map(params![from, to, offset], |row| row.get(0))?
            .collect::<rusqlite::Result<Vec<String>>>()?;
        Ok(days)
    }

    /// Moves Entries to another Book, in one transaction: all of them or none. An Entry already
    /// in that Book stays as it is.
    ///
    /// Moving is not editing: each Entry keeps its ID, date, text, Images, times, and star. It is opened
    /// with its Book's key and sealed again, with a fresh Entry key, for the Book's current key;
    /// its Images' files stay as they are, since their keys travel inside the Entry. The Books
    /// moved from take their last activity from the Entries they still have; the Book moved to
    /// takes a moved Entry's only if it is later.
    ///
    /// Fails, moving nothing, with [`StoreError::NotFound`] if the Book or an Entry does not exist.
    pub fn move_entries(&self, ids: &[Id], book_id: Id) -> Result<()> {
        let moved = {
            let mut inner = lock(&self.inner);
            let Inner { conn, keyring } = &mut *inner;
            let version = current_key_version(conn, book_id)?;
            book_key(conn, keyring, book_id, version)?;
            let tx = conn.transaction()?;
            let mut moved = Vec::new();
            for &id in ids {
                let Some(from) = move_entry(&tx, keyring, id, book_id, version)? else {
                    continue;
                };
                moved.push(Change {
                    book_id: from,
                    entry_id: Some(id),
                });
            }
            for from in books_of(&moved) {
                recompute_last_activity(&tx, from)?;
            }
            self.fail_if_asked()?;
            tx.commit()?;
            moved
        };
        for change in moved {
            self.notify(change);
            self.notify(Change { book_id, ..change });
        }
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
        self.open_image_file(image, variant)
    }

    /// Entries in which every word typed starts a word, newest first, within one Book
    /// if `book_id` is given. Letters match with or without diacritics. Entries in the Trash are
    /// left out, and so are Locked Books but the one searched: a search across all Books never
    /// shows them, nor counts them in `per_book`.
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
            .prepare_cached(&format!(
                "SELECT e.book_id, count(*) FROM entry_search
                 JOIN entry e ON e.seq = entry_search.rowid
                 WHERE entry_search MATCH ?1 AND {SEARCHABLE} AND {NOT_IN_TRASH}
                 GROUP BY e.book_id ORDER BY count(*) DESC, e.book_id"
            ))?
            .query_map(params![query, book_id], |row| {
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
                    {STARRED},
                    snippet(entry_search, 0, '{MATCH_START}', '{MATCH_END}', '…', {SNIPPET_WORDS})
             FROM entry_search JOIN entry e ON e.seq = entry_search.rowid
             WHERE entry_search MATCH ?1 AND (?2 IS NULL OR e.book_id = ?2) AND {SEARCHABLE}
               AND {NOT_IN_TRASH}
             ORDER BY {by} LIMIT ?3 OFFSET ?4",
            by = EntryOrder::NewestFirst.sql()
        ))?;
        let mut hits = statement
            .query_map(params![query, book_id, limit, offset], |row| {
                Ok(SearchHit {
                    entry: read_entry(row)?,
                    snippet: row.get(7)?,
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

    /// Rebuilds every plaintext column and the search index from the blobs and records, in one
    /// transaction.
    ///
    /// Fails, changing nothing, if any Book record, Entry blob, Star record, or Lock record does
    /// not open.
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
                "UPDATE book SET name = ?2, description = ?3, cover_id = ?4 WHERE id = ?1",
                params![
                    id,
                    record.name,
                    record.description,
                    record.cover.as_ref().map(ImageRef::id)
                ],
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

        let stars = {
            let mut statement = tx.prepare("SELECT record_id, record FROM star")?;
            statement
                .query_map([], |row| {
                    Ok((row.get::<_, Id>(0)?, row.get::<_, Vec<u8>>(1)?))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        for (record_id, record) in stars {
            let star = open_star_record(&record, keyring.master())?;
            if star_record_id(star.entry_id, keyring.master()) != record_id {
                return Err(Error::WrongEntry.into());
            }
            tx.execute(
                "UPDATE star SET entry_id = ?2, book_id = ?3, starred_at = ?4 WHERE record_id = ?1",
                params![record_id, star.entry_id, star.book_id, star.starred_at],
            )?;
        }

        let locks = {
            let mut statement = tx.prepare("SELECT record_id, record FROM book_lock")?;
            statement
                .query_map([], |row| {
                    Ok((row.get::<_, Id>(0)?, row.get::<_, Vec<u8>>(1)?))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        for (record_id, record) in locks {
            let book_lock = open_lock_record(&record, keyring.master())?;
            if lock_record_id(book_lock.book_id, keyring.master()) != record_id {
                return Err(Error::WrongBook.into());
            }
            tx.execute(
                "UPDATE book_lock SET book_id = ?2, locked_at = ?3 WHERE record_id = ?1",
                params![record_id, book_lock.book_id, book_lock.locked_at],
            )?;
        }

        tx.execute(
            &format!(
                "UPDATE book SET last_activity_at = coalesce(
                     (SELECT max(e.updated_at) FROM entry e
                      WHERE e.book_id = book.id AND {NOT_TRASHED_ALONE}),
                     last_activity_at)"
            ),
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

    /// Opens a Book's record, changes it, and stores it sealed again with the Book's current key.
    /// Returns the record as it was.
    fn change_book(&self, id: Id, change: impl FnOnce(&mut BookRecord)) -> Result<BookRecord> {
        let mut inner = lock(&self.inner);
        let Inner { conn, keyring } = &mut *inner;
        let old = open_stored_book_record(conn, keyring, id)?;
        let mut record = old.clone();
        change(&mut record);
        store_book_record(conn, keyring, &record)?;
        Ok(old)
    }

    /// Reads one variant of an Image's file, or a Cover's, and opens it.
    fn open_image_file(&self, image: &ImageRef, variant: ImageVariant) -> Result<Vec<u8>> {
        let blob = self
            .files
            .read(image.id(), variant)
            .map_err(|error| match error.kind() {
                std::io::ErrorKind::NotFound => StoreError::ImageMissing,
                _ => error.into(),
            })?;
        Ok(open_image(&blob, image, variant)?)
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
        self.fail_if_asked()?;
        tx.commit()?;
        Ok(())
    }

    /// In tests, fails once when asked to, just before a transaction commits.
    #[allow(clippy::unused_self)]
    fn fail_if_asked(&self) -> Result<()> {
        #[cfg(test)]
        if self
            .fail_before_commit
            .swap(false, std::sync::atomic::Ordering::SeqCst)
        {
            return Err(std::io::Error::other("failure injected before commit").into());
        }
        Ok(())
    }

    /// Deletes for good what was deleted [`Store::trash_days`] or more before `now`.
    fn purge_trash(&self, now: i64) -> Result<()> {
        let (books, entries) = {
            let inner = lock(&self.inner);
            let keep = i64::from(trash_days(&inner.conn)?) * DAY_MS;
            trashed_ids(&inner.conn, now - keep)?
        };
        if books.is_empty() && entries.is_empty() {
            return Ok(());
        }
        self.delete_forever(&books, &entries)
    }

    fn remove_orphan_files(&self) -> Result<()> {
        let referenced: HashSet<Id> = {
            let inner = lock(&self.inner);
            let mut statement = inner.conn.prepare(
                "SELECT image_id FROM entry_image
                 UNION ALL SELECT cover_id FROM book WHERE cover_id IS NOT NULL",
            )?;
            statement
                .query_map([], |row| row.get(0))?
                .collect::<rusqlite::Result<_>>()?
        };
        self.files
            .remove_orphans(|id| referenced.contains(&id), ORPHAN_AGE)?;
        Ok(())
    }

    fn notify_book(&self, book_id: Id) {
        self.notify(Change {
            book_id,
            entry_id: None,
        });
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

fn open_stored_book_record(conn: &Connection, keyring: &mut Keyring, id: Id) -> Result<BookRecord> {
    let (version, blob) = conn.query_row(
        "SELECT record_key_version, record FROM book WHERE id = ?1",
        [id],
        |row| Ok((row.get::<_, u32>(0)?, row.get::<_, Vec<u8>>(1)?)),
    )?;
    let key = book_key(conn, keyring, id, version)?;
    Ok(open_book_record(&blob, key)?)
}

/// Seals a Book record with the Book's current key, and stores it with the columns that come
/// from it.
fn store_book_record(conn: &Connection, keyring: &mut Keyring, record: &BookRecord) -> Result<()> {
    let version = current_key_version(conn, record.id)?;
    let key = book_key(conn, keyring, record.id, version)?;
    let blob = seal_book_record(record, key)?;
    conn.execute(
        "UPDATE book SET name = ?2, description = ?3, cover_id = ?4, record = ?5,
             record_key_version = ?6
         WHERE id = ?1",
        params![
            record.id,
            record.name,
            record.description,
            record.cover.as_ref().map(ImageRef::id),
            blob,
            version
        ],
    )?;
    Ok(())
}

/// Schema migration 2: seals every Book record again, which until then held only a name, with an
/// empty Description and no Cover.
fn reseal_name_only_book_records(tx: &Transaction<'_>, keyring: &mut Keyring) -> Result<()> {
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
    for (id, version, blob) in books {
        let key = book_key(tx, keyring, id, version)?;
        let name = open_book_record_name_only(&blob, key)?;
        let record = BookRecord {
            id,
            name,
            description: String::new(),
            cover: None,
        };
        store_book_record(tx, keyring, &record)?;
    }
    Ok(())
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

/// Moves an Entry to another Book: opens it with its Book's key and seals it again, with a fresh
/// Entry key, for `book_id`'s key `version`, which must be in the keyring. Its star moves with it,
/// and the Book moved to takes its last activity if it is later. Returns the Book it was in, or
/// `None` if it already is in `book_id`.
fn move_entry(
    tx: &Transaction<'_>,
    keyring: &mut Keyring,
    id: Id,
    book_id: Id,
    version: u32,
) -> Result<Option<Id>> {
    let mut entry = open_stored_entry(tx, keyring, id)?;
    if entry.book_id == book_id {
        return Ok(None);
    }
    let from = entry.book_id;
    entry.book_id = book_id;
    let key = keyring
        .book_key(book_id, version)
        .expect("the caller unwrapped the key");
    let blob = seal_entry(&entry, key)?;
    tx.execute(
        "UPDATE entry SET book_id = ?2, book_key_version = ?3, blob = ?4 WHERE id = ?1",
        params![id, book_id, version, blob],
    )?;
    // A star moves with its Entry, keeping when it was made.
    let star = tx
        .query_row("SELECT record FROM star WHERE entry_id = ?1", [id], |row| {
            row.get::<_, Vec<u8>>(0)
        })
        .optional()?;
    if let Some(star) = star {
        let mut star = open_star_record(&star, keyring.master())?;
        star.book_id = book_id;
        store_star(tx, keyring, &star)?;
    }
    tx.execute(
        "UPDATE book SET last_activity_at = max(last_activity_at, ?2) WHERE id = ?1",
        params![book_id, entry.updated_at],
    )?;
    Ok(Some(from))
}

/// Deletes a Book's rows: its Entries' too, through the foreign keys, and their search rows.
/// Returns the Images whose files to delete after the commit, its Cover among them, or `None` if
/// the Book does not exist.
fn delete_book_rows(tx: &Transaction<'_>, id: Id) -> Result<Option<Vec<Id>>> {
    let mut images = ids(
        tx,
        "SELECT i.image_id FROM entry_image i JOIN entry e ON e.id = i.entry_id
         WHERE e.book_id = ?1",
        id,
    )?;
    images.extend(ids(
        tx,
        "SELECT cover_id FROM book WHERE id = ?1 AND cover_id IS NOT NULL",
        id,
    )?);
    tx.execute(
        "DELETE FROM entry_search WHERE rowid IN (SELECT seq FROM entry WHERE book_id = ?1)",
        [id],
    )?;
    if tx.execute("DELETE FROM book WHERE id = ?1", [id])? == 0 {
        return Ok(None);
    }
    Ok(Some(images))
}

/// Deletes an Entry's rows: its Images', star's, and Trash row's too, through the foreign keys.
/// Returns its Book and the Images whose files to delete after the commit, or `None` if the Entry
/// does not exist.
fn delete_entry_rows(tx: &Transaction<'_>, id: Id) -> Result<Option<(Id, Vec<Id>)>> {
    let Some((seq, book_id)) = tx
        .query_row(
            "SELECT seq, book_id FROM entry WHERE id = ?1",
            [id],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, Id>(1)?)),
        )
        .optional()?
    else {
        return Ok(None);
    };
    let images = ids(
        tx,
        "SELECT image_id FROM entry_image WHERE entry_id = ?1",
        id,
    )?;
    tx.execute("DELETE FROM entry_search WHERE rowid = ?1", [seq])?;
    tx.execute("DELETE FROM entry WHERE id = ?1", [id])?;
    Ok(Some((book_id, images)))
}

/// Whether the Book `id` is in the Trash.
fn in_book_trash(conn: &Connection, id: Id) -> Result<bool> {
    Ok(conn
        .prepare_cached("SELECT EXISTS (SELECT 1 FROM book_trash WHERE book_id = ?1)")?
        .query_row([id], |row| row.get(0))?)
}

/// How many days the Trash keeps what is deleted: the user's choice, or the default.
fn trash_days(conn: &Connection) -> Result<u32> {
    Ok(conn
        .prepare_cached("SELECT days FROM trash_setting WHERE id = 1")?
        .query_row([], |row| row.get(0))
        .optional()?
        .unwrap_or(DEFAULT_TRASH_DAYS))
}

/// The Books and the Entries in the Trash on their own that were deleted before `before`.
fn trashed_ids(conn: &Connection, before: i64) -> Result<(Vec<Id>, Vec<Id>)> {
    let select = |sql: &str| -> Result<Vec<Id>> {
        Ok(conn
            .prepare(sql)?
            .query_map([before], |row| row.get(0))?
            .collect::<rusqlite::Result<_>>()?)
    };
    Ok((
        select("SELECT book_id FROM book_trash WHERE deleted_at < ?1")?,
        select("SELECT entry_id FROM entry_trash WHERE deleted_at < ?1")?,
    ))
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

/// The Books of these changes, each once, in the order they first come.
fn books_of(changes: &[Change]) -> Vec<Id> {
    let mut books = Vec::new();
    for change in changes {
        if !books.contains(&change.book_id) {
            books.push(change.book_id);
        }
    }
    books
}

/// Sets a Book's last activity to that of the Entry it has changed most recently, of those not in
/// the Trash on their own. A Book left with no Entries keeps the one it had.
fn recompute_last_activity(conn: &Connection, book_id: Id) -> Result<()> {
    conn.execute(
        &format!(
            "UPDATE book SET last_activity_at = coalesce(
                 (SELECT max(e.updated_at) FROM entry e WHERE e.book_id = ?1 AND {NOT_TRASHED_ALONE}),
                 last_activity_at)
             WHERE id = ?1"
        ),
        [book_id],
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

/// Whether the user starred the Entry `id`.
fn is_starred(conn: &Connection, id: Id) -> Result<bool> {
    Ok(conn
        .prepare_cached("SELECT EXISTS (SELECT 1 FROM star WHERE entry_id = ?1)")?
        .query_row([id], |row| row.get(0))?)
}

/// Whether the user locked the Book `id`.
fn is_locked(conn: &Connection, id: Id) -> Result<bool> {
    Ok(conn
        .prepare_cached("SELECT EXISTS (SELECT 1 FROM book_lock WHERE book_id = ?1)")?
        .query_row([id], |row| row.get(0))?)
}

/// Seals a Lock record and keeps it, in place of the one its Book had.
fn store_book_lock(conn: &Connection, keyring: &Keyring, book_lock: &LockRecord) -> Result<()> {
    let record = seal_lock_record(book_lock, keyring.master())?;
    conn.execute(
        "INSERT OR REPLACE INTO book_lock (record_id, book_id, locked_at, record)
         VALUES (?1, ?2, ?3, ?4)",
        params![
            lock_record_id(book_lock.book_id, keyring.master()),
            book_lock.book_id,
            book_lock.locked_at,
            record
        ],
    )?;
    Ok(())
}

/// Seals a Star record and keeps it, in place of the one its Entry had.
fn store_star(conn: &Connection, keyring: &Keyring, star: &StarRecord) -> Result<()> {
    let record = seal_star_record(star, keyring.master())?;
    conn.execute(
        "INSERT OR REPLACE INTO star (record_id, entry_id, book_id, starred_at, record)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![
            star_record_id(star.entry_id, keyring.master()),
            star.entry_id,
            star.book_id,
            star.starred_at,
            record
        ],
    )?;
    Ok(())
}

fn stored(entry: Entry, starred: bool) -> StoredEntry {
    StoredEntry {
        starred,
        image_ids: entry.images.iter().map(|image| image.id()).collect(),
        id: entry.id,
        book_id: entry.book_id,
        date: entry.date,
        text: entry.text,
        created_at: entry.created_at,
        updated_at: entry.updated_at,
    }
}

/// Each Book with the Entry changed most recently, if any (its text and how many Images it has),
/// how many Entries it has, and whether it is pinned, in the Timeline, and locked. Entries in the Trash on their own do not
/// count; for a Book in the Trash, those that went with it do.
const SELECT_BOOK: &str = "SELECT b.id, b.name, b.description, b.last_activity_at, s.text,
        (SELECT count(*) FROM entry_image i WHERE i.entry_id = e.id), b.cover_id,
        (SELECT count(*) FROM entry c WHERE c.book_id = b.id
           AND NOT EXISTS (SELECT 1 FROM entry_trash x WHERE x.entry_id = c.id)),
        p.book_id IS NOT NULL, t.book_id IS NULL, k.book_id IS NOT NULL
    FROM book b
    LEFT JOIN book_pin p ON p.book_id = b.id
    LEFT JOIN book_out_of_timeline t ON t.book_id = b.id
    LEFT JOIN book_lock k ON k.book_id = b.id
    LEFT JOIN entry e ON e.seq = (
        SELECT l.seq FROM entry l
        WHERE l.book_id = b.id AND NOT EXISTS (SELECT 1 FROM entry_trash x WHERE x.entry_id = l.id)
        ORDER BY l.updated_at DESC, l.id DESC LIMIT 1)
    LEFT JOIN entry_search s ON s.rowid = e.seq";

fn read_book(row: &rusqlite::Row<'_>) -> rusqlite::Result<BookInfo> {
    Ok(BookInfo {
        id: row.get(0)?,
        name: row.get(1)?,
        description: row.get(2)?,
        last_activity_at: row.get(3)?,
        last_entry_text: row.get(4)?,
        last_entry_image_count: row.get(5)?,
        cover_id: row.get(6)?,
        entry_count: row.get(7)?,
        pinned: row.get(8)?,
        in_timeline: row.get(9)?,
        locked: row.get(10)?,
    })
}

/// The condition on an Entry `e` that its Book is in the Timeline: not kept out of it, and not
/// locked, whatever its Timeline choice.
const IN_TIMELINE: &str =
    "NOT EXISTS (SELECT 1 FROM book_out_of_timeline t WHERE t.book_id = e.book_id)
     AND NOT EXISTS (SELECT 1 FROM book_lock k WHERE k.book_id = e.book_id)";

/// The condition on an Entry `e` that search may show it, given the Book searched as `?2`: a
/// search across all Books leaves Locked Books out, a search within one Book does not.
const SEARCHABLE: &str = "(e.book_id = ?2
     OR NOT EXISTS (SELECT 1 FROM book_lock k WHERE k.book_id = e.book_id))";

/// The SQLite date modifier that moves a time `utc_offset_minutes` east of UTC, at most 18 hours
/// either way as in an Entry date.
fn offset_modifier(utc_offset_minutes: i32) -> Result<String> {
    if utc_offset_minutes.unsigned_abs() > 18 * 60 {
        return Err(StoreError::Invalid("a UTC offset is more than 18 hours"));
    }
    Ok(format!("{utc_offset_minutes:+} minutes"))
}

/// The condition on an Entry `e` that it is not in the Trash on its own. It may still be there
/// with its Book.
const NOT_TRASHED_ALONE: &str = "NOT EXISTS (SELECT 1 FROM entry_trash x WHERE x.entry_id = e.id)";

/// The condition on an Entry `e` that it is not in the Trash, on its own or with its Book.
const NOT_IN_TRASH: &str = "NOT EXISTS (SELECT 1 FROM entry_trash x WHERE x.entry_id = e.id)
    AND NOT EXISTS (SELECT 1 FROM book_trash y WHERE y.book_id = e.book_id)";

/// Whether the Entry `e` is starred.
const STARRED: &str = "EXISTS (SELECT 1 FROM star st WHERE st.entry_id = e.id)";

/// An Entry's plaintext columns and whether it is starred ([`STARRED`]).
const SELECT_ENTRY: &str =
    "SELECT e.id, e.book_id, e.entry_date, e.created_at, e.updated_at, s.text,
        EXISTS (SELECT 1 FROM star st WHERE st.entry_id = e.id)
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
        starred: row.get(6)?,
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
