//! Books, Entries, and Images on the device, through the core's encrypted store.
//!
//! Dart sends and receives plaintext content and IDs only. Keys stay in Rust: Dart holds a
//! [`Keyring`] and a [`CoreStore`] as opaque handles it cannot read.

use std::path::Path;
use std::sync::{Arc, OnceLock};

use flutter_rust_bridge::frb;
use kronoer_core::store::{
    self, Change, DeviceError, EntryCursor, EntryOrder, ImageInput, Store, StoreError, TrashContent,
};
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

/// How many words an Entry's text holds, by the rule a Book insight counts them with: Text style
/// marks are not words.
#[frb(sync)]
pub fn count_words(text: String) -> u32 {
    store::count_words(&text)
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
    /// A keyring with a new random master key that is not kept anywhere, for tests and throwaway
    /// stores: what is saved with it cannot be opened again once it is dropped. The app's own
    /// store comes from [`open_device_store`], which keeps its master key in the platform's key
    /// store.
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

    /// Sets a Book's Description. An empty one removes it.
    pub fn set_book_description(
        &self,
        id: String,
        description: String,
    ) -> Result<(), StoreFailure> {
        Ok(self
            .store
            .set_book_description(parse_id(&id)?, &description)?)
    }

    /// Gives a Book a new Cover from the bytes of its full-size image and its thumbnail, in
    /// place of the one it had.
    pub fn set_book_cover(
        &self,
        id: String,
        full: Vec<u8>,
        thumbnail: Vec<u8>,
    ) -> Result<(), StoreFailure> {
        Ok(self
            .store
            .set_book_cover(parse_id(&id)?, &full, &thumbnail)?)
    }

    /// Removes a Book's Cover.
    pub fn remove_book_cover(&self, id: String) -> Result<(), StoreFailure> {
        Ok(self.store.remove_book_cover(parse_id(&id)?)?)
    }

    /// The bytes of a Book's Cover, at full size or as its thumbnail. Fails with `NotFound` when
    /// the Book has no Cover.
    pub fn get_book_cover(&self, id: String, thumbnail: bool) -> Result<Vec<u8>, StoreFailure> {
        Ok(self
            .store
            .get_book_cover(parse_id(&id)?, variant(thumbnail))?)
    }

    /// Moves a Book to the Trash, with its Entries. It is no longer pinned or kept out of the
    /// Timeline.
    pub fn trash_book(&self, id: String) -> Result<(), StoreFailure> {
        Ok(self.store.trash_book(parse_id(&id)?)?)
    }

    /// Moves Entries to the Trash, all of them or none.
    pub fn trash_entries(&self, ids: Vec<String>) -> Result<(), StoreFailure> {
        Ok(self.store.trash_entries(&parse_ids(&ids)?)?)
    }

    /// Takes Books and Entries out of the Trash, all of them or none. An Entry whose Book is in
    /// the Trash and not restored with it goes to the Book `others_to`; with none, its Book is
    /// restored too.
    pub fn restore(
        &self,
        book_ids: Vec<String>,
        entry_ids: Vec<String>,
        others_to: Option<String>,
    ) -> Result<(), StoreFailure> {
        Ok(self.store.restore(
            &parse_ids(&book_ids)?,
            &parse_ids(&entry_ids)?,
            others_to.as_deref().map(parse_id).transpose()?,
        )?)
    }

    /// Deletes Books and Entries for good, all of them or none. A Book goes with all its Entries.
    pub fn delete_forever(
        &self,
        book_ids: Vec<String>,
        entry_ids: Vec<String>,
    ) -> Result<(), StoreFailure> {
        Ok(self
            .store
            .delete_forever(&parse_ids(&book_ids)?, &parse_ids(&entry_ids)?)?)
    }

    /// Deletes everything in the Trash for good.
    pub fn empty_trash(&self) -> Result<(), StoreFailure> {
        Ok(self.store.empty_trash()?)
    }

    /// Every Book and Entry in the Trash, the one deleted most recently first.
    pub fn list_trash(&self) -> Result<Vec<TrashedItem>, StoreFailure> {
        Ok(self
            .store
            .list_trash()?
            .into_iter()
            .map(TrashedItem::from)
            .collect())
    }

    /// How many items the Trash holds.
    pub fn trash_count(&self) -> Result<u32, StoreFailure> {
        Ok(self.store.trash_count()?)
    }

    /// How many days the Trash keeps what is deleted: 7, 30, or 90.
    pub fn trash_days(&self) -> Result<u32, StoreFailure> {
        Ok(self.store.trash_days()?)
    }

    /// Sets how many days the Trash keeps what is deleted, 7, 30, or 90, and deletes for good at
    /// once what was deleted longer ago than that. Other numbers fail with `Invalid`.
    pub fn set_trash_days(&self, days: u32) -> Result<(), StoreFailure> {
        Ok(self.store.set_trash_days(days)?)
    }

    /// Pins or unpins Books on this device. Fails with `TooManyPinned`, pinning none of them, if
    /// that would make more Pinned Books than allowed.
    pub fn set_books_pinned(&self, ids: Vec<String>, pinned: bool) -> Result<(), StoreFailure> {
        let ids = ids
            .iter()
            .map(|id| parse_id(id))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(self.store.set_books_pinned(&ids, pinned)?)
    }

    /// Keeps a Book out of the Timeline on this device, or puts it back in.
    pub fn set_book_in_timeline(&self, id: String, in_timeline: bool) -> Result<(), StoreFailure> {
        Ok(self
            .store
            .set_book_in_timeline(parse_id(&id)?, in_timeline)?)
    }

    /// Every Book: the Pinned Books first, then the rest, each with the latest activity first.
    pub fn list_books(&self) -> Result<Vec<BookItem>, StoreFailure> {
        Ok(self
            .store
            .list_books()?
            .into_iter()
            .map(BookItem::from)
            .collect())
    }

    /// One Book, in the Trash or not.
    pub fn get_book(&self, id: String) -> Result<BookItem, StoreFailure> {
        Ok(self.store.get_book(parse_id(&id)?)?.into())
    }

    /// How many Entries, words, and Images a Book holds.
    pub fn book_insight(&self, id: String) -> Result<BookInsightItem, StoreFailure> {
        let insight = self.store.book_insight(parse_id(&id)?)?;
        Ok(BookInsightItem {
            entry_count: insight.entry_count,
            word_count: insight.word_count,
            image_count: insight.image_count,
        })
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

    /// A page of a Book's Entries in `order`, starting after the Entry `after` points at, or at
    /// the top.
    pub fn list_entries(
        &self,
        book_id: String,
        order: EntryOrderItem,
        after: Option<EntryCursorItem>,
        limit: u32,
    ) -> Result<Vec<EntryItem>, StoreFailure> {
        let after = after.map(EntryCursorItem::parse).transpose()?;
        Ok(self
            .store
            .list_entries(parse_id(&book_id)?, order.into(), after.as_ref(), limit)?
            .into_iter()
            .map(EntryItem::from)
            .collect())
    }

    /// A page of a Book's Starred Entries, newest first, starting after the Entry `after` points
    /// at, or at the top.
    pub fn list_starred_entries(
        &self,
        book_id: String,
        after: Option<EntryCursorItem>,
        limit: u32,
    ) -> Result<Vec<EntryItem>, StoreFailure> {
        let after = after.map(EntryCursorItem::parse).transpose()?;
        Ok(self
            .store
            .list_starred_entries(parse_id(&book_id)?, after.as_ref(), limit)?
            .into_iter()
            .map(EntryItem::from)
            .collect())
    }

    /// Stars or unstars Entries, all of them or none. Starring is not editing: the Entries do
    /// not change.
    pub fn set_entries_starred(&self, ids: Vec<String>, starred: bool) -> Result<(), StoreFailure> {
        Ok(self.store.set_entries_starred(&parse_ids(&ids)?, starred)?)
    }

    /// A page of the Entries in every Book in `order`, starting after the Entry `after` points
    /// at, or at the top: the Timeline.
    pub fn list_all_entries(
        &self,
        order: EntryOrderItem,
        after: Option<EntryCursorItem>,
        limit: u32,
    ) -> Result<Vec<EntryItem>, StoreFailure> {
        let after = after.map(EntryCursorItem::parse).transpose()?;
        Ok(self
            .store
            .list_all_entries(order.into(), after.as_ref(), limit)?
            .into_iter()
            .map(EntryItem::from)
            .collect())
    }

    /// The earliest day with an Entry in the Timeline, as `YYYY-MM-DD` in local time
    /// `utc_offset_minutes` east of UTC; none when the Timeline has no Entry.
    pub fn oldest_timeline_day(
        &self,
        utc_offset_minutes: i32,
    ) -> Result<Option<String>, StoreFailure> {
        Ok(self.store.oldest_timeline_day(utc_offset_minutes)?)
    }

    /// The days from `from` to `to`, both `YYYY-MM-DD` and both included, with an Entry in the
    /// Timeline, in local time `utc_offset_minutes` east of UTC, earliest first.
    pub fn timeline_days(
        &self,
        from: String,
        to: String,
        utc_offset_minutes: i32,
    ) -> Result<Vec<String>, StoreFailure> {
        Ok(self.store.timeline_days(&from, &to, utc_offset_minutes)?)
    }

    /// Moves Entries to another Book, all of them or none. Each keeps its ID, content, and times.
    pub fn move_entries(&self, ids: Vec<String>, book_id: String) -> Result<(), StoreFailure> {
        Ok(self
            .store
            .move_entries(&parse_ids(&ids)?, parse_id(&book_id)?)?)
    }

    /// The bytes of one of an Entry's Images, at full size or as its thumbnail.
    pub fn get_image(
        &self,
        entry_id: String,
        image_id: String,
        thumbnail: bool,
    ) -> Result<Vec<u8>, StoreFailure> {
        Ok(self.store.get_image(
            parse_id(&entry_id)?,
            parse_id(&image_id)?,
            variant(thumbnail),
        )?)
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
    /// Empty when the Book has no Description.
    pub description: String,
    /// The Image ID of the Book's Cover; `None` when it has none. It changes with the Cover.
    pub cover_id: Option<String>,
    /// Milliseconds since the Unix epoch.
    pub last_activity_at: i64,
    /// Empty when the latest Entry has only Images; `None` when the Book has no Entries.
    pub last_entry_text: Option<String>,
    /// How many Images the latest Entry has.
    pub last_entry_image_count: u32,
    /// How many Entries the Book has.
    pub entry_count: u32,
    /// Whether the user pinned the Book on this device.
    pub pinned: bool,
    /// Whether the Book's Entries show in the Timeline on this device.
    pub in_timeline: bool,
}

impl From<store::BookInfo> for BookItem {
    fn from(book: store::BookInfo) -> BookItem {
        BookItem {
            id: book.id.to_hex(),
            name: book.name,
            description: book.description,
            cover_id: book.cover_id.as_ref().map(Id::to_hex),
            last_activity_at: book.last_activity_at,
            last_entry_text: book.last_entry_text,
            last_entry_image_count: book.last_entry_image_count,
            entry_count: book.entry_count,
            pinned: book.pinned,
            in_timeline: book.in_timeline,
        }
    }
}

/// A Book or an Entry in the Trash: `book` or `entry` is set.
pub struct TrashedItem {
    /// Milliseconds since the Unix epoch.
    pub deleted_at: i64,
    /// When it is deleted for good, in milliseconds since the Unix epoch.
    pub purge_at: i64,
    /// The Book; its Entry count counts the Entries that come back with it.
    pub book: Option<BookItem>,
    /// The Entry.
    pub entry: Option<EntryItem>,
    /// The name of the Entry's Book; empty for a Book.
    pub book_name: String,
    /// Whether the Entry's Book is in the Trash too.
    pub book_in_trash: bool,
}

impl From<store::TrashItem> for TrashedItem {
    fn from(item: store::TrashItem) -> TrashedItem {
        let mut dto = TrashedItem {
            deleted_at: item.deleted_at,
            purge_at: item.purge_at,
            book: None,
            entry: None,
            book_name: String::new(),
            book_in_trash: false,
        };
        match item.content {
            TrashContent::Book(book) => dto.book = Some(book.into()),
            TrashContent::Entry {
                entry,
                book_name,
                book_in_trash,
            } => {
                dto.entry = Some(entry.into());
                dto.book_name = book_name;
                dto.book_in_trash = book_in_trash;
            }
        }
        dto
    }
}

/// How many Entries, words, and Images a Book holds. The Cover is not one of its Images.
pub struct BookInsightItem {
    pub entry_count: u32,
    pub word_count: u32,
    pub image_count: u32,
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
    /// Whether the user starred the Entry.
    pub starred: bool,
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
            starred: entry.starred,
        }
    }
}

