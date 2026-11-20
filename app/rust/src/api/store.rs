//! Books, Entries, and Images on the device, through the core's encrypted store.
//!
//! Dart sends and receives plaintext content and IDs only. Keys stay in Rust: Dart holds a
//! [`Keyring`] and a [`CoreStore`] as opaque handles it cannot read.

use std::path::Path;
use std::sync::{Arc, OnceLock};

use flutter_rust_bridge::frb;
use kronoer_core::store::{self, Change, DeviceError, EntryCursor, ImageInput, Store, StoreError};
use kronoer_core::{EntryDate, Id, ImageVariant, MasterKey};

use crate::frb_generated::StreamSink;

/// Opens the device's store, with its master key wrapped by the platform's key store.
///
/// On Android the store lives in the app's files directory and the wrapped master key in its
/// `no_backup` directory; the first launch makes the master key. Other platforms are not
/// supported yet.
pub fn open_device_store() -> Result<CoreStore, StoreFailure> {
    #[cfg(target_os = "android")]
    {
        let device = crate::android::device().ok_or_else(|| StoreFailure {
            kind: StoreFailureKind::Unsupported,
            message: "KronoerCore.init was not called".to_owned(),
        })?;
        let store = Store::open_on_device(
            &device.files_dir().join("store"),
            &device.no_backup_dir().join("master-key"),
            &crate::android::AndroidKeystore,
        )?;
        Ok(CoreStore {
            store: Arc::new(store),
        })
    }
    #[cfg(not(target_os = "android"))]
    {
        Err(StoreFailure {
            kind: StoreFailureKind::Unsupported,
            message: "the device store is only on Android so far".to_owned(),
        })
    }
}

/// A new random ID for a Book, Entry, or Image, as 32 lowercase hexadecimal digits.
#[frb(sync)]
pub fn new_id() -> Result<String, StoreFailure> {
    Ok(Id::random().map_err(StoreError::from)?.to_hex())
}

/// Where a search for `query` matches `text`, in order: each range one whole word that starts
/// with a word typed, by the same rules as [`CoreStore::search`]. Empty when not every word typed
/// matches.
#[frb(sync)]
pub fn match_ranges(text: String, query: String) -> Result<Vec<MatchRange>, StoreFailure> {
    let ranges = store::match_ranges(&text, &query)?;
    // Byte offsets to UTF-16 offsets, which is how Dart indexes a String.
    let mut utf16 = Vec::with_capacity(text.len() + 1);
    let mut units = 0;
    for c in text.chars() {
        utf16.extend(std::iter::repeat_n(units, c.len_utf8()));
        units += c.len_utf16() as u32;
    }
    utf16.push(units);
    Ok(ranges
        .into_iter()
        .map(|range| MatchRange {
            start: utf16[range.start],
            end: utf16[range.end],
        })
        .collect())
}

/// Part of a text, in UTF-16 code units: from `start` up to, not including, `end`.
pub struct MatchRange {
    pub start: u32,
    pub end: u32,
}

/// The open keys of the device. Dart can hold it, but never read it.
#[frb(opaque)]
pub struct Keyring {
    inner: store::Keyring,
}

impl Keyring {
    /// A keyring with a new random master key.
    ///
    /// Until the master key is kept in the platform's key store (KRO-19), what is saved with this
    /// keyring cannot be opened again once it is dropped.
    #[frb(sync)]
    pub fn generate() -> Result<Keyring, StoreFailure> {
        let master_key = MasterKey::generate().map_err(StoreError::from)?;
        Ok(Keyring {
            inner: store::Keyring::new(master_key),
        })
    }
}

/// The device's store, open.
#[frb(opaque)]
pub struct CoreStore {
    store: Arc<Store>,
}

impl CoreStore {
    /// Opens the store in the directory `dir`, creating it if needed. The keyring is used up.
    pub fn open(dir: String, keyring: Keyring) -> Result<CoreStore, StoreFailure> {
        Ok(CoreStore {
            store: Arc::new(Store::open(Path::new(&dir), keyring.inner)?),
        })
    }

    /// Fires after every commit, until the stream is cancelled.
    pub fn watch(&self, sink: StreamSink<StoreChange>) {
        let store = Arc::downgrade(&self.store);
        let subscription = Arc::new(OnceLock::new());
        let id = self.store.subscribe({
            let subscription = Arc::clone(&subscription);
            move |change| {
                if sink.add(change.into()).is_err()
                    && let (Some(store), Some(id)) = (store.upgrade(), subscription.get())
                {
                    store.unsubscribe(*id);
                }
            }
        });
        let _ = subscription.set(id);
    }

    /// Creates a Book.
    pub fn create_book(&self, name: String) -> Result<BookItem, StoreFailure> {
        Ok(self.store.create_book(&name)?.into())
    }

    /// Renames a Book.
    pub fn rename_book(&self, id: String, name: String) -> Result<(), StoreFailure> {
        Ok(self.store.rename_book(parse_id(&id)?, &name)?)
    }

    /// Deletes a Book with all its Entries and Images.
    pub fn delete_book(&self, id: String) -> Result<(), StoreFailure> {
        Ok(self.store.delete_book(parse_id(&id)?)?)
    }

    /// Every Book, the one with the latest activity first.
    pub fn list_books(&self) -> Result<Vec<BookItem>, StoreFailure> {
        Ok(self
            .store
            .list_books()?
            .into_iter()
            .map(BookItem::from)
            .collect())
    }

    /// One Book.
    pub fn get_book(&self, id: String) -> Result<BookItem, StoreFailure> {
        Ok(self.store.get_book(parse_id(&id)?)?.into())
    }

    /// Saves a new Entry, or a change to one, and returns it as stored.
    pub fn save_entry(&self, draft: EntryDraftItem) -> Result<EntryItem, StoreFailure> {
        let draft = store::EntryDraft {
            id: draft.id.as_deref().map(parse_id).transpose()?,
            book_id: parse_id(&draft.book_id)?,
            date: parse_date(&draft.date)?,
            text: draft.text,
            images: draft
                .images
                .into_iter()
                .map(|image| match image.id {
                    Some(id) => parse_id(&id).map(ImageInput::Keep),
                    None => Ok(ImageInput::New {
                        full: image.full,
                        thumbnail: image.thumbnail,
                    }),
                })
                .collect::<Result<_, _>>()?,
        };
        Ok(self.store.save_entry(draft)?.into())
    }

    /// One Entry.
    pub fn get_entry(&self, id: String) -> Result<EntryItem, StoreFailure> {
        Ok(self.store.get_entry(parse_id(&id)?)?.into())
    }

    /// A page of a Book's Entries, newest Entry date first, starting after the Entry with
    /// `after_date` and `after_id` (both or neither).
    pub fn list_entries(
        &self,
        book_id: String,
        after_date: Option<String>,
        after_id: Option<String>,
        limit: u32,
    ) -> Result<Vec<EntryItem>, StoreFailure> {
        let after = match (after_date, after_id) {
            (Some(date), Some(id)) => Some(EntryCursor {
                date: parse_date(&date)?,
                id: parse_id(&id)?,
            }),
            (None, None) => None,
            _ => return Err(StoreFailure::invalid("give both after_date and after_id")),
        };
        Ok(self
            .store
            .list_entries(parse_id(&book_id)?, after.as_ref(), limit)?
            .into_iter()
            .map(EntryItem::from)
            .collect())
    }

    /// Deletes an Entry and its Images.
    pub fn delete_entry(&self, id: String) -> Result<(), StoreFailure> {
        Ok(self.store.delete_entry(parse_id(&id)?)?)
    }