/// The order a list of Entries comes in, by Entry date. Entries with the same date come in the
/// order they were written.
pub enum EntryOrderItem {
    NewestFirst,
    OldestFirst,
}

impl From<EntryOrderItem> for EntryOrder {
    fn from(order: EntryOrderItem) -> EntryOrder {
        match order {
            EntryOrderItem::NewestFirst => EntryOrder::NewestFirst,
            EntryOrderItem::OldestFirst => EntryOrder::OldestFirst,
        }
    }
}

/// Where a page of Entries ends: the last Entry on it. The next page starts after it.
pub struct EntryCursorItem {
    /// Local time with its UTC offset, as `YYYY-MM-DDTHH:MM:SS±HH:MM`.
    pub date: String,
    /// Milliseconds since the Unix epoch.
    pub created_at: i64,
    pub id: String,
}

impl EntryCursorItem {
    fn parse(self) -> Result<EntryCursor, StoreFailure> {
        Ok(EntryCursor {
            date: parse_date(&self.date)?,
            created_at: self.created_at,
            id: parse_id(&self.id)?,
        })
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
    /// Pinning would make more Pinned Books than allowed. Nothing was pinned.
    TooManyPinned,
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
            StoreError::TooManyPinned => StoreFailureKind::TooManyPinned,
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

fn variant(thumbnail: bool) -> ImageVariant {
    if thumbnail {
        ImageVariant::Thumbnail
    } else {
        ImageVariant::Full
    }
}

fn parse_id(text: &str) -> Result<Id, StoreFailure> {
    Id::from_hex(text).map_err(|_| StoreFailure::invalid("an ID is 32 lowercase hex digits"))
}

fn parse_ids(texts: &[String]) -> Result<Vec<Id>, StoreFailure> {
    texts.iter().map(|text| parse_id(text)).collect()
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