    /// The bytes of one of an Entry's Images, at full size or as its thumbnail.
    pub fn get_image(
        &self,
        entry_id: String,
        image_id: String,
        thumbnail: bool,
    ) -> Result<Vec<u8>, StoreFailure> {
        let variant = if thumbnail {
            ImageVariant::Thumbnail
        } else {
            ImageVariant::Full
        };
        Ok(self
            .store
            .get_image(parse_id(&entry_id)?, parse_id(&image_id)?, variant)?)
    }

    /// Entries in which every word typed starts a word, newest Entry date first, within one Book
    /// if `book_id` is given. In snippets, each match is between U+E000 and U+E001.
    pub fn search(
        &self,
        query: String,
        book_id: Option<String>,
        limit: u32,
        offset: u32,
    ) -> Result<SearchPage, StoreFailure> {
        let book_id = book_id.as_deref().map(parse_id).transpose()?;
        let results = self.store.search(&query, book_id, limit, offset)?;
        Ok(SearchPage {
            hits: results
                .hits
                .into_iter()
                .map(|hit| SearchHitItem {
                    entry: hit.entry.into(),
                    snippet: hit.snippet,
                })
                .collect(),
            total: results.total,
            per_book: results
                .per_book
                .into_iter()
                .map(|count| BookCountItem {
                    book_id: count.book_id.to_hex(),
                    count: count.count,
                })
                .collect(),
        })
    }

    /// Rebuilds the lists and the search index from the encrypted Entries.
    pub fn rebuild_index(&self) -> Result<(), StoreFailure> {
        Ok(self.store.rebuild_index()?)
    }
}

/// A Book, as lists show it.
pub struct BookItem {
    pub id: String,
    pub name: String,
    /// Milliseconds since the Unix epoch.
    pub last_activity_at: i64,
    pub last_entry_text: Option<String>,
}

impl From<store::BookInfo> for BookItem {
    fn from(book: store::BookInfo) -> BookItem {
        BookItem {
            id: book.id.to_hex(),
            name: book.name,
            last_activity_at: book.last_activity_at,
            last_entry_text: book.last_entry_text,
        }
    }
}

/// An Entry as stored.
pub struct EntryItem {
    pub id: String,
    pub book_id: String,
    /// Local time with its UTC offset, as `YYYY-MM-DDTHH:MM:SS±HH:MM`.
    pub date: String,
    pub text: String,
    pub image_ids: Vec<String>,
    /// Milliseconds since the Unix epoch.
    pub created_at: i64,
    /// Milliseconds since the Unix epoch.
    pub updated_at: i64,
}

impl From<store::StoredEntry> for EntryItem {
    fn from(entry: store::StoredEntry) -> EntryItem {
        EntryItem {
            id: entry.id.to_hex(),
            book_id: entry.book_id.to_hex(),
            date: entry.date.to_string(),
            text: entry.text,
            image_ids: entry.image_ids.iter().map(Id::to_hex).collect(),
            created_at: entry.created_at,
            updated_at: entry.updated_at,
        }
    }
}

/// An Entry to save: a new one when `id` is null.
pub struct EntryDraftItem {
    pub id: Option<String>,
    pub book_id: String,
    /// Local time with its UTC offset, as `YYYY-MM-DDTHH:MM:SS±HH:MM`.
    pub date: String,
    pub text: String,
    pub images: Vec<ImageDraftItem>,
}

/// One Image of an Entry being saved: an Image it already has, by `id`, or a new one from its
/// bytes.
pub struct ImageDraftItem {
    pub id: Option<String>,
    pub full: Vec<u8>,
    pub thumbnail: Vec<u8>,
}

/// One Entry found by a search.
pub struct SearchHitItem {
    pub entry: EntryItem,
    pub snippet: String,
}

/// How many Entries of one Book match a search.
pub struct BookCountItem {
    pub book_id: String,
    pub count: u32,
}

/// A page of search results.
pub struct SearchPage {
    pub hits: Vec<SearchHitItem>,
    /// How many Entries match in all, within the Book searched if one was given.
    pub total: u32,
    /// How many Entries match in each Book, most first.
    pub per_book: Vec<BookCountItem>,
}

/// What a commit changed.
pub struct StoreChange {
    pub book_id: String,
    /// Null when the Book itself changed.
    pub entry_id: Option<String>,
}

impl From<Change> for StoreChange {
    fn from(change: Change) -> StoreChange {
        StoreChange {
            book_id: change.book_id.to_hex(),
            entry_id: change.entry_id.as_ref().map(Id::to_hex),
        }
    }
}

/// Why a store call failed.
#[derive(Debug)]
pub enum StoreFailureKind {
    /// No Book, Entry, or Image has the given ID.
    NotFound,
    /// The call cannot be done as asked: an ID, a date, or a page cursor is not valid, an Image is
    /// kept twice, or an Entry would move to another Book.
    Invalid,
    /// The database does not open with this keyring.
    WrongKey,
    /// The database was written by a newer version of the app.
    NewerSchema,
    /// Stored data failed to open, or an Image's file is gone: it was changed or damaged.
    Damaged,
    /// The database or the file system failed.
    Failed,
    /// The store exists but its master key is gone, so it cannot be opened. Nothing was changed.
    MasterKeyMissing,
    /// The master key is there but the platform's key store could not unwrap it, or its file is
    /// damaged. Nothing was changed.
    MasterKeyUnreadable,
    /// The platform's key store could not wrap a new master key. Nothing was written.
    KeyStoreFailed,
    /// This platform has no device store.
    Unsupported,
}

/// A failed store call.
#[derive(Debug)]
pub struct StoreFailure {
    pub kind: StoreFailureKind,
    pub message: String,
}

impl StoreFailure {
    fn invalid(message: &str) -> StoreFailure {
        StoreFailure {
            kind: StoreFailureKind::Invalid,
            message: message.to_owned(),
        }
    }
}

impl From<StoreError> for StoreFailure {
    fn from(error: StoreError) -> StoreFailure {
        let kind = match &error {
            StoreError::NotFound => StoreFailureKind::NotFound,
            StoreError::Invalid(_) => StoreFailureKind::Invalid,
            StoreError::ImageMissing => StoreFailureKind::Damaged,
            StoreError::WrongKey => StoreFailureKind::WrongKey,
            StoreError::NewerSchema(_) => StoreFailureKind::NewerSchema,
            StoreError::Format(_) => StoreFailureKind::Damaged,
            StoreError::Database(_) | StoreError::Io(_) => StoreFailureKind::Failed,
        };
        StoreFailure {
            kind,
            message: error.to_string(),
        }
    }
}

impl From<DeviceError> for StoreFailure {
    fn from(error: DeviceError) -> StoreFailure {
        let kind = match error {
            DeviceError::Store(error) => return error.into(),
            DeviceError::MasterKeyMissing => StoreFailureKind::MasterKeyMissing,
            DeviceError::CannotUnwrap(_) | DeviceError::KeyFileDamaged => {
                StoreFailureKind::MasterKeyUnreadable
            }
            DeviceError::CannotWrap(_) => StoreFailureKind::KeyStoreFailed,
            DeviceError::Io(_) => StoreFailureKind::Failed,
        };
        StoreFailure {
            kind,
            message: error.to_string(),
        }
    }
}

fn parse_id(text: &str) -> Result<Id, StoreFailure> {
    Id::from_hex(text).map_err(|_| StoreFailure::invalid("an ID is 32 lowercase hex digits"))
}

fn parse_date(text: &str) -> Result<EntryDate, StoreFailure> {
    EntryDate::parse(text)
        .map_err(|_| StoreFailure::invalid("an Entry date is YYYY-MM-DDTHH:MM:SS±HH:MM"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn match_ranges_count_utf16_code_units() {
        let ranges = match_ranges("Ké 🌧 hujan".to_owned(), "huj".to_owned()).unwrap();
        let ranges: Vec<(u32, u32)> = ranges.iter().map(|r| (r.start, r.end)).collect();
        assert_eq!(ranges, [(6, 11)]);
    }
}
