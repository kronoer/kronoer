use std::fs::{self, File};
use std::sync::atomic::Ordering;

use tempfile::TempDir;

use super::*;
use crate::MasterKey;

const SECRET: [u8; 32] = [7; 32];

fn keyring() -> Keyring {
    Keyring::new(MasterKey::from_secret(Zeroizing::new(SECRET)))
}

fn open(dir: &TempDir) -> Store {
    Store::open(dir.path(), keyring()).unwrap()
}

fn date(text: &str) -> EntryDate {
    EntryDate::parse(text).unwrap()
}

fn draft(book_id: Id, date_text: &str, text: &str) -> EntryDraft {
    EntryDraft {
        id: None,
        book_id,
        date: date(date_text),
        text: text.to_owned(),
        images: Vec::new(),
    }
}

fn new_image(name: &str) -> ImageInput {
    ImageInput::New {
        full: format!("{name} full").into_bytes(),
        thumbnail: format!("{name} thumbnail").into_bytes(),
    }
}

fn image_files(dir: &TempDir) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(dir.path().join(IMAGES_DIR))
        .unwrap()
        .map(|item| item.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

fn count(store: &Store, table: &str) -> i64 {
    lock(&store.inner)
        .conn
        .query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
}

#[test]
fn books_round_trip_and_survive_reopening() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    store.rename_book(garden.id, "Kebun belakang").unwrap();
    drop(store);

    let store = open(&dir);
    let garden = store.get_book(garden.id).unwrap();
    assert_eq!(garden.name, "Kebun belakang");
    assert_eq!(garden.last_entry_text, None);
    let names: Vec<String> = store
        .list_books()
        .unwrap()
        .into_iter()
        .map(|book| book.name)
        .collect();
    assert_eq!(names.len(), 2);
    assert!(names.contains(&"Perjalanan".to_owned()));
    assert_eq!(store.get_book(trips.id).unwrap().name, "Perjalanan");
}

#[test]
fn books_keep_a_description_through_renames_and_reopening() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    assert_eq!(book.description, "");

    store
        .set_book_description(book.id, "Sayur dan bunga.\nSejak 2024.")
        .unwrap();
    store.rename_book(book.id, "Kebun belakang").unwrap();
    drop(store);

    let store = open(&dir);
    let book = store.get_book(book.id).unwrap();
    assert_eq!(book.name, "Kebun belakang");
    assert_eq!(book.description, "Sayur dan bunga.\nSejak 2024.");
    assert_eq!(store.list_books().unwrap(), vec![book.clone()]);

    store.set_book_description(book.id, "").unwrap();
    assert_eq!(store.get_book(book.id).unwrap().description, "");
    assert!(matches!(
        store.set_book_description(Id::random().unwrap(), "Tidak ada."),
        Err(StoreError::NotFound)
    ));
}

#[test]
fn the_description_is_not_searched() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    store.set_book_description(book.id, "Tomat").unwrap();
    store
        .save_entry(draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi."))
        .unwrap();

    assert_eq!(store.search("tomat", None, 10, 0).unwrap().total, 0);
}

#[test]
fn covers_round_trip_replace_and_remove_their_files() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    assert!(matches!(
        store.get_book_cover(book.id, ImageVariant::Full),
        Err(StoreError::NotFound)
    ));

    store
        .set_book_cover(book.id, b"first full", b"first thumb")
        .unwrap();
    let first = image_files(&dir);
    assert_eq!(first.len(), 2);
    let first_id = store.get_book(book.id).unwrap().cover_id.unwrap();
    assert!(first[0].starts_with(&first_id.to_hex()));
    store
        .set_book_cover(book.id, b"second full", b"second thumb")
        .unwrap();
    let second = image_files(&dir);
    assert_eq!(second.len(), 2);
    assert!(first.iter().all(|name| !second.contains(name)));
    let second_id = store.list_books().unwrap()[0].cover_id.unwrap();
    assert_ne!(second_id, first_id);

    // Changing the name or the Description keeps the Cover.
    store.rename_book(book.id, "Kebun belakang").unwrap();
    store.set_book_description(book.id, "Sayur.").unwrap();
    drop(store);
    let store = open(&dir);
    assert_eq!(
        store.get_book_cover(book.id, ImageVariant::Full).unwrap(),
        b"second full"
    );
    assert_eq!(
        store
            .get_book_cover(book.id, ImageVariant::Thumbnail)
            .unwrap(),
        b"second thumb"
    );

    store.remove_book_cover(book.id).unwrap();
    assert!(image_files(&dir).is_empty());
    assert_eq!(store.get_book(book.id).unwrap().cover_id, None);
    assert!(matches!(
        store.get_book_cover(book.id, ImageVariant::Full),
        Err(StoreError::NotFound)
    ));
    store.remove_book_cover(book.id).unwrap();
}

#[test]
fn a_cover_for_a_missing_book_leaves_no_files() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);

    assert!(matches!(
        store.set_book_cover(Id::random().unwrap(), b"full", b"thumb"),
        Err(StoreError::NotFound)
    ));
    assert!(image_files(&dir).is_empty());
}

#[test]
fn deleting_a_book_deletes_its_cover() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let kept = store.create_book("Perjalanan").unwrap();
    store.set_book_cover(book.id, b"full", b"thumb").unwrap();
    store
        .set_book_cover(kept.id, b"kept full", b"kept thumb")
        .unwrap();

    store.delete_forever(&[book.id], &[]).unwrap();

    assert_eq!(image_files(&dir).len(), 2);
    assert_eq!(
        store.get_book_cover(kept.id, ImageVariant::Full).unwrap(),
        b"kept full"
    );
}

#[test]
fn books_show_the_text_and_image_count_of_their_latest_entry() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let save = |name: &str, text: &str, images: Vec<ImageInput>| {
        let book = store.create_book(name).unwrap();
        store
            .save_entry(EntryDraft {
                images,
                ..draft(book.id, "2026-11-17T08:00:00+07:00", text)
            })
            .unwrap();
        book.id
    };
    let text_only = save("Teks", "Hujan.", Vec::new());
    let both = save("Keduanya", "Kebun.", vec![new_image("a"), new_image("b")]);
    let images_only = save("Foto", "", vec![new_image("c")]);
    let empty = store.create_book("Kosong").unwrap().id;

    let shown = |id: Id| {
        let book = store.get_book(id).unwrap();
        (book.last_entry_text, book.last_entry_image_count)
    };
    assert_eq!(shown(text_only), (Some("Hujan.".to_owned()), 0));
    assert_eq!(shown(both), (Some("Kebun.".to_owned()), 2));
    assert_eq!(shown(images_only), (Some(String::new()), 1));
    assert_eq!(shown(empty), (None, 0));

    let listed: Vec<(Id, u32)> = store
        .list_books()
        .unwrap()
        .into_iter()
        .map(|book| (book.id, book.last_entry_image_count))
        .collect();
    assert_eq!(listed.len(), 4);
    assert!(listed.contains(&(both, 2)));
    assert!(listed.contains(&(images_only, 1)));
}

#[test]
fn refuses_another_master_key() {
    let dir = TempDir::new().unwrap();
    open(&dir).create_book("Kebun").unwrap();

    let other = Keyring::new(MasterKey::from_secret(Zeroizing::new([8; 32])));
    assert!(matches!(
        Store::open(dir.path(), other),
        Err(StoreError::WrongKey)
    ));
}

#[test]
fn the_database_file_is_encrypted() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun rahasia").unwrap();
    store
        .save_entry(draft(
            book.id,
            "2026-11-17T08:00:00+07:00",
            "kalimat yang sangat rahasia",
        ))
        .unwrap();
    drop(store);

    let mut bytes = fs::read(dir.path().join(DATABASE_FILE)).unwrap();
    if let Ok(wal) = fs::read(dir.path().join(format!("{DATABASE_FILE}-wal"))) {
        bytes.extend(wal);
    }
    let contains = |needle: &[u8]| bytes.windows(needle.len()).any(|w| w == needle);
    assert!(!contains(b"SQLite format 3"));
    assert!(!contains(b"rahasia"));
}

#[test]
fn entries_round_trip_with_images() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat"), new_image("cabai")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Tomat mulai merah.")
        })
        .unwrap();

    assert_eq!(saved.text, "Tomat mulai merah.");
    assert_eq!(saved.image_ids.len(), 2);
    assert_eq!(saved.created_at, saved.updated_at);
    assert_eq!(image_files(&dir).len(), 4);
    drop(store);

    let store = open(&dir);
    assert_eq!(store.get_entry(saved.id).unwrap(), saved);
    assert_eq!(
        store
            .list_entries(book.id, EntryOrder::NewestFirst, None, 10)
            .unwrap(),
        vec![saved.clone()]
    );
    assert_eq!(
        store
            .get_image(saved.id, saved.image_ids[0], ImageVariant::Full)
            .unwrap(),
        b"tomat full"
    );
    assert_eq!(
        store
            .get_image(saved.id, saved.image_ids[1], ImageVariant::Thumbnail)
            .unwrap(),
        b"cabai thumbnail"
    );
    let book = store.get_book(book.id).unwrap();
    assert_eq!(book.last_entry_text.as_deref(), Some("Tomat mulai merah."));
    assert_eq!(book.last_activity_at, saved.updated_at);
}

#[test]
fn editing_keeps_and_drops_images() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let first = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat"), new_image("cabai")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
        })
        .unwrap();
    let (tomato, chili) = (first.image_ids[0], first.image_ids[1]);

    let edited = store
        .save_entry(EntryDraft {
            id: Some(first.id),
            images: vec![new_image("terong"), ImageInput::Keep(chili)],
            ..draft(book.id, "2026-11-17T09:00:00+07:00", "Pagi, diedit.")
        })
        .unwrap();

    assert_eq!(edited.id, first.id);
    assert_eq!(edited.created_at, first.created_at);
    assert_eq!(edited.date, date("2026-11-17T09:00:00+07:00"));
    assert_eq!(edited.image_ids[1], chili);
    assert!(!edited.image_ids.contains(&tomato));
    assert_eq!(store.get_entry(first.id).unwrap(), edited);
    assert_eq!(
        store
            .get_image(edited.id, chili, ImageVariant::Full)
            .unwrap(),
        b"cabai full"
    );
    assert!(
        !image_files(&dir)
            .iter()
            .any(|name| name.starts_with(&tomato.to_hex()))
    );
    assert_eq!(image_files(&dir).len(), 4);
    assert_eq!(count(&store, "entry_search"), 1);
}

#[test]
fn keeping_an_image_the_entry_does_not_have_fails() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();

    let result = store.save_entry(EntryDraft {
        images: vec![new_image("tomat"), ImageInput::Keep(Id::random().unwrap())],
        ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
    });

    assert!(matches!(result, Err(StoreError::NotFound)));
    assert_eq!(image_files(&dir), Vec::<String>::new());
}

#[test]
fn an_entry_cannot_move_to_another_book() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let saved = store
        .save_entry(draft(garden.id, "2026-11-17T08:00:00+07:00", "Pagi."))
        .unwrap();

    let result = store.save_entry(EntryDraft {
        id: Some(saved.id),
        ..draft(trips.id, "2026-11-17T08:00:00+07:00", "Pindah.")
    });

    assert!(matches!(result, Err(StoreError::Invalid(_))));
    assert_eq!(store.get_entry(saved.id).unwrap(), saved);
}

#[test]
fn keeping_an_image_twice_fails_before_writing_files() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
        })
        .unwrap();
    let tomato = saved.image_ids[0];

    let result = store.save_entry(EntryDraft {
        id: Some(saved.id),
        images: vec![
            ImageInput::Keep(tomato),
            new_image("cabai"),
            ImageInput::Keep(tomato),
        ],
        ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
    });

    assert!(matches!(result, Err(StoreError::Invalid(_))));
    assert_eq!(image_files(&dir).len(), 2);
}

#[test]
fn a_failed_image_write_leaves_no_files() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();

    store.fail_image_write.store(true, Ordering::SeqCst);
    let result = store.save_entry(EntryDraft {
        images: vec![new_image("tomat"), new_image("cabai")],
        ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
    });

    assert!(matches!(result, Err(StoreError::Io(_))));
    assert_eq!(image_files(&dir), Vec::<String>::new());
    assert_eq!(count(&store, "entry"), 0);
}

#[test]
fn a_missing_image_file_is_reported_as_missing() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
        })
        .unwrap();
    fs::remove_file(
        store
            .files
            .path(saved.image_ids[0], ImageVariant::Thumbnail),
    )
    .unwrap();

    assert!(matches!(
        store.get_image(saved.id, saved.image_ids[0], ImageVariant::Thumbnail),
        Err(StoreError::ImageMissing)
    ));
}

#[test]
fn refuses_a_database_from_a_newer_schema() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    lock(&store.inner)
        .conn
        .pragma_update(None, "user_version", schema::VERSION + 1)
        .unwrap();
    drop(store);

    assert!(matches!(
        Store::open(dir.path(), keyring()),
        Err(StoreError::NewerSchema(version)) if version == schema::VERSION + 1
    ));
}

/// Saves Entries one after another, a little apart so each is written at a later millisecond.
fn save_in_turn(store: &Store, drafts: impl IntoIterator<Item = EntryDraft>) -> Vec<StoredEntry> {
    drafts
        .into_iter()
        .map(|draft| {
            std::thread::sleep(Duration::from_millis(2));
            store.save_entry(draft).unwrap()
        })
        .collect()
}

/// Every Entry `list_page` gives, page after page of `limit`.
fn every_page(
    limit: u32,
    list_page: impl Fn(Option<&EntryCursor>, u32) -> Result<Vec<StoredEntry>>,
) -> Vec<StoredEntry> {
    let mut listed = Vec::new();
    let mut after: Option<EntryCursor> = None;
    loop {
        let page = list_page(after.as_ref(), limit).unwrap();
        let Some(last) = page.last() else { break };
        after = Some(last.into());
        listed.extend(page);
    }
    listed
}

fn texts(entries: &[StoredEntry]) -> Vec<&str> {
    entries.iter().map(|entry| entry.text.as_str()).collect()
}

#[test]
fn entries_with_the_same_date_come_in_the_order_written() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = save_in_turn(
        &store,
        (0..5).map(|i| draft(book.id, "2026-11-17T08:00:00+07:00", &format!("Sama {i}"))),
    );
    // Editing an Entry does not move it among those of its date.
    store
        .save_entry(EntryDraft {
            id: Some(saved[0].id),
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Sama 0, diubah")
        })
        .unwrap();

    let newest = every_page(2, |after, limit| {
        store.list_entries(book.id, EntryOrder::NewestFirst, after, limit)
    });
    let oldest = every_page(2, |after, limit| {
        store.list_entries(book.id, EntryOrder::OldestFirst, after, limit)
    });

    assert_eq!(
        texts(&newest),
        ["Sama 4", "Sama 3", "Sama 2", "Sama 1", "Sama 0, diubah"]
    );
    assert_eq!(
        texts(&oldest),
        ["Sama 0, diubah", "Sama 1", "Sama 2", "Sama 3", "Sama 4"]
    );
}

#[test]
fn lists_a_books_entries_in_pages_either_way() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let other = store.create_book("Lain").unwrap();
    for day in [3, 1, 5, 2, 4] {
        store
            .save_entry(draft(
                book.id,
                &format!("2026-11-0{day}T08:00:00+07:00"),
                &format!("Hari {day}"),
            ))
            .unwrap();
    }
    store
        .save_entry(draft(other.id, "2026-11-09T08:00:00+07:00", "Lain"))
        .unwrap();

    let newest = every_page(2, |after, limit| {
        store.list_entries(book.id, EntryOrder::NewestFirst, after, limit)
    });
    let oldest = every_page(2, |after, limit| {
        store.list_entries(book.id, EntryOrder::OldestFirst, after, limit)
    });

    assert_eq!(
        texts(&newest),
        ["Hari 5", "Hari 4", "Hari 3", "Hari 2", "Hari 1"]
    );
    assert_eq!(
        texts(&oldest),
        ["Hari 1", "Hari 2", "Hari 3", "Hari 4", "Hari 5"]
    );
}

#[test]
fn lists_entries_of_every_book_in_pages_either_way() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let kebun = store.create_book("Kebun").unwrap();
    let jalan = store.create_book("Jalan").unwrap();
    save_in_turn(
        &store,
        [
            draft(kebun.id, "2026-11-03T08:00:00+07:00", "Kebun 3"),
            draft(jalan.id, "2026-11-05T08:00:00+07:00", "Jalan 5"),
            draft(kebun.id, "2019-06-01T08:00:00+07:00", "Kebun 2019"),
            draft(jalan.id, "2026-11-03T08:00:00+07:00", "Jalan 3"),
            draft(kebun.id, "2026-11-04T08:00:00+07:00", "Kebun 4"),
        ],
    );

    let newest = every_page(2, |after, limit| {
        store.list_all_entries(EntryOrder::NewestFirst, after, limit)
    });
    let oldest = every_page(2, |after, limit| {
        store.list_all_entries(EntryOrder::OldestFirst, after, limit)
    });

    assert_eq!(
        texts(&newest),
        ["Jalan 5", "Kebun 4", "Jalan 3", "Kebun 3", "Kebun 2019"]
    );
    assert_eq!(
        texts(&oldest),
        ["Kebun 2019", "Kebun 3", "Jalan 3", "Kebun 4", "Jalan 5"]
    );
}

#[test]
fn books_kept_out_of_the_timeline_leave_it_and_nothing_else() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let kebun = store.create_book("Kebun").unwrap();
    let jalan = store.create_book("Jalan").unwrap();
    assert!(kebun.in_timeline);
    save_in_turn(
        &store,
        [
            draft(kebun.id, "2026-11-03T08:00:00+07:00", "Kebun 3 pagi"),
            draft(jalan.id, "2026-11-05T08:00:00+07:00", "Jalan 5 pagi"),
            draft(kebun.id, "2026-11-04T08:00:00+07:00", "Kebun 4 pagi"),
            draft(jalan.id, "2026-11-01T08:00:00+07:00", "Jalan 1 pagi"),
            draft(jalan.id, "2026-11-04T09:00:00+07:00", "Jalan 4 pagi"),
        ],
    );

    store.set_book_in_timeline(kebun.id, false).unwrap();
    // Keeping it out again changes nothing.
    store.set_book_in_timeline(kebun.id, false).unwrap();

    for (order, expected) in [
        (
            EntryOrder::NewestFirst,
            ["Jalan 5 pagi", "Jalan 4 pagi", "Jalan 1 pagi"],
        ),
        (
            EntryOrder::OldestFirst,
            ["Jalan 1 pagi", "Jalan 4 pagi", "Jalan 5 pagi"],
        ),
    ] {
        let listed = every_page(2, |after, limit| {
            store.list_all_entries(order, after, limit)
        });
        assert_eq!(texts(&listed), expected, "{order:?}");
    }
    assert!(!store.get_book(kebun.id).unwrap().in_timeline);
    assert!(store.get_book(jalan.id).unwrap().in_timeline);
    // Its own list, the Book list, and search still have it.
    assert_eq!(
        store
            .list_entries(kebun.id, EntryOrder::NewestFirst, None, 10)
            .unwrap()
            .len(),
        2
    );
    let books = store.list_books().unwrap();
    assert!(
        books
            .iter()
            .any(|book| book.id == kebun.id && !book.in_timeline)
    );
    assert_eq!(store.search("pagi", None, 10, 0).unwrap().total, 5);

    store.set_book_in_timeline(kebun.id, true).unwrap();
    let listed = every_page(10, |after, limit| {
        store.list_all_entries(EntryOrder::NewestFirst, after, limit)
    });
    assert_eq!(listed.len(), 5);
    assert!(store.get_book(kebun.id).unwrap().in_timeline);
}

#[test]
fn timeline_days_are_the_days_at_the_offset_given() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let kebun = store.create_book("Kebun").unwrap();
    let jalan = store.create_book("Jalan").unwrap();
    for (book, date_text) in [
        // 16:30 UTC on 3 November.
        (kebun.id, "2026-11-03T23:30:00+07:00"),
        // 18:00 UTC on 3 November.
        (kebun.id, "2026-11-04T01:00:00+07:00"),
        (kebun.id, "2026-11-10T08:00:00+07:00"),
        (kebun.id, "2026-11-10T09:00:00+07:00"),
        (jalan.id, "2026-11-07T08:00:00+07:00"),
        (kebun.id, "2026-10-31T12:00:00+07:00"),
    ] {
        store.save_entry(draft(book, date_text, "")).unwrap();
    }

    let days = |from, to, offset| store.timeline_days(from, to, offset).unwrap();
    // Each day once, earliest first, both ends included.
    assert_eq!(
        days("2026-11-03", "2026-11-10", 7 * 60),
        ["2026-11-03", "2026-11-04", "2026-11-07", "2026-11-10"]
    );
    // In UTC both early Entries are on the 3rd; ten hours east, both on the 4th.
    assert_eq!(days("2026-11-01", "2026-11-05", 0), ["2026-11-03"]);
    assert_eq!(days("2026-11-01", "2026-11-05", 10 * 60), ["2026-11-04"]);
    assert_eq!(
        days("2026-11-11", "2026-11-30", 7 * 60),
        Vec::<String>::new()
    );
    assert_eq!(
        days("2026-11-10", "2026-11-03", 7 * 60),
        Vec::<String>::new()
    );

    // A Book kept out of the Timeline counts for nothing.
    store.set_book_in_timeline(jalan.id, false).unwrap();
    assert_eq!(
        days("2026-11-05", "2026-11-09", 7 * 60),
        Vec::<String>::new()
    );
}

#[test]
fn the_oldest_timeline_day_is_at_the_offset_given() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let kebun = store.create_book("Kebun").unwrap();
    let jalan = store.create_book("Jalan").unwrap();
    assert_eq!(store.oldest_timeline_day(0).unwrap(), None);

    // Written on the 1st, but 06:00 UTC on the 2nd.
    store
        .save_entry(draft(kebun.id, "2026-11-01T20:00:00-10:00", ""))
        .unwrap();
    // Written on the 2nd, but 10:30 UTC on the 1st: the earlier one in UTC.
    store
        .save_entry(draft(kebun.id, "2026-11-02T00:30:00+14:00", ""))
        .unwrap();
    store
        .save_entry(draft(kebun.id, "2026-12-01T08:00:00+07:00", ""))
        .unwrap();
    store
        .save_entry(draft(jalan.id, "2025-06-01T08:00:00+07:00", ""))
        .unwrap();
    store.set_book_in_timeline(jalan.id, false).unwrap();

    assert_eq!(
        store.oldest_timeline_day(0).unwrap().as_deref(),
        Some("2026-11-01")
    );
    // Ten hours west, the Entry written on the 1st is still on the 1st.
    assert_eq!(
        store.oldest_timeline_day(-10 * 60).unwrap().as_deref(),
        Some("2026-11-01")
    );
    // Fourteen hours east, both are on the 2nd.
    assert_eq!(
        store.oldest_timeline_day(14 * 60).unwrap().as_deref(),
        Some("2026-11-02")
    );

    store.set_book_in_timeline(kebun.id, false).unwrap();
    assert_eq!(store.oldest_timeline_day(0).unwrap(), None);
}

#[test]
fn timeline_days_refuse_bad_days_and_offsets() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    for (from, to, offset) in [
        ("2026-11-1", "2026-11-30", 0),
        ("2026-11-01", "2026-02-30", 0),
        ("2026-11-01T00:00", "2026-11-30", 0),
        ("2026-11-01", "2026-11-30", 18 * 60 + 1),
        ("2026-11-01", "2026-11-30", -18 * 60 - 1),
    ] {
        assert!(
            matches!(
                store.timeline_days(from, to, offset),
                Err(StoreError::Invalid(_))
            ),
            "{from} {to} {offset}"
        );
    }
    assert!(matches!(
        store.oldest_timeline_day(19 * 60),
        Err(StoreError::Invalid(_))
    ));
    assert!(
        store
            .timeline_days("2026-11-01", "2026-11-30", -18 * 60)
            .is_ok()
    );
}

#[test]
fn keeping_a_book_out_of_the_timeline_needs_the_book() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);

    assert!(matches!(
        store.set_book_in_timeline(Id::random().unwrap(), false),
        Err(StoreError::NotFound)
    ));
}

#[test]
fn deleting_a_book_forgets_it_was_kept_out_of_the_timeline() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    store.set_book_in_timeline(book.id, false).unwrap();

    store.delete_forever(&[book.id], &[]).unwrap();

    assert_eq!(count(&store, "book_out_of_timeline"), 0);
}

#[test]
fn entries_written_in_the_same_millisecond_page_by_id() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    for i in 0..6 {
        store
            .save_entry(draft(
                book.id,
                "2026-11-17T08:00:00+07:00",
                &format!("Sama {i}"),
            ))
            .unwrap();
    }
    lock(&store.inner)
        .conn
        .execute("UPDATE entry SET created_at = 1", [])
        .unwrap();
    let mut ids: Vec<Id> = every_page(10, |after, limit| {
        store.list_entries(book.id, EntryOrder::OldestFirst, after, limit)
    })
    .iter()
    .map(|entry| entry.id)
    .collect();
    ids.sort();

    for order in [EntryOrder::OldestFirst, EntryOrder::NewestFirst] {
        let listed: Vec<Id> = every_page(4, |after, limit| {
            store.list_all_entries(order, after, limit)
        })
        .iter()
        .map(|entry| entry.id)
        .collect();
        let mut expected = ids.clone();
        if order == EntryOrder::NewestFirst {
            expected.reverse();
        }
        assert_eq!(listed, expected, "{order:?}");
    }
}

#[test]
fn listings_seek_the_date_indexes_either_way() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let inner = lock(&store.inner);
    // `step` is what the plan must show: a seek ("USING INDEX name (") after a cursor, a walk of
    // the index in order ("SCAN e USING INDEX name") for the first page.
    let plan = |sql: String, step: &str| {
        let steps: Vec<String> = inner
            .conn
            .prepare(&format!("EXPLAIN QUERY PLAN {sql}"))
            .unwrap()
            .query_map([], |row| row.get(3))
            .unwrap()
            .collect::<rusqlite::Result<_>>()
            .unwrap();
        assert!(steps.iter().any(|s| s.contains(step)), "{steps:?}");
        assert!(
            !steps.iter().any(|step| step.contains("TEMP B-TREE")),
            "{steps:?}"
        );
    };
    let cursor = format!("('2026-11-17T08:00:00+07:00', 1, x'{}')", "01".repeat(16));

    for order in [EntryOrder::NewestFirst, EntryOrder::OldestFirst] {
        let (by, past) = (order.sql(), order.past());
        plan(
            format!(
                "{SELECT_ENTRY} WHERE {IN_TIMELINE}
                   AND (e.entry_date, e.created_at, e.id) {past} {cursor}
                 ORDER BY {by} LIMIT 2"
            ),
            "USING INDEX entry_by_date (",
        );
        plan(
            format!("{SELECT_ENTRY} WHERE {IN_TIMELINE} ORDER BY {by} LIMIT 2"),
            "SCAN e USING INDEX entry_by_date",
        );
        plan(
            format!(
                "{SELECT_ENTRY} WHERE e.book_id = x'{book}'
                   AND (e.entry_date, e.created_at, e.id) {past} {cursor}
                 ORDER BY {by} LIMIT 2",
                book = "02".repeat(16)
            ),
            "USING INDEX entry_by_book_and_date (",
        );
    }
}

#[test]
fn searches_by_word_prefix_without_diacritics() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let old = store
        .save_entry(draft(
            garden.id,
            "2026-11-01T08:00:00+07:00",
            "Hujan deras sejak pagi.",
        ))
        .unwrap();
    let new = store
        .save_entry(draft(
            garden.id,
            "2026-11-03T08:00:00+07:00",
            "Pagi cerah, kopi di teras.",
        ))
        .unwrap();
    store
        .save_entry(draft(
            trips.id,
            "2026-11-02T08:00:00+07:00",
            "Café di Bandung, pagi sekali.",
        ))
        .unwrap();

    let results = store.search("pag", None, 10, 0).unwrap();
    assert_eq!(results.total, 3);
    assert_eq!(
        results.per_book,
        vec![
            BookCount {
                book_id: garden.id,
                count: 2
            },
            BookCount {
                book_id: trips.id,
                count: 1
            },
        ]
    );
    let dates: Vec<&str> = results
        .hits
        .iter()
        .map(|hit| hit.entry.date.as_str())
        .collect();
    assert_eq!(
        dates,
        [
            "2026-11-03T08:00:00+07:00",
            "2026-11-02T08:00:00+07:00",
            "2026-11-01T08:00:00+07:00"
        ]
    );
    assert!(
        results.hits[0]
            .snippet
            .contains(&format!("{MATCH_START}Pagi{MATCH_END}"))
    );

    let in_garden = store.search("PAGI hujan", Some(garden.id), 10, 0).unwrap();
    assert_eq!(in_garden.total, 1);
    assert_eq!(in_garden.hits[0].entry.id, old.id);
    assert_eq!(in_garden.per_book.len(), 1);

    let filtered = store.search("pagi", Some(garden.id), 1, 1).unwrap();
    assert_eq!(filtered.total, 2);
    assert_eq!(filtered.hits.len(), 1);
    assert_eq!(filtered.hits[0].entry.id, old.id);
    assert_ne!(filtered.hits[0].entry.id, new.id);

    assert_eq!(store.search("cafe", None, 10, 0).unwrap().total, 1);
    assert_eq!(store.search("caf", None, 10, 0).unwrap().total, 1);
    assert_eq!(store.search("eras", None, 10, 0).unwrap().total, 0);
    assert_eq!(
        store.search(" \"* ", None, 10, 0).unwrap(),
        SearchResults::default()
    );
}

#[test]
fn match_ranges_mark_the_words_a_snippet_marks() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let text = "Pagi ini hujan. Café-nya tutup, jadi kehujanan sampai pagi.";
    store
        .save_entry(draft(book.id, "2026-11-01T08:00:00+07:00", text))
        .unwrap();

    for typed in ["pag", "hujan pagi", "cafe", "café NYA"] {
        let hit = &store.search(typed, None, 1, 0).unwrap().hits[0];
        let from_snippet: Vec<&str> = hit
            .snippet
            .split(MATCH_START)
            .skip(1)
            .map(|part| part.split(MATCH_END).next().unwrap())
            .collect();
        let from_ranges: Vec<&str> = match_ranges(text, typed)
            .unwrap()
            .into_iter()
            .map(|range| &text[range])
            .collect();
        assert_eq!(from_ranges, from_snippet, "{typed}");
    }
}

#[test]
fn rebuilds_every_index_from_the_blobs() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Tomat mulai merah.")
        })
        .unwrap();
    store.set_book_description(book.id, "Sayur.").unwrap();
    store.set_book_cover(book.id, b"full", b"thumb").unwrap();
    let book = store.get_book(book.id).unwrap();
    let cover_id = |store: &Store| -> Option<Id> {
        lock(&store.inner)
            .conn
            .query_row("SELECT cover_id FROM book", [], |row| row.get(0))
            .unwrap()
    };
    let cover = cover_id(&store);
    assert!(cover.is_some());

    lock(&store.inner)
        .conn
        .execute_batch(
            "DELETE FROM entry_search; DELETE FROM entry_image;
             UPDATE entry SET entry_date = '2000-01-01T00:00:00+00:00', created_at = 0,
                 updated_at = 0;
             UPDATE book SET name = 'rusak', description = 'rusak', cover_id = NULL,
                 last_activity_at = 0;",
        )
        .unwrap();
    store.rebuild_index().unwrap();

    assert_eq!(store.get_book(book.id).unwrap(), book);
    assert_eq!(cover_id(&store), cover);
    assert_eq!(
        store
            .list_entries(book.id, EntryOrder::NewestFirst, None, 10)
            .unwrap(),
        vec![saved]
    );
    assert_eq!(store.search("tomat", None, 10, 0).unwrap().total, 1);
}

#[test]
fn a_failed_save_leaves_no_rows_and_no_files() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let before = store.get_book(book.id).unwrap();

    store.fail_before_commit.store(true, Ordering::SeqCst);
    let result = store.save_entry(EntryDraft {
        images: vec![new_image("tomat"), new_image("cabai")],
        ..draft(book.id, "2026-11-17T08:00:00+07:00", "Tidak tersimpan.")
    });

    assert!(result.is_err());
    for table in ["entry", "entry_image", "entry_search"] {
        assert_eq!(count(&store, table), 0, "{table}");
    }
    assert_eq!(image_files(&dir), Vec::<String>::new());
    assert_eq!(store.get_book(book.id).unwrap(), before);
}

#[test]
fn a_failed_edit_keeps_the_entry_as_it_was() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Asli.")
        })
        .unwrap();

    store.fail_before_commit.store(true, Ordering::SeqCst);
    let result = store.save_entry(EntryDraft {
        id: Some(saved.id),
        images: vec![new_image("cabai")],
        ..draft(book.id, "2026-11-18T08:00:00+07:00", "Diedit.")
    });

    assert!(result.is_err());
    assert_eq!(store.get_entry(saved.id).unwrap(), saved);
    assert_eq!(
        store
            .list_entries(book.id, EntryOrder::NewestFirst, None, 10)
            .unwrap(),
        vec![saved.clone()]
    );
    assert_eq!(image_files(&dir).len(), 2);
    assert_eq!(
        store
            .get_image(saved.id, saved.image_ids[0], ImageVariant::Full)
            .unwrap(),
        b"tomat full"
    );
}

#[test]
fn rejects_a_tampered_blob() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(draft(book.id, "2026-11-17T08:00:00+07:00", "Asli."))
        .unwrap();

    {
        let inner = lock(&store.inner);
        let mut blob: Vec<u8> = inner
            .conn
            .query_row("SELECT blob FROM entry WHERE id = ?1", [saved.id], |row| {
                row.get(0)
            })
            .unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 0x01;
        inner
            .conn
            .execute(
                "UPDATE entry SET blob = ?2 WHERE id = ?1",
                params![saved.id, blob],
            )
            .unwrap();
    }

    assert!(matches!(
        store.get_entry(saved.id),
        Err(StoreError::Format(Error::DecryptionFailed))
    ));
    assert!(store.rebuild_index().is_err());
    assert_eq!(store.search("asli", None, 10, 0).unwrap().total, 1);
}

#[test]
fn rejects_a_tampered_image_file() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
        })
        .unwrap();
    let path = store.files.path(saved.image_ids[0], ImageVariant::Full);
    let mut blob = fs::read(&path).unwrap();
    blob[0] ^= 0x01;
    fs::write(&path, blob).unwrap();

    assert!(matches!(
        store.get_image(saved.id, saved.image_ids[0], ImageVariant::Full),
        Err(StoreError::Format(Error::HashMismatch))
    ));
}

#[test]
fn deleting_removes_rows_then_files() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let kept = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(garden.id, "2026-11-01T08:00:00+07:00", "Lama.")
        })
        .unwrap();
    let gone = store
        .save_entry(EntryDraft {
            images: vec![new_image("cabai")],
            ..draft(garden.id, "2026-11-02T08:00:00+07:00", "Baru.")
        })
        .unwrap();
    store
        .save_entry(EntryDraft {
            images: vec![new_image("pantai")],
            ..draft(trips.id, "2026-11-03T08:00:00+07:00", "Pantai.")
        })
        .unwrap();

    store.delete_forever(&[], &[gone.id]).unwrap();
    store.delete_forever(&[], &[gone.id]).unwrap();
    assert!(matches!(
        store.get_entry(gone.id),
        Err(StoreError::NotFound)
    ));
    assert_eq!(image_files(&dir).len(), 4);
    let garden_now = store.get_book(garden.id).unwrap();
    assert_eq!(garden_now.last_activity_at, kept.updated_at);
    assert_eq!(garden_now.last_entry_text.as_deref(), Some("Lama."));

    store.delete_forever(&[trips.id], &[]).unwrap();
    store.delete_forever(&[trips.id], &[]).unwrap();
    assert!(matches!(
        store.get_book(trips.id),
        Err(StoreError::NotFound)
    ));
    assert_eq!(image_files(&dir).len(), 2);
    assert_eq!(count(&store, "entry"), 1);
    assert_eq!(count(&store, "entry_search"), 1);
    assert_eq!(count(&store, "book_key"), 1);
    assert_eq!(store.search("pantai", None, 10, 0).unwrap().total, 0);
}

#[test]
fn removes_old_orphan_files_at_open() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let saved = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi.")
        })
        .unwrap();
    store
        .set_book_cover(book.id, b"cover full", b"cover thumb")
        .unwrap();
    let cover: Id = lock(&store.inner)
        .conn
        .query_row("SELECT cover_id FROM book", [], |row| row.get(0))
        .unwrap();
    let images = dir.path().join(IMAGES_DIR);
    let old = SystemTime::now() - ORPHAN_AGE - Duration::from_secs(60);
    let orphan = Id::random().unwrap();
    for name in [
        format!("{orphan}.full"),
        format!("{orphan}.thumb.tmp"),
        format!("{}.full", saved.image_ids[0]),
        format!("{cover}.full"),
        format!("{cover}.thumb"),
    ] {
        let path = images.join(name);
        if !path.exists() {
            fs::write(&path, b"left behind").unwrap();
        }
        File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_modified(old)
            .unwrap();
    }
    let young = Id::random().unwrap();
    fs::write(images.join(format!("{young}.full")), b"saving").unwrap();
    drop(store);

    let store = open(&dir);
    let mut expected = vec![
        format!("{}.full", saved.image_ids[0]),
        format!("{}.thumb", saved.image_ids[0]),
        format!("{cover}.full"),
        format!("{cover}.thumb"),
        format!("{young}.full"),
    ];
    expected.sort();
    assert_eq!(image_files(&dir), expected);
    assert_eq!(
        store
            .get_image(saved.id, saved.image_ids[0], ImageVariant::Full)
            .unwrap(),
        b"tomat full"
    );
    assert_eq!(
        store.get_book_cover(book.id, ImageVariant::Full).unwrap(),
        b"cover full"
    );
}

#[test]
fn listeners_hear_every_commit() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let heard = Arc::new(Mutex::new(Vec::new()));
    let subscription = store.subscribe({
        let heard = Arc::clone(&heard);
        move |change| heard.lock().unwrap().push(change)
    });

    let book = store.create_book("Kebun").unwrap();
    let entry = store
        .save_entry(draft(book.id, "2026-11-17T08:00:00+07:00", "Pagi."))
        .unwrap();
    store.fail_before_commit.store(true, Ordering::SeqCst);
    let _ = store.save_entry(draft(book.id, "2026-11-17T08:00:00+07:00", "Gagal."));
    store.delete_forever(&[], &[entry.id]).unwrap();
    store.unsubscribe(subscription);
    store.rename_book(book.id, "Kebun baru").unwrap();

    let book_change = Change {
        book_id: book.id,
        entry_id: None,
    };
    let entry_change = Change {
        book_id: book.id,
        entry_id: Some(entry.id),
    };
    assert_eq!(
        *heard.lock().unwrap(),
        [book_change, entry_change, entry_change]
    );
}

#[test]
fn a_listener_can_read_the_store() {
    let dir = TempDir::new().unwrap();
    let store = Arc::new(open(&dir));
    let names = Arc::new(Mutex::new(Vec::new()));
    store.subscribe({
        let store = Arc::downgrade(&store);
        let names = Arc::clone(&names);
        move |change| {
            let store = store.upgrade().unwrap();
            names
                .lock()
                .unwrap()
                .push(store.get_book(change.book_id).unwrap().name);
        }
    });

    store.create_book("Kebun").unwrap();

    assert_eq!(*names.lock().unwrap(), ["Kebun"]);
}

fn set_activity(store: &Store, book_id: Id, at: i64) {
    lock(&store.inner)
        .conn
        .execute(
            "UPDATE book SET last_activity_at = ?2 WHERE id = ?1",
            params![book_id, at],
        )
        .unwrap();
}

fn book_names(store: &Store) -> Vec<String> {
    store
        .list_books()
        .unwrap()
        .into_iter()
        .map(|book| book.name)
        .collect()
}

#[test]
fn pinned_books_come_first_each_by_last_activity() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let names = ["Kebun", "Perjalanan", "Kerja", "Resep"];
    let books: Vec<BookInfo> = names
        .iter()
        .map(|name| store.create_book(name).unwrap())
        .collect();
    for (at, book) in books.iter().enumerate() {
        set_activity(&store, book.id, 1_000 + at as i64);
    }
    assert_eq!(
        book_names(&store),
        ["Resep", "Kerja", "Perjalanan", "Kebun"]
    );

    store
        .set_books_pinned(&[books[0].id, books[1].id], true)
        .unwrap();
    assert_eq!(
        book_names(&store),
        ["Perjalanan", "Kebun", "Resep", "Kerja"]
    );
    assert!(store.get_book(books[0].id).unwrap().pinned);
    assert!(!store.get_book(books[3].id).unwrap().pinned);

    // A Book written in today stays under the Pinned Books.
    store
        .save_entry(draft(books[2].id, "2026-11-22T08:00:00+07:00", "Rapat."))
        .unwrap();
    assert_eq!(
        book_names(&store),
        ["Perjalanan", "Kebun", "Kerja", "Resep"]
    );

    // Pins stay on the device across reopening.
    drop(store);
    let store = open(&dir);
    assert_eq!(
        book_names(&store),
        ["Perjalanan", "Kebun", "Kerja", "Resep"]
    );

    store.set_books_pinned(&[books[1].id], false).unwrap();
    store.set_books_pinned(&[books[1].id], false).unwrap();
    assert_eq!(
        book_names(&store),
        ["Kebun", "Kerja", "Resep", "Perjalanan"]
    );
}

#[test]
fn pinning_refuses_a_fourth_book_and_pins_none_of_them() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let books: Vec<Id> = (0..5)
        .map(|i| store.create_book(&format!("Book {i}")).unwrap().id)
        .collect();
    store.set_books_pinned(&books[..2], true).unwrap();

    assert!(matches!(
        store.set_books_pinned(&books[2..4], true),
        Err(StoreError::TooManyPinned)
    ));
    assert_eq!(count(&store, "book_pin"), 2);

    // Pinning a Pinned Book again does not count twice.
    store.set_books_pinned(&books[..3], true).unwrap();
    assert_eq!(count(&store, "book_pin"), 3);

    assert!(matches!(
        store.set_books_pinned(&[Id::random().unwrap()], true),
        Err(StoreError::NotFound)
    ));
}

#[test]
fn deleting_a_pinned_book_frees_its_place() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let books: Vec<Id> = (0..4)
        .map(|i| store.create_book(&format!("Book {i}")).unwrap().id)
        .collect();
    store.set_books_pinned(&books[..3], true).unwrap();

    store.delete_forever(&[books[0]], &[]).unwrap();

    assert_eq!(count(&store, "book_pin"), 2);
    store.set_books_pinned(&books[3..], true).unwrap();
    assert_eq!(count(&store, "book_pin"), 3);
}

#[test]
fn books_count_their_entries() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    assert_eq!(garden.entry_count, 0);
    let first = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();
    store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Dua."))
        .unwrap();
    assert_eq!(store.get_book(garden.id).unwrap().entry_count, 2);

    store.delete_forever(&[], &[first.id]).unwrap();

    assert_eq!(store.list_books().unwrap()[0].entry_count, 1);
}

#[test]
fn pinning_tells_listeners_about_each_book() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let heard = Arc::new(Mutex::new(Vec::new()));
    store.subscribe({
        let heard = Arc::clone(&heard);
        move |change| heard.lock().unwrap().push(change.book_id)
    });

    store
        .set_books_pinned(&[garden.id, trips.id], true)
        .unwrap();

    assert_eq!(*heard.lock().unwrap(), [garden.id, trips.id]);
}

fn blob(store: &Store, id: Id) -> Vec<u8> {
    lock(&store.inner)
        .conn
        .query_row("SELECT blob FROM entry WHERE id = ?1", [id], |row| {
            row.get(0)
        })
        .unwrap()
}

fn entry_texts(store: &Store, book_id: Id) -> Vec<String> {
    store
        .list_entries(book_id, EntryOrder::NewestFirst, None, 100)
        .unwrap()
        .into_iter()
        .map(|entry| entry.text)
        .collect()
}

#[test]
fn moving_seals_entries_again_for_the_other_book() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let work = store.create_book("Kerja").unwrap();
    let meeting = store
        .save_entry(draft(work.id, "2026-11-01T08:00:00+07:00", "Rapat."))
        .unwrap();
    let morning = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(garden.id, "2026-11-17T08:00:00+07:00", "Pagi di kebun.")
        })
        .unwrap();
    let evening = store
        .save_entry(draft(garden.id, "2026-11-17T18:00:00+07:00", "Sore."))
        .unwrap();
    let files = image_files(&dir);
    let old_blob = blob(&store, morning.id);

    store
        .move_entries(&[morning.id, evening.id], work.id)
        .unwrap();

    // The same Entries, in the other Book, sealed again.
    let moved = store.get_entry(morning.id).unwrap();
    assert_eq!(
        moved,
        StoredEntry {
            book_id: work.id,
            ..morning.clone()
        }
    );
    assert_ne!(blob(&store, morning.id), old_blob);
    assert_eq!(
        store
            .get_image(morning.id, morning.image_ids[0], ImageVariant::Full)
            .unwrap(),
        b"tomat full"
    );
    assert_eq!(image_files(&dir), files);
    assert_eq!(entry_texts(&store, garden.id), Vec::<String>::new());
    assert_eq!(
        entry_texts(&store, work.id),
        ["Sore.", "Pagi di kebun.", "Rapat."]
    );
    let found = store.search("kebun", None, 10, 0).unwrap();
    assert_eq!(found.per_book[0].book_id, work.id);

    // The Book moved to takes the later activity; the one left empty keeps its own.
    let work_now = store.get_book(work.id).unwrap();
    assert_eq!(work_now.last_activity_at, evening.updated_at);
    assert_eq!(work_now.entry_count, 3);
    assert_eq!(work_now.last_entry_text.as_deref(), Some("Sore."));
    let garden_now = store.get_book(garden.id).unwrap();
    assert_eq!(garden_now.last_activity_at, evening.updated_at);
    assert_eq!(garden_now.last_entry_text, None);

    // The blobs open with the new Book's key from scratch.
    store.rebuild_index().unwrap();
    drop(store);
    let store = open(&dir);
    assert_eq!(store.get_entry(morning.id).unwrap(), moved);

    // Moving back undoes it.
    store
        .move_entries(&[morning.id, evening.id], garden.id)
        .unwrap();
    assert_eq!(store.get_entry(morning.id).unwrap(), morning);
    assert_eq!(entry_texts(&store, garden.id), ["Sore.", "Pagi di kebun."]);
    assert_eq!(entry_texts(&store, work.id), ["Rapat."]);
    assert_eq!(
        store.get_book(work.id).unwrap().last_activity_at,
        meeting.updated_at
    );
}

#[test]
fn the_book_moved_from_takes_the_activity_of_the_entries_it_keeps() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let work = store.create_book("Kerja").unwrap();
    let kept = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Lama."))
        .unwrap();
    let moved = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Baru."))
        .unwrap();
    set_activity(&store, work.id, moved.updated_at + 1_000);

    store.move_entries(&[moved.id], work.id).unwrap();

    let garden_now = store.get_book(garden.id).unwrap();
    assert_eq!(garden_now.last_activity_at, kept.updated_at);
    assert_eq!(garden_now.last_entry_text.as_deref(), Some("Lama."));
    // The moved Entry is older than the Book's own activity, which stays.
    assert_eq!(
        store.get_book(work.id).unwrap().last_activity_at,
        moved.updated_at + 1_000
    );
}

#[test]
fn a_failed_move_moves_nothing() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let work = store.create_book("Kerja").unwrap();
    let first = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();
    let second = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Dua."))
        .unwrap();
    let blobs = [blob(&store, first.id), blob(&store, second.id)];
    let heard = Arc::new(Mutex::new(0));
    store.subscribe({
        let heard = Arc::clone(&heard);
        move |_| *heard.lock().unwrap() += 1
    });

    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(store.move_entries(&[first.id, second.id], work.id).is_err());
    assert!(matches!(
        store.move_entries(&[first.id, Id::random().unwrap()], work.id),
        Err(StoreError::NotFound)
    ));
    assert!(matches!(
        store.move_entries(&[first.id], Id::random().unwrap()),
        Err(StoreError::NotFound)
    ));

    assert_eq!(entry_texts(&store, garden.id), ["Dua.", "Satu."]);
    assert_eq!(entry_texts(&store, work.id), Vec::<String>::new());
    assert_eq!([blob(&store, first.id), blob(&store, second.id)], blobs);
    assert_eq!(*heard.lock().unwrap(), 0);
}

#[test]
fn moving_tells_listeners_about_both_books() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let work = store.create_book("Kerja").unwrap();
    let entry = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();
    let heard = Arc::new(Mutex::new(Vec::new()));
    store.subscribe({
        let heard = Arc::clone(&heard);
        move |change| heard.lock().unwrap().push(change)
    });

    store.move_entries(&[entry.id], work.id).unwrap();
    // Moving to the Book it is in already changes nothing.
    store.move_entries(&[entry.id], work.id).unwrap();

    let change = |book_id| Change {
        book_id,
        entry_id: Some(entry.id),
    };
    assert_eq!(*heard.lock().unwrap(), [change(garden.id), change(work.id)]);
}

#[test]
fn deletes_several_entries_at_once() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let kept = store
        .save_entry(EntryDraft {
            images: vec![new_image("tomat")],
            ..draft(garden.id, "2026-11-01T08:00:00+07:00", "Lama.")
        })
        .unwrap();
    let gone: Vec<Id> = ["Dua.", "Tiga."]
        .iter()
        .map(|text| {
            store
                .save_entry(EntryDraft {
                    images: vec![new_image(text)],
                    ..draft(garden.id, "2026-11-02T08:00:00+07:00", text)
                })
                .unwrap()
                .id
        })
        .collect();

    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(store.delete_forever(&[], &gone).is_err());
    assert_eq!(entry_texts(&store, garden.id).len(), 3);
    assert_eq!(image_files(&dir).len(), 6);

    store
        .delete_forever(&[], &[gone[0], gone[1], Id::random().unwrap()])
        .unwrap();

    assert_eq!(entry_texts(&store, garden.id), ["Lama."]);
    assert_eq!(image_files(&dir).len(), 2);
    assert_eq!(count(&store, "entry_search"), 1);
    assert_eq!(count(&store, "entry_image"), 1);
    assert_eq!(
        store.get_book(garden.id).unwrap().last_activity_at,
        kept.updated_at
    );
}

#[test]
fn a_book_insight_counts_entries_words_and_images() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let work = store.create_book("Kerja").unwrap();
    let insight = |id| store.book_insight(id).unwrap();

    // An empty Book, and a Cover that is not one of its Images.
    store.set_book_cover(garden.id, b"full", b"thumb").unwrap();
    assert_eq!(insight(garden.id), BookInsight::default());

    let morning = store
        .save_entry(EntryDraft {
            images: vec![new_image("a"), new_image("b")],
            ..draft(garden.id, "2026-11-01T08:00:00+07:00", "*Pagi* di kebun.")
        })
        .unwrap();
    let photos = store
        .save_entry(EntryDraft {
            images: vec![new_image("c")],
            ..draft(garden.id, "2026-11-02T08:00:00+07:00", "")
        })
        .unwrap();
    store
        .save_entry(draft(
            work.id,
            "2026-11-02T09:00:00+07:00",
            "- Rapat pagi\n- Laporan",
        ))
        .unwrap();
    assert_eq!(
        insight(garden.id),
        BookInsight {
            entry_count: 2,
            word_count: 3,
            image_count: 3,
        }
    );
    assert_eq!(
        insight(work.id),
        BookInsight {
            entry_count: 1,
            word_count: 3,
            image_count: 0,
        }
    );

    // An edit, then a move and a delete.
    store
        .save_entry(EntryDraft {
            id: Some(morning.id),
            images: vec![ImageInput::Keep(morning.image_ids[0])],
            ..draft(garden.id, "2026-11-01T08:00:00+07:00", "Pagi.")
        })
        .unwrap();
    store.move_entries(&[photos.id], work.id).unwrap();
    assert_eq!(
        insight(garden.id),
        BookInsight {
            entry_count: 1,
            word_count: 1,
            image_count: 1,
        }
    );
    assert_eq!(
        insight(work.id),
        BookInsight {
            entry_count: 2,
            word_count: 3,
            image_count: 1,
        }
    );
    store.delete_forever(&[], &[morning.id]).unwrap();
    assert_eq!(insight(garden.id), BookInsight::default());

    assert!(matches!(
        store.book_insight(Id::random().unwrap()),
        Err(StoreError::NotFound)
    ));
}

fn starred_texts(store: &Store, book_id: Id) -> Vec<String> {
    store
        .list_starred_entries(book_id, None, 100)
        .unwrap()
        .into_iter()
        .map(|entry| entry.text)
        .collect()
}

fn star_record(store: &Store, entry_id: Id) -> Option<StarRecord> {
    let inner = lock(&store.inner);
    inner
        .conn
        .query_row(
            "SELECT record FROM star WHERE entry_id = ?1",
            [entry_id],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .optional()
        .unwrap()
        .map(|record| open_star_record(&record, inner.keyring.master()).unwrap())
}

#[test]
fn entries_are_starred_and_unstarred_without_being_edited() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let first = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();
    let second = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Dua."))
        .unwrap();
    let activity = store.get_book(garden.id).unwrap().last_activity_at;
    let blobs = [blob(&store, first.id), blob(&store, second.id)];
    let heard = Arc::new(Mutex::new(Vec::new()));
    store.subscribe({
        let heard = Arc::clone(&heard);
        move |change| heard.lock().unwrap().push(change.entry_id)
    });

    store
        .set_entries_starred(&[first.id, second.id], true)
        .unwrap();
    assert!(store.get_entry(first.id).unwrap().starred);
    assert_eq!(starred_texts(&store, garden.id), ["Dua.", "Satu."]);
    assert_eq!(starred_texts(&store, garden.id).len(), 2);
    assert_eq!(*heard.lock().unwrap(), [Some(first.id), Some(second.id)]);
    // Starring is not editing.
    assert_eq!([blob(&store, first.id), blob(&store, second.id)], blobs);
    assert_eq!(
        store.get_entry(first.id).unwrap().updated_at,
        first.updated_at
    );
    assert_eq!(
        store.get_book(garden.id).unwrap().last_activity_at,
        activity
    );

    // The star is a sealed record of its own, under the record ID of its Entry.
    let star = star_record(&store, first.id).unwrap();
    assert_eq!((star.entry_id, star.book_id), (first.id, garden.id));
    let record_id: Id = lock(&store.inner)
        .conn
        .query_row(
            "SELECT record_id FROM star WHERE entry_id = ?1",
            [first.id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        record_id,
        star_record_id(first.id, lock(&store.inner).keyring.master())
    );

    // Starring again changes nothing and says nothing.
    heard.lock().unwrap().clear();
    store.set_entries_starred(&[first.id], true).unwrap();
    assert_eq!(star_record(&store, first.id).unwrap(), star);
    assert!(heard.lock().unwrap().is_empty());

    store.set_entries_starred(&[second.id], false).unwrap();
    assert!(!store.get_entry(second.id).unwrap().starred);
    assert_eq!(starred_texts(&store, garden.id), ["Satu."]);
    assert_eq!(starred_texts(&store, garden.id).len(), 1);
    assert_eq!(count(&store, "star"), 1);
}

#[test]
fn the_star_shows_in_every_list_and_survives_an_edit() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let entry = store
        .save_entry(draft(
            garden.id,
            "2026-11-01T08:00:00+07:00",
            "Tomat merah.",
        ))
        .unwrap();
    assert!(!entry.starred);
    store.set_entries_starred(&[entry.id], true).unwrap();

    let listed = store
        .list_entries(garden.id, EntryOrder::NewestFirst, None, 10)
        .unwrap();
    assert!(listed[0].starred);
    let timeline = store
        .list_all_entries(EntryOrder::NewestFirst, None, 10)
        .unwrap();
    assert!(timeline[0].starred);
    let found = store.search("tomat", None, 10, 0).unwrap();
    assert!(found.hits[0].entry.starred);

    let edited = store
        .save_entry(EntryDraft {
            id: Some(entry.id),
            ..draft(garden.id, "2026-11-01T08:00:00+07:00", "Tomat matang.")
        })
        .unwrap();
    assert!(edited.starred);
    assert_eq!(
        store.search("tomat", None, 10, 0).unwrap().hits[0].snippet,
        format!("{MATCH_START}Tomat{MATCH_END} matang.")
    );
}

#[test]
fn starred_entries_come_newest_first_across_pages() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let other = store.create_book("Kerja").unwrap();
    let mut starred = Vec::new();
    for day in 1..=5 {
        let entry = store
            .save_entry(draft(
                garden.id,
                &format!("2026-11-0{day}T08:00:00+07:00"),
                &format!("Hari {day}."),
            ))
            .unwrap();
        if day != 3 {
            starred.push(entry.id);
        }
    }
    let elsewhere = store
        .save_entry(draft(other.id, "2026-11-09T08:00:00+07:00", "Kerja."))
        .unwrap();
    starred.push(elsewhere.id);
    store.set_entries_starred(&starred, true).unwrap();

    let first = store.list_starred_entries(garden.id, None, 2).unwrap();
    let cursor = EntryCursor::from(first.last().unwrap());
    let rest = store
        .list_starred_entries(garden.id, Some(&cursor), 10)
        .unwrap();
    let texts: Vec<&str> = first
        .iter()
        .chain(&rest)
        .map(|entry| entry.text.as_str())
        .collect();
    assert_eq!(texts, ["Hari 5.", "Hari 4.", "Hari 2.", "Hari 1."]);
    assert!(first.iter().chain(&rest).all(|entry| entry.starred));
    assert_eq!(starred_texts(&store, other.id), ["Kerja."]);
}

#[test]
fn a_star_moves_with_its_entry_and_goes_with_it() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let work = store.create_book("Kerja").unwrap();
    let moved = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Pindah."))
        .unwrap();
    let deleted = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Hapus."))
        .unwrap();
    store
        .set_entries_starred(&[moved.id, deleted.id], true)
        .unwrap();
    let starred_at = star_record(&store, moved.id).unwrap().starred_at;

    store.move_entries(&[moved.id], work.id).unwrap();
    let star = star_record(&store, moved.id).unwrap();
    assert_eq!((star.book_id, star.starred_at), (work.id, starred_at));
    assert_eq!(starred_texts(&store, work.id), ["Pindah."]);
    assert_eq!(starred_texts(&store, garden.id), ["Hapus."]);
    assert_eq!(starred_texts(&store, garden.id).len(), 1);
    assert_eq!(starred_texts(&store, work.id).len(), 1);

    store.delete_forever(&[], &[deleted.id]).unwrap();
    assert_eq!(star_record(&store, deleted.id), None);
    assert_eq!(starred_texts(&store, garden.id).len(), 0);

    store.delete_forever(&[work.id], &[]).unwrap();
    assert_eq!(count(&store, "star"), 0);
}

#[test]
fn starring_a_missing_entry_stars_nothing() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let entry = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();

    assert!(matches!(
        store.set_entries_starred(&[entry.id, Id::random().unwrap()], true),
        Err(StoreError::NotFound)
    ));
    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(store.set_entries_starred(&[entry.id], true).is_err());
    store.fail_before_commit.store(false, Ordering::SeqCst);
    assert_eq!(count(&store, "star"), 0);
}

#[test]
fn stars_survive_reopening_and_a_rebuild_of_the_index() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let entry = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();
    store.set_entries_starred(&[entry.id], true).unwrap();
    let star = star_record(&store, entry.id).unwrap();
    drop(store);

    let store = open(&dir);
    // Spoil a plaintext column; the rebuild takes it from the record.
    lock(&store.inner)
        .conn
        .execute("UPDATE star SET starred_at = 0", [])
        .unwrap();
    store.rebuild_index().unwrap();
    let starred_at: i64 = lock(&store.inner)
        .conn
        .query_row("SELECT starred_at FROM star", [], |row| row.get(0))
        .unwrap();
    assert_eq!(starred_at, star.starred_at);
    assert_eq!(starred_texts(&store, garden.id), ["Satu."]);
}

fn timeline_texts(store: &Store) -> Vec<String> {
    store
        .list_all_entries(EntryOrder::NewestFirst, None, 100)
        .unwrap()
        .into_iter()
        .map(|entry| entry.text)
        .collect()
}

fn search_texts(store: &Store, typed: &str) -> Vec<String> {
    store
        .search(typed, None, 100, 0)
        .unwrap()
        .hits
        .into_iter()
        .map(|hit| hit.entry.text)
        .collect()
}

/// Moves when every item in the Trash was deleted `days` days back.
fn deleted_earlier(store: &Store, days: i64) {
    let inner = lock(&store.inner);
    for table in ["book_trash", "entry_trash"] {
        inner
            .conn
            .execute(
                &format!("UPDATE {table} SET deleted_at = deleted_at - ?1"),
                [days * DAY_MS],
            )
            .unwrap();
    }
}

#[test]
fn an_entry_in_the_trash_is_hidden_everywhere_and_comes_back_as_it_was() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let kept = store
        .save_entry(draft(
            garden.id,
            "2026-11-01T08:00:00+07:00",
            "Tomat tumbuh.",
        ))
        .unwrap();
    let gone = store
        .save_entry(EntryDraft {
            images: vec![new_image("cabai")],
            ..draft(garden.id, "2026-11-02T08:00:00+07:00", "Cabai tumbuh.")
        })
        .unwrap();
    store.set_entries_starred(&[gone.id], true).unwrap();
    let before = store.get_book(garden.id).unwrap();

    store.trash_entries(&[gone.id]).unwrap();
    assert_eq!(entry_texts(&store, garden.id), ["Tomat tumbuh."]);
    assert_eq!(timeline_texts(&store), ["Tomat tumbuh."]);
    assert_eq!(search_texts(&store, "tumbuh"), ["Tomat tumbuh."]);
    assert_eq!(store.search("tumbuh", None, 10, 0).unwrap().total, 1);
    assert!(starred_texts(&store, garden.id).is_empty());
    assert_eq!(
        store
            .timeline_days("2026-11-01", "2026-11-30", 7 * 60)
            .unwrap(),
        ["2026-11-01"]
    );
    let book = store.get_book(garden.id).unwrap();
    assert_eq!(book.entry_count, 1);
    assert_eq!(book.last_entry_text.as_deref(), Some("Tomat tumbuh."));
    assert_eq!(book.last_activity_at, kept.updated_at);
    let insight = store.book_insight(garden.id).unwrap();
    assert_eq!((insight.entry_count, insight.image_count), (1, 0));
    // It is all still there, Images and star too.
    assert_eq!(image_files(&dir).len(), 2);
    assert!(star_record(&store, gone.id).is_some());
    assert_eq!(store.trash_count().unwrap(), 1);

    let trash = store.list_trash().unwrap();
    assert_eq!(trash.len(), 1);
    assert_eq!(
        trash[0].purge_at - trash[0].deleted_at,
        i64::from(DEFAULT_TRASH_DAYS) * DAY_MS
    );
    let TrashContent::Entry {
        entry,
        book_name,
        book_in_trash,
        book_locked,
    } = &trash[0].content
    else {
        panic!("not an Entry: {trash:?}");
    };
    assert_eq!((entry.id, entry.starred), (gone.id, true));
    assert_eq!(entry.image_ids, gone.image_ids);
    assert_eq!(
        (book_name.as_str(), *book_in_trash, *book_locked),
        ("Kebun", false, false)
    );

    // Moving an Entry to the Trash again changes nothing.
    store.trash_entries(&[gone.id]).unwrap();
    assert_eq!(store.trash_count().unwrap(), 1);

    store.restore(&[], &[gone.id], None).unwrap();
    assert_eq!(
        entry_texts(&store, garden.id),
        ["Cabai tumbuh.", "Tomat tumbuh."]
    );
    assert_eq!(search_texts(&store, "cabai"), ["Cabai tumbuh."]);
    assert_eq!(starred_texts(&store, garden.id), ["Cabai tumbuh."]);
    assert_eq!(store.get_entry(gone.id).unwrap().image_ids, gone.image_ids);
    assert_eq!(store.get_book(garden.id).unwrap(), before);
    assert_eq!(store.trash_count().unwrap(), 0);
}

#[test]
fn a_book_in_the_trash_hides_its_entries_and_comes_back_without_its_pin() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Kebun pagi."))
        .unwrap();
    let earlier = store
        .save_entry(draft(trips.id, "2026-11-02T08:00:00+07:00", "Pantai pagi."))
        .unwrap();
    let with_book = store
        .save_entry(draft(trips.id, "2026-11-03T08:00:00+07:00", "Gunung pagi."))
        .unwrap();
    store.set_books_pinned(&[trips.id], true).unwrap();

    store.trash_entries(&[earlier.id]).unwrap();
    store.trash_book(trips.id).unwrap();
    let names: Vec<String> = store
        .list_books()
        .unwrap()
        .into_iter()
        .map(|book| book.name)
        .collect();
    assert_eq!(names, ["Kebun"]);
    assert_eq!(search_texts(&store, "pagi"), ["Kebun pagi."]);
    assert_eq!(store.search("pagi", None, 10, 0).unwrap().per_book.len(), 1);
    assert_eq!(timeline_texts(&store), ["Kebun pagi."]);
    assert_eq!(
        store.oldest_timeline_day(7 * 60).unwrap().as_deref(),
        Some("2026-11-01")
    );
    // Its Entries can still be read, as the Trash shows them.
    assert_eq!(store.get_entry(with_book.id).unwrap().text, "Gunung pagi.");
    assert_eq!(store.book_insight(trips.id).unwrap().entry_count, 1);
    assert_eq!(store.trash_count().unwrap(), 2);

    let trash = store.list_trash().unwrap();
    let TrashContent::Book(book) = &trash[0].content else {
        panic!("the Book is not first: {trash:?}");
    };
    assert_eq!((book.id, book.entry_count), (trips.id, 1));
    assert!(!book.pinned);
    assert!(matches!(
        &trash[1].content,
        TrashContent::Entry { entry, book_in_trash: true, .. } if entry.id == earlier.id
    ));

    store.restore(&[trips.id], &[], None).unwrap();
    assert!(!store.get_book(trips.id).unwrap().pinned);
    assert_eq!(entry_texts(&store, trips.id), ["Gunung pagi."]);
    assert_eq!(timeline_texts(&store), ["Gunung pagi.", "Kebun pagi."]);
    // The Entry deleted before the Book stays in the Trash, now with its Book out of it.
    let trash = store.list_trash().unwrap();
    assert!(matches!(
        &trash[..],
        [TrashItem { content: TrashContent::Entry { entry, book_in_trash: false, .. }, .. }]
            if entry.id == earlier.id
    ));
}

#[test]
fn a_book_comes_back_from_the_trash_in_the_timeline() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let trips = store.create_book("Perjalanan").unwrap();
    store
        .save_entry(draft(trips.id, "2026-11-03T08:00:00+07:00", "Gunung."))
        .unwrap();
    store.set_book_in_timeline(trips.id, false).unwrap();

    store.trash_book(trips.id).unwrap();
    store.restore(&[trips.id], &[], None).unwrap();
    assert!(store.get_book(trips.id).unwrap().in_timeline);
    assert_eq!(timeline_texts(&store), ["Gunung."]);
}

#[test]
fn an_entry_whose_book_is_in_the_trash_comes_back_with_it_or_elsewhere() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let first = store
        .save_entry(draft(trips.id, "2026-11-02T08:00:00+07:00", "Pantai."))
        .unwrap();
    let second = store
        .save_entry(draft(trips.id, "2026-11-03T08:00:00+07:00", "Gunung."))
        .unwrap();
    let third = store
        .save_entry(draft(trips.id, "2026-11-04T08:00:00+07:00", "Danau."))
        .unwrap();
    store.set_entries_starred(&[first.id], true).unwrap();
    store.trash_entries(&[first.id, second.id]).unwrap();
    store.trash_book(trips.id).unwrap();

    // To a Book that is missing, or in the Trash: nothing comes back.
    assert!(matches!(
        store.restore(&[], &[first.id], Some(Id::random().unwrap())),
        Err(StoreError::NotFound)
    ));
    assert!(matches!(
        store.restore(&[], &[first.id], Some(trips.id)),
        Err(StoreError::Invalid(_))
    ));
    assert_eq!(store.trash_count().unwrap(), 3);

    // To another Book: sealed again for it, with its star, and the Book stays in the Trash.
    store.restore(&[], &[first.id], Some(garden.id)).unwrap();
    assert_eq!(entry_texts(&store, garden.id), ["Pantai."]);
    assert_eq!(starred_texts(&store, garden.id), ["Pantai."]);
    assert_eq!(store.get_entry(first.id).unwrap().book_id, garden.id);
    assert_eq!(star_record(&store, first.id).unwrap().book_id, garden.id);
    assert!(store.list_books().unwrap().iter().all(|b| b.id != trips.id));

    // With no Book given: its own Book comes back too, with the Entry that went with it.
    store.restore(&[], &[second.id], None).unwrap();
    assert_eq!(entry_texts(&store, trips.id), ["Danau.", "Gunung."]);
    assert!(store.list_books().unwrap().iter().any(|b| b.id == trips.id));
    assert_eq!(store.trash_count().unwrap(), 0);
    assert_eq!(store.get_entry(third.id).unwrap().book_id, trips.id);
}

#[test]
fn deleting_for_good_and_emptying_the_trash_delete_the_files() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    store.set_book_cover(trips.id, b"cover", b"thumb").unwrap();
    let gone = store
        .save_entry(EntryDraft {
            images: vec![new_image("cabai")],
            ..draft(garden.id, "2026-11-02T08:00:00+07:00", "Cabai.")
        })
        .unwrap();
    store.set_entries_starred(&[gone.id], true).unwrap();
    let earlier = store
        .save_entry(EntryDraft {
            images: vec![new_image("pantai")],
            ..draft(trips.id, "2026-11-03T08:00:00+07:00", "Pantai.")
        })
        .unwrap();
    store
        .save_entry(EntryDraft {
            images: vec![new_image("gunung")],
            ..draft(trips.id, "2026-11-04T08:00:00+07:00", "Gunung.")
        })
        .unwrap();
    store.trash_entries(&[gone.id, earlier.id]).unwrap();
    store.trash_book(trips.id).unwrap();
    assert_eq!(image_files(&dir).len(), 8);

    store.delete_forever(&[], &[gone.id]).unwrap();
    assert!(matches!(
        store.get_entry(gone.id),
        Err(StoreError::NotFound)
    ));
    assert_eq!(count(&store, "star"), 0);
    assert_eq!(image_files(&dir).len(), 6);
    assert_eq!(store.trash_count().unwrap(), 2);

    store.empty_trash().unwrap();
    assert_eq!(store.trash_count().unwrap(), 0);
    assert!(store.list_trash().unwrap().is_empty());
    assert!(matches!(
        store.get_book(trips.id),
        Err(StoreError::NotFound)
    ));
    assert!(image_files(&dir).is_empty());
    assert_eq!(count(&store, "entry"), 0);
    assert_eq!(count(&store, "entry_search"), 0);
    assert_eq!(count(&store, "book_key"), 1);
    assert_eq!(store.list_books().unwrap().len(), 1);
}

#[test]
fn what_has_been_in_the_trash_for_its_days_is_deleted_on_opening() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let old = store
        .save_entry(EntryDraft {
            images: vec![new_image("cabai")],
            ..draft(garden.id, "2026-11-02T08:00:00+07:00", "Lama.")
        })
        .unwrap();
    store
        .save_entry(EntryDraft {
            images: vec![new_image("pantai")],
            ..draft(trips.id, "2026-11-03T08:00:00+07:00", "Pantai.")
        })
        .unwrap();
    store.trash_entries(&[old.id]).unwrap();
    store.trash_book(trips.id).unwrap();
    deleted_earlier(&store, i64::from(DEFAULT_TRASH_DAYS) - 1);
    drop(store);

    // A day short of the time, everything stays.
    let store = open(&dir);
    assert_eq!(store.trash_count().unwrap(), 2);
    deleted_earlier(&store, 2);
    let recent = store
        .save_entry(draft(garden.id, "2026-11-04T08:00:00+07:00", "Baru."))
        .unwrap();
    store.trash_entries(&[recent.id]).unwrap();
    drop(store);

    let store = open(&dir);
    let trash = store.list_trash().unwrap();
    assert!(matches!(
        &trash[..],
        [TrashItem { content: TrashContent::Entry { entry, .. }, .. }] if entry.id == recent.id
    ));
    assert!(matches!(
        store.get_book(trips.id),
        Err(StoreError::NotFound)
    ));
    assert!(matches!(store.get_entry(old.id), Err(StoreError::NotFound)));
    assert!(image_files(&dir).is_empty());
}

#[test]
fn moving_to_the_trash_and_back_is_all_or_nothing() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let entries: Vec<Id> = ["Satu.", "Dua."]
        .iter()
        .map(|text| {
            store
                .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", text))
                .unwrap()
                .id
        })
        .collect();

    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(store.trash_entries(&entries).is_err());
    assert_eq!(store.trash_count().unwrap(), 0);
    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(store.trash_book(garden.id).is_err());
    assert_eq!(store.trash_count().unwrap(), 0);

    // Missing items are left out.
    store
        .trash_entries(&[entries[0], entries[1], Id::random().unwrap()])
        .unwrap();
    store.trash_book(Id::random().unwrap()).unwrap();
    assert_eq!(store.trash_count().unwrap(), 2);

    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(store.restore(&[], &entries, None).is_err());
    assert_eq!(store.trash_count().unwrap(), 2);
    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(store.delete_forever(&[], &entries).is_err());
    assert_eq!(store.trash_count().unwrap(), 2);
    store.fail_before_commit.store(false, Ordering::SeqCst);
}

#[test]
fn the_trash_survives_reopening_and_a_rebuild_of_the_index() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let kept = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Tetap."))
        .unwrap();
    let gone = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Hapus."))
        .unwrap();
    store.trash_entries(&[gone.id]).unwrap();
    drop(store);

    let store = open(&dir);
    store.rebuild_index().unwrap();
    assert_eq!(entry_texts(&store, garden.id), ["Tetap."]);
    assert_eq!(
        store.get_book(garden.id).unwrap().last_activity_at,
        kept.updated_at
    );
    assert_eq!(store.trash_count().unwrap(), 1);
}

#[test]
fn trashing_and_restoring_tell_the_listeners() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let entry = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();
    let changes = Arc::new(Mutex::new(Vec::new()));
    store.subscribe({
        let changes = Arc::clone(&changes);
        move |change| changes.lock().unwrap().push(change)
    });

    store.trash_entries(&[entry.id]).unwrap();
    store.restore(&[], &[entry.id], None).unwrap();
    store.trash_book(garden.id).unwrap();
    store.restore(&[garden.id], &[], None).unwrap();
    let on_entry = Change {
        book_id: garden.id,
        entry_id: Some(entry.id),
    };
    let on_book = Change {
        book_id: garden.id,
        entry_id: None,
    };
    assert_eq!(
        *changes.lock().unwrap(),
        [on_entry, on_entry, on_book, on_book]
    );
}

#[test]
fn the_trash_keeps_what_is_deleted_for_the_days_chosen() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let entry = store
        .save_entry(draft(garden.id, "2026-11-01T08:00:00+07:00", "Satu."))
        .unwrap();
    store.trash_entries(&[entry.id]).unwrap();
    assert_eq!(store.trash_days().unwrap(), DEFAULT_TRASH_DAYS);

    store.set_trash_days(90).unwrap();
    let [item] = &store.list_trash().unwrap()[..] else {
        panic!("not one item");
    };
    assert_eq!(item.purge_at - item.deleted_at, 90 * DAY_MS);
    assert!(matches!(
        store.set_trash_days(14),
        Err(StoreError::Invalid(_))
    ));
    assert_eq!(store.trash_days().unwrap(), 90);

    // The choice stays, and opening deletes for good by it.
    store.set_trash_days(7).unwrap();
    deleted_earlier(&store, 8);
    drop(store);
    let store = open(&dir);
    assert_eq!(store.trash_days().unwrap(), 7);
    assert_eq!(store.trash_count().unwrap(), 0);
    assert!(matches!(
        store.get_entry(entry.id),
        Err(StoreError::NotFound)
    ));
}

#[test]
fn fewer_days_delete_what_is_past_them_at_once_and_more_days_keep_it() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let old = store
        .save_entry(EntryDraft {
            images: vec![new_image("cabai")],
            ..draft(garden.id, "2026-11-01T08:00:00+07:00", "Lama.")
        })
        .unwrap();
    store.trash_entries(&[old.id]).unwrap();
    store.trash_book(trips.id).unwrap();
    deleted_earlier(&store, 10);
    let recent = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Baru."))
        .unwrap();
    store.trash_entries(&[recent.id]).unwrap();

    // Longer keeps everything.
    store.set_trash_days(90).unwrap();
    assert_eq!(store.trash_count().unwrap(), 3);

    let changes = Arc::new(Mutex::new(Vec::new()));
    store.subscribe({
        let changes = Arc::clone(&changes);
        move |change| changes.lock().unwrap().push(change)
    });
    store.set_trash_days(7).unwrap();

    let trash = store.list_trash().unwrap();
    assert!(matches!(
        &trash[..],
        [TrashItem { content: TrashContent::Entry { entry, .. }, .. }] if entry.id == recent.id
    ));
    assert!(matches!(store.get_entry(old.id), Err(StoreError::NotFound)));
    assert!(matches!(
        store.get_book(trips.id),
        Err(StoreError::NotFound)
    ));
    assert!(image_files(&dir).is_empty());
    assert_eq!(changes.lock().unwrap().len(), 2);

    // Nothing past the days: no change to tell.
    store.set_trash_days(30).unwrap();
    assert_eq!(changes.lock().unwrap().len(), 2);
}

#[test]
fn locked_books_stay_out_of_the_timeline_whatever_their_choice() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let diary = store.create_book("Rahasia").unwrap();
    let shown = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Cabai."))
        .unwrap();
    store
        .save_entry(draft(diary.id, "2026-11-01T08:00:00+07:00", "Rahasia."))
        .unwrap();
    store.set_books_locked(&[diary.id], true).unwrap();

    let timeline = store
        .list_all_entries(EntryOrder::NewestFirst, None, 50)
        .unwrap();
    assert_eq!(
        timeline.iter().map(|e| e.id).collect::<Vec<_>>(),
        [shown.id]
    );
    assert_eq!(
        store.oldest_timeline_day(420).unwrap().as_deref(),
        Some("2026-11-02")
    );
    assert_eq!(
        store
            .timeline_days("2026-11-01", "2026-11-30", 420)
            .unwrap(),
        ["2026-11-02"]
    );

    // Unlocked, it is back as it was.
    store.set_books_locked(&[diary.id], false).unwrap();
    assert_eq!(
        store
            .list_all_entries(EntryOrder::NewestFirst, None, 50)
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn search_across_all_books_leaves_locked_books_out_and_within_one_does_not() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let diary = store.create_book("Rahasia").unwrap();
    let open_hit = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Hujan pagi."))
        .unwrap();
    let locked_hit = store
        .save_entry(draft(diary.id, "2026-11-01T08:00:00+07:00", "Hujan malam."))
        .unwrap();
    store.set_books_locked(&[diary.id], true).unwrap();

    let all = store.search("hujan", None, 50, 0).unwrap();
    assert_eq!(
        all.hits.iter().map(|h| h.entry.id).collect::<Vec<_>>(),
        [open_hit.id]
    );
    assert_eq!(all.total, 1);
    assert_eq!(
        all.per_book.iter().map(|c| c.book_id).collect::<Vec<_>>(),
        [garden.id]
    );

    let within = store.search("hujan", Some(diary.id), 50, 0).unwrap();
    assert_eq!(
        within.hits.iter().map(|h| h.entry.id).collect::<Vec<_>>(),
        [locked_hit.id]
    );
    assert_eq!(within.total, 1);
    // The other Books' counts still leave out Locked Books but the one searched.
    let mut books = within
        .per_book
        .iter()
        .map(|c| c.book_id)
        .collect::<Vec<_>>();
    books.sort();
    let mut expected = vec![garden.id, diary.id];
    expected.sort();
    assert_eq!(books, expected);
}

#[test]
fn the_trash_says_which_items_belong_to_locked_books() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let diary = store.create_book("Rahasia").unwrap();
    let notes = store.create_book("Catatan").unwrap();
    let from_garden = store
        .save_entry(draft(garden.id, "2026-11-02T08:00:00+07:00", "Cabai."))
        .unwrap();
    let from_diary = store
        .save_entry(draft(diary.id, "2026-11-01T08:00:00+07:00", "Rahasia."))
        .unwrap();
    store.set_books_locked(&[diary.id, notes.id], true).unwrap();
    store
        .trash_entries(&[from_garden.id, from_diary.id])
        .unwrap();
    store.trash_book(notes.id).unwrap();

    let mut locked = store
        .list_trash()
        .unwrap()
        .into_iter()
        .map(|item| match item.content {
            TrashContent::Book(book) => (book.id, book.locked),
            TrashContent::Entry {
                entry, book_locked, ..
            } => (entry.id, book_locked),
        })
        .collect::<Vec<_>>();
    locked.sort();
    let mut expected = vec![
        (from_garden.id, false),
        (from_diary.id, true),
        (notes.id, true),
    ];
    expected.sort();
    assert_eq!(locked, expected);
}

fn names_of(books: Vec<BookInfo>) -> Vec<String> {
    books.into_iter().map(|book| book.name).collect()
}

fn lock_record(store: &Store, book_id: Id) -> Option<LockRecord> {
    let inner = lock(&store.inner);
    inner
        .conn
        .query_row(
            "SELECT record FROM book_lock WHERE book_id = ?1",
            [book_id],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .optional()
        .unwrap()
        .map(|record| open_lock_record(&record, inner.keyring.master()).unwrap())
}

#[test]
fn a_locked_book_leaves_the_book_list_unpinned_and_keeps_its_timeline_choice() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    let entry = store
        .save_entry(draft(trips.id, "2026-11-01T08:00:00+07:00", "Pantai."))
        .unwrap();
    store.set_books_pinned(&[trips.id], true).unwrap();
    store.set_book_in_timeline(trips.id, false).unwrap();

    store.set_books_locked(&[trips.id], true).unwrap();

    assert_eq!(names_of(store.list_books().unwrap()), ["Kebun"]);
    assert_eq!(names_of(store.list_locked_books().unwrap()), ["Perjalanan"]);
    let locked = store.get_book(trips.id).unwrap();
    assert!(locked.locked);
    assert!(!locked.pinned);
    assert!(!locked.in_timeline);
    assert!(!store.get_book(garden.id).unwrap().locked);
    // Not encryption: the Book and its Entries open as before.
    assert_eq!(store.get_entry(entry.id).unwrap().text, "Pantai.");
    let record = lock_record(&store, trips.id).unwrap();
    assert_eq!(record.book_id, trips.id);
    // Locking it again changes nothing, not even when it was locked.
    store.set_books_locked(&[trips.id], true).unwrap();
    assert_eq!(lock_record(&store, trips.id), Some(record));

    store.set_books_locked(&[trips.id], false).unwrap();

    assert_eq!(
        names_of(store.list_books().unwrap()),
        ["Perjalanan", "Kebun"]
    );
    assert!(store.list_locked_books().unwrap().is_empty());
    assert_eq!(lock_record(&store, trips.id), None);
    // The pin stays off; the Timeline choice was kept all along.
    let unlocked = store.get_book(trips.id).unwrap();
    assert!(!unlocked.pinned);
    assert!(!unlocked.in_timeline);
}

#[test]
fn locking_is_all_or_nothing_and_tells_the_listeners() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let heard = Arc::new(Mutex::new(Vec::new()));
    store.subscribe({
        let heard = Arc::clone(&heard);
        move |change| heard.lock().unwrap().push(change.book_id)
    });

    assert!(matches!(
        store.set_books_locked(&[garden.id, Id::from_bytes([9; Id::LEN])], true),
        Err(StoreError::NotFound)
    ));
    assert!(!store.get_book(garden.id).unwrap().locked);
    assert!(heard.lock().unwrap().is_empty());

    store.set_books_locked(&[garden.id], true).unwrap();
    assert_eq!(*heard.lock().unwrap(), [garden.id]);
}

#[test]
fn a_locked_book_stays_locked_through_the_trash_and_its_lock_goes_with_it() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    let trips = store.create_book("Perjalanan").unwrap();
    store
        .set_books_locked(&[garden.id, trips.id], true)
        .unwrap();

    store.trash_book(garden.id).unwrap();
    store.trash_book(trips.id).unwrap();
    assert!(store.list_locked_books().unwrap().is_empty());
    assert!(lock_record(&store, garden.id).is_some());

    store.restore(&[garden.id], &[], None).unwrap();
    assert_eq!(names_of(store.list_locked_books().unwrap()), ["Kebun"]);
    assert!(store.list_books().unwrap().is_empty());

    store.delete_forever(&[trips.id], &[]).unwrap();
    assert_eq!(lock_record(&store, trips.id), None);
    assert_eq!(count(&store, "book_lock"), 1);
}

#[test]
fn locks_survive_reopening_and_a_rebuild_of_the_index() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    store.set_books_locked(&[garden.id], true).unwrap();
    let record = lock_record(&store, garden.id).unwrap();
    drop(store);

    let store = open(&dir);
    // Spoil a plaintext column; the rebuild takes it from the record.
    lock(&store.inner)
        .conn
        .execute("UPDATE book_lock SET locked_at = 0", [])
        .unwrap();
    store.rebuild_index().unwrap();
    let locked_at: i64 = lock(&store.inner)
        .conn
        .query_row("SELECT locked_at FROM book_lock", [], |row| row.get(0))
        .unwrap();
    assert_eq!(locked_at, record.locked_at);
    assert_eq!(names_of(store.list_locked_books().unwrap()), ["Kebun"]);
}

/// Reads an Archive back: its `kronoer.json` and every file name with its bytes.
fn read_archive(bytes: &[u8]) -> (serde_json::Value, Vec<(String, Vec<u8>)>) {
    use std::io::Read;
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(bytes)).unwrap();
    let mut files = Vec::new();
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).unwrap();
        let mut content = Vec::new();
        file.read_to_end(&mut content).unwrap();
        files.push((file.name().unwrap().into_owned(), content));
    }
    let json = &files
        .iter()
        .find(|(name, _)| name == ARCHIVE_DATA_FILE)
        .unwrap()
        .1;
    (serde_json::from_slice(json).unwrap(), files)
}

#[test]
fn exports_every_book_with_its_entries_images_stars_and_locks() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let garden = store.create_book("Kebun").unwrap();
    store
        .set_book_description(garden.id, "Tanaman di belakang rumah")
        .unwrap();
    store
        .set_book_cover(garden.id, b"cover full", b"cover thumbnail")
        .unwrap();
    let secret = store.create_book("Rahasia").unwrap();
    store.set_books_locked(&[secret.id], true).unwrap();
    let gone = store.create_book("Dihapus").unwrap();

    let mut first = draft(garden.id, "2026-11-16T19:40:00+07:00", "**Hujan** pagi");
    first.images = vec![new_image("one"), new_image("two")];
    let first = store.save_entry(first).unwrap();
    let second = store
        .save_entry(draft(
            secret.id,
            "2026-11-14T21:15:00+07:00",
            "Rahasia kecil",
        ))
        .unwrap();
    let trashed = store
        .save_entry(draft(garden.id, "2026-11-15T08:00:00+07:00", "Dibuang"))
        .unwrap();
    store
        .save_entry(draft(gone.id, "2026-11-13T08:00:00+07:00", "Ikut terbuang"))
        .unwrap();
    store.set_entries_starred(&[first.id], true).unwrap();
    store.trash_entries(&[trashed.id]).unwrap();
    store.trash_book(gone.id).unwrap();
    assert_eq!(store.exportable_entry_count().unwrap(), 2);

    let mut steps = Vec::new();
    let mut bytes = Vec::new();
    let summary = store
        .export_archive(&mut bytes, 1_795_494_824_123, |progress| {
            steps.push(progress);
            true
        })
        .unwrap();
    assert_eq!(
        summary,
        ExportSummary {
            book_count: 2,
            entry_count: 2,
            image_count: 3,
        }
    );
    // Once before anything, then after each of two Entries and three Images.
    assert_eq!(steps.len(), 6);
    assert!(steps.iter().all(|step| step.total == 5));
    assert_eq!(
        steps.iter().map(|step| step.done).collect::<Vec<_>>(),
        [0, 1, 2, 3, 4, 5]
    );

    let (json, files) = read_archive(&bytes);
    let names: Vec<&str> = files.iter().map(|(name, _)| name.as_str()).collect();
    let cover_id = store.get_book(garden.id).unwrap().cover_id.unwrap();
    let image_name = |id: Id| format!("images/{}.jpg", id.to_hex());
    assert_eq!(
        names,
        [
            ARCHIVE_README_FILE.to_owned(),
            ARCHIVE_DATA_FILE.to_owned(),
            image_name(cover_id),
            image_name(first.image_ids[0]),
            image_name(first.image_ids[1]),
        ]
    );
    assert_eq!(files[2].1, b"cover full");
    assert_eq!(files[3].1, b"one full");
    assert_eq!(files[4].1, b"two full");
    assert!(String::from_utf8_lossy(&files[0].1).contains("NOT encrypted"));

    assert_eq!(json["format"], ARCHIVE_FORMAT);
    assert_eq!(json["format_version"], ARCHIVE_FORMAT_VERSION);
    assert_eq!(json["exported_at"], "2026-11-24T04:33:44.123Z");
    let books = json["books"].as_array().unwrap();
    assert_eq!(books.len(), 2);
    let kebun = books
        .iter()
        .find(|book| book["id"] == garden.id.to_hex())
        .unwrap();
    assert_eq!(kebun["name"], "Kebun");
    assert_eq!(kebun["description"], "Tanaman di belakang rumah");
    assert_eq!(kebun["cover_image_id"], cover_id.to_hex());
    let rahasia = books
        .iter()
        .find(|book| book["id"] == secret.id.to_hex())
        .unwrap();
    assert_eq!(rahasia["cover_image_id"], serde_json::Value::Null);
    assert_eq!(
        json["locked_book_ids"],
        serde_json::json!([secret.id.to_hex()])
    );
    assert_eq!(
        json["starred_entry_ids"],
        serde_json::json!([first.id.to_hex()])
    );

    // Oldest first, by Entry date as written.
    let entries = json["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 2);
    assert_eq!(entries[0]["id"], second.id.to_hex());
    assert_eq!(entries[1]["id"], first.id.to_hex());
    assert_eq!(entries[1]["book_id"], garden.id.to_hex());
    assert_eq!(entries[1]["entry_date"], "2026-11-16T19:40:00+07:00");
    assert_eq!(entries[1]["text"], "**Hujan** pagi");
    assert_eq!(
        entries[1]["image_ids"],
        serde_json::json!([first.image_ids[0].to_hex(), first.image_ids[1].to_hex()])
    );
    assert_eq!(entries[1]["created_at"], export::utc_time(first.created_at));
    assert_eq!(entries[1]["updated_at"], export::utc_time(first.updated_at));
}

#[test]
fn exports_an_empty_store() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let mut bytes = Vec::new();
    let summary = store.export_archive(&mut bytes, 0, |_| true).unwrap();
    assert_eq!(summary.entry_count, 0);
    let (json, files) = read_archive(&bytes);
    assert_eq!(files.len(), 2);
    assert_eq!(json["books"], serde_json::json!([]));
    assert_eq!(json["entries"], serde_json::json!([]));
}

#[test]
fn export_activity_counts_what_an_export_would_write() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let none = ExportActivity {
        first_created_at: None,
        created_since: 0,
    };
    assert_eq!(store.export_activity(None).unwrap(), none);
    assert_eq!(store.export_activity(Some(0)).unwrap(), none);

    let garden = store.create_book("Kebun").unwrap();
    let secret = store.create_book("Rahasia").unwrap();
    store.set_books_locked(&[secret.id], true).unwrap();
    let gone = store.create_book("Dihapus").unwrap();
    let [first, second, third, trashed, _] = save_in_turn(
        &store,
        [
            draft(garden.id, "2026-11-10T08:00:00+07:00", "Satu"),
            draft(secret.id, "2026-11-11T08:00:00+07:00", "Dua"),
            draft(garden.id, "2026-11-01T08:00:00+07:00", "Tiga"),
            draft(garden.id, "2026-11-12T08:00:00+07:00", "Dibuang"),
            draft(gone.id, "2026-11-13T08:00:00+07:00", "Ikut terbuang"),
        ],
    )
    .try_into()
    .unwrap();
    store.trash_entries(&[trashed.id]).unwrap();
    store.trash_book(gone.id).unwrap();

    // By when each was created, not by its Entry date; Locked Books count, the Trash does not.
    let activity = |since| store.export_activity(since).unwrap();
    assert_eq!(
        activity(None),
        ExportActivity {
            first_created_at: Some(first.created_at),
            created_since: 3,
        }
    );
    assert_eq!(activity(Some(first.created_at)).created_since, 2);
    assert_eq!(activity(Some(second.created_at)).created_since, 1);
    assert_eq!(activity(Some(third.created_at)).created_since, 0);
    assert_eq!(
        activity(Some(third.created_at)).first_created_at,
        Some(first.created_at)
    );
}

#[test]
fn an_export_stops_when_asked() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Buku").unwrap();
    for day in 10..15 {
        store
            .save_entry(draft(
                book.id,
                &format!("2026-11-{day}T08:00:00+07:00"),
                "Hari",
            ))
            .unwrap();
    }
    let mut bytes = Vec::new();
    let result = store.export_archive(&mut bytes, 0, |progress| progress.done < 2);
    assert!(matches!(result, Err(StoreError::Cancelled)));
}

/// A file that takes only so many bytes, like storage that fills up.
struct Full(usize);

impl std::io::Write for Full {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        if self.0 < buf.len() {
            return Err(std::io::ErrorKind::StorageFull.into());
        }
        self.0 -= buf.len();
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[test]
fn a_full_disk_fails_the_export_as_a_write_failure() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Buku").unwrap();
    let mut entry = draft(book.id, "2026-11-16T19:40:00+07:00", "Foto");
    entry.images = vec![ImageInput::New {
        full: vec![9; 200_000],
        thumbnail: vec![8; 100],
    }];
    store.save_entry(entry).unwrap();
    match store.export_archive(Full(50_000), 0, |_| true) {
        Err(StoreError::ArchiveWrite(error)) => {
            assert_eq!(error.kind(), std::io::ErrorKind::StorageFull);
        }
        other => panic!("expected a write failure, got {other:?}"),
    }
}

/// A JPEG of `width` × `height`, as Kronoer stores one: nothing but the picture.
pub(super) fn jpeg(width: u32, height: u32) -> Vec<u8> {
    let image = image::RgbImage::from_fn(width, height, |x, y| {
        image::Rgb([(x * 7) as u8, (y * 5) as u8, ((x + y) * 3) as u8])
    });
    let mut out = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 85)
        .encode_image(&image)
        .unwrap();
    out
}

/// A JPEG of `width` × `height` with an EXIF segment, a comment, and bytes after its end.
pub(super) fn jpeg_with_metadata(width: u32, height: u32) -> Vec<u8> {
    let plain = jpeg(width, height);
    let mut with = plain[..2].to_vec();
    with.extend_from_slice(&[0xFF, 0xE1, 0x00, 0x0C]);
    with.extend_from_slice(b"Exif\0\0GPS!");
    with.extend_from_slice(&[0xFF, 0xFE, 0x00, 0x07]);
    with.extend_from_slice(b"hello");
    with.extend_from_slice(&plain[2..]);
    with.extend_from_slice(b"trailing data");
    with
}

fn jpeg_image(width: u32, height: u32) -> ImageInput {
    ImageInput::New {
        full: jpeg_with_metadata(width, height),
        thumbnail: jpeg(8, 8),
    }
}

/// Another install: its own folder and its own master key.
fn open_other(dir: &TempDir) -> Store {
    Store::open(
        dir.path(),
        Keyring::new(MasterKey::from_secret(Zeroizing::new([9; 32]))),
    )
    .unwrap()
}

fn export(store: &Store) -> Vec<u8> {
    let mut bytes = Vec::new();
    store
        .export_archive(&mut bytes, 1_795_494_824_123, |_| true)
        .unwrap();
    bytes
}

fn import(store: &Store, archive: &[u8]) -> Result<ImportSummary> {
    store.import_archive(std::io::Cursor::new(archive), |_| true)
}

fn imported(summary: &ImportSummary, id: Id) -> &ImportedBook {
    summary.books.iter().find(|book| book.id == id).unwrap()
}

/// A device with two Books: Kebun, with a Description, a Cover, and two Entries, one starred with
/// two Images; and Rahasia, locked, with one Entry.
struct Source {
    store: Store,
    garden: BookInfo,
    secret: BookInfo,
    rain: StoredEntry,
    seeds: StoredEntry,
    hidden: StoredEntry,
}

fn source(dir: &TempDir) -> Source {
    let store = open(dir);
    let garden = store.create_book("Kebun").unwrap();
    store
        .set_book_description(garden.id, "Tanaman di belakang rumah")
        .unwrap();
    store
        .set_book_cover(garden.id, &jpeg_with_metadata(48, 64), &jpeg(6, 8))
        .unwrap();
    let secret = store.create_book("Rahasia").unwrap();
    let mut rain = draft(garden.id, "2026-11-16T19:40:00+07:00", "**Hujan** pagi");
    rain.images = vec![jpeg_image(1200, 600), jpeg_image(40, 30)];
    let rain = store.save_entry(rain).unwrap();
    let seeds = store
        .save_entry(draft(garden.id, "2026-11-10T08:00:00+07:00", "Bibit"))
        .unwrap();
    let hidden = store
        .save_entry(draft(
            secret.id,
            "2026-11-14T21:15:00+07:00",
            "Rahasia kecil",
        ))
        .unwrap();
    store.set_entries_starred(&[rain.id], true).unwrap();
    store.set_books_locked(&[secret.id], true).unwrap();
    Source {
        garden: store.get_book(garden.id).unwrap(),
        secret,
        rain: store.get_entry(rain.id).unwrap(),
        seeds,
        hidden,
        store,
    }
}

#[test]
fn imports_an_archive_from_another_install() {
    let from = TempDir::new().unwrap();
    let source = source(&from);
    let archive = export(&source.store);

    let dir = TempDir::new().unwrap();
    let store = open_other(&dir);
    let mut steps = Vec::new();
    let summary = store
        .import_archive(std::io::Cursor::new(&archive), |step| {
            steps.push(step);
            true
        })
        .unwrap();

    let counts = ArchiveCounts {
        book_count: 2,
        entry_count: 3,
        image_count: 3,
    };
    assert_eq!(summary.archive, counts);
    assert_eq!(summary.added_book_count(), 2);
    assert_eq!(summary.added_entry_count(), 3);
    assert_eq!(summary.existing_entry_count(), 0);
    assert_eq!(summary.trashed_entry_count(), 0);
    let garden = imported(&summary, source.garden.id);
    assert_eq!(garden.name, "Kebun");
    assert!(garden.added && !garden.locked && !garden.in_trash);
    assert_eq!(garden.added_entry_count, 2);
    assert!(imported(&summary, source.secret.id).locked);
    // Checking, then once before the first new Entry and after each of the three.
    assert_eq!(steps[0], ImportProgress::Checking);
    let done: Vec<u32> = steps[1..]
        .iter()
        .map(|step| match *step {
            ImportProgress::Adding {
                archive,
                new_book_count,
                new_entry_count,
                done,
            } => {
                assert_eq!((archive, new_book_count, new_entry_count), (counts, 2, 3));
                done
            }
            ImportProgress::Checking => panic!("checking after adding"),
        })
        .collect();
    assert_eq!(done, [0, 1, 2, 3]);

    // The same Books, with their IDs and what they hold.
    let book = store.get_book(source.garden.id).unwrap();
    assert_eq!(book.description, "Tanaman di belakang rumah");
    assert_eq!(book.entry_count, 2);
    assert_eq!(
        book.last_activity_at,
        source.rain.updated_at.max(source.seeds.updated_at)
    );
    assert_eq!(names_of(store.list_locked_books().unwrap()), ["Rahasia"]);
    assert_eq!(names_of(store.list_books().unwrap()), ["Kebun"]);

    // The same Entries, with their IDs and times, and the star.
    let rain = store.get_entry(source.rain.id).unwrap();
    assert_eq!(rain.text, "**Hujan** pagi");
    assert_eq!(rain.date, source.rain.date);
    assert_eq!(
        (rain.created_at, rain.updated_at),
        (source.rain.created_at, source.rain.updated_at)
    );
    assert!(rain.starred);
    assert!(!store.get_entry(source.seeds.id).unwrap().starred);
    assert_eq!(
        store.get_entry(source.hidden.id).unwrap().text,
        "Rahasia kecil"
    );

    // Each Image without its metadata, and a thumbnail made from it.
    assert_eq!(rain.image_ids.len(), 2);
    let full = store
        .get_image(rain.id, rain.image_ids[0], ImageVariant::Full)
        .unwrap();
    assert_eq!(full, jpeg(1200, 600));
    let thumbnail = store
        .get_image(rain.id, rain.image_ids[0], ImageVariant::Thumbnail)
        .unwrap();
    let thumbnail = image::load_from_memory(&thumbnail).unwrap();
    assert_eq!((thumbnail.width(), thumbnail.height()), (512, 256));
    assert_eq!(
        store.get_book_cover(book.id, ImageVariant::Full).unwrap(),
        jpeg(48, 64)
    );
    let cover = image::load_from_memory(
        &store
            .get_book_cover(book.id, ImageVariant::Thumbnail)
            .unwrap(),
    )
    .unwrap();
    assert_eq!((cover.width(), cover.height()), (48, 64));
    // Two files for each of the three Images, and none left over.
    assert_eq!(image_files(&dir).len(), 6);
    assert!(search_ids(&store, "hujan").contains(&rain.id));

    // Sealed with this device's keys: it opens again after reopening.
    drop(store);
    let store = open_other(&dir);
    store.rebuild_index().unwrap();
    assert_eq!(store.get_entry(rain.id).unwrap().text, "**Hujan** pagi");
}

fn search_ids(store: &Store, query: &str) -> Vec<Id> {
    store
        .search(query, None, 10, 0)
        .unwrap()
        .hits
        .into_iter()
        .map(|hit| hit.entry.id)
        .collect()
}

#[test]
fn importing_the_same_archive_twice_adds_nothing_the_second_time() {
    let from = TempDir::new().unwrap();
    let source = source(&from);
    let archive = export(&source.store);
    let dir = TempDir::new().unwrap();
    let store = open_other(&dir);
    import(&store, &archive).unwrap();
    let files = image_files(&dir);

    let summary = import(&store, &archive).unwrap();
    assert_eq!(summary.added_book_count(), 0);
    assert_eq!(summary.added_entry_count(), 0);
    assert_eq!(summary.existing_entry_count(), 3);
    assert_eq!(imported(&summary, source.garden.id).existing_entry_count, 2);
    assert_eq!(image_files(&dir), files, "no Image is written again");
    assert_eq!(count(&store, "entry"), 3);
}

#[test]
fn skips_what_this_device_has_wherever_it_is_and_brings_back_what_was_deleted_for_good() {
    let dir = TempDir::new().unwrap();
    let source = source(&dir);
    let store = &source.store;
    let archive = export(store);

    // Changed after the Export: the change stays, a newer time or not.
    let mut changed = draft(source.garden.id, "2026-11-16T19:40:00+07:00", "Diubah");
    changed.id = Some(source.seeds.id);
    store.save_entry(changed).unwrap();
    // In the Trash on its own: it stays there.
    store.trash_entries(&[source.rain.id]).unwrap();
    // Deleted for good: it comes back.
    store.delete_forever(&[], &[source.hidden.id]).unwrap();
    // Unstarred and unlocked after the Export: they stay so.
    store.set_books_locked(&[source.secret.id], false).unwrap();

    let summary = import(store, &archive).unwrap();
    assert_eq!(summary.added_entry_count(), 1);
    assert_eq!(summary.existing_entry_count(), 2);
    assert_eq!(store.get_entry(source.seeds.id).unwrap().text, "Diubah");
    assert_eq!(store.trash_count().unwrap(), 1);
    let hidden = store.get_entry(source.hidden.id).unwrap();
    assert_eq!(hidden.text, "Rahasia kecil");
    assert_eq!(hidden.created_at, source.hidden.created_at);
    let secret = imported(&summary, source.secret.id);
    assert!(!secret.added && !secret.locked);
    assert_eq!(secret.added_entry_count, 1);
    assert!(store.list_locked_books().unwrap().is_empty());
}

#[test]
fn a_book_deleted_for_good_comes_back_with_its_lock_and_stars() {
    let dir = TempDir::new().unwrap();
    let source = source(&dir);
    let store = &source.store;
    let archive = export(store);
    store
        .delete_forever(&[source.garden.id, source.secret.id], &[])
        .unwrap();
    assert!(image_files(&dir).is_empty());

    let summary = import(store, &archive).unwrap();
    assert_eq!(summary.added_book_count(), 2);
    assert_eq!(summary.added_entry_count(), 3);
    assert!(store.get_entry(source.rain.id).unwrap().starred);
    assert_eq!(names_of(store.list_locked_books().unwrap()), ["Rahasia"]);
    assert!(store.get_book(source.garden.id).unwrap().cover_id.is_some());
}

#[test]
fn skips_the_new_entries_of_a_book_in_the_trash() {
    let from = TempDir::new().unwrap();
    let source = source(&from);
    let dir = TempDir::new().unwrap();
    let store = open_other(&dir);
    import(&store, &export(&source.store)).unwrap();
    store.trash_book(source.garden.id).unwrap();

    let late = source
        .store
        .save_entry(draft(source.garden.id, "2026-11-20T08:00:00+07:00", "Baru"))
        .unwrap();
    let summary = import(&store, &export(&source.store)).unwrap();
    let garden = imported(&summary, source.garden.id);
    assert!(garden.in_trash);
    assert_eq!(garden.name, "Kebun");
    assert_eq!(
        (
            garden.added_entry_count,
            garden.existing_entry_count,
            garden.trashed_entry_count
        ),
        (0, 2, 1)
    );
    assert_eq!(summary.trashed_entry_count(), 1);
    assert!(matches!(
        store.get_entry(late.id),
        Err(StoreError::NotFound)
    ));
    assert_eq!(
        store.trash_count().unwrap(),
        1,
        "the Book stays in the Trash"
    );

    // Restored, the next Import adds it.
    store.restore(&[source.garden.id], &[], None).unwrap();
    let summary = import(&store, &export(&source.store)).unwrap();
    assert_eq!(summary.added_entry_count(), 1);
    assert_eq!(store.get_entry(late.id).unwrap().text, "Baru");
}

#[test]
fn locks_and_stars_are_only_set_on_what_the_import_adds() {
    let from = TempDir::new().unwrap();
    let source = source(&from);
    let dir = TempDir::new().unwrap();
    let store = open_other(&dir);
    import(&store, &export(&source.store)).unwrap();
    store.set_books_locked(&[source.secret.id], false).unwrap();
    store.set_entries_starred(&[source.rain.id], false).unwrap();

    let late = source
        .store
        .save_entry(draft(source.secret.id, "2026-11-20T08:00:00+07:00", "Lagi"))
        .unwrap();
    source.store.set_entries_starred(&[late.id], true).unwrap();
    let summary = import(&store, &export(&source.store)).unwrap();

    assert_eq!(summary.added_entry_count(), 1);
    assert!(store.list_locked_books().unwrap().is_empty());
    assert!(!store.get_entry(source.rain.id).unwrap().starred);
    assert!(store.get_entry(late.id).unwrap().starred);
    let star = lock(&store.inner)
        .conn
        .query_row(
            "SELECT record FROM star WHERE entry_id = ?1",
            [late.id],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .unwrap();
    let master = MasterKey::from_secret(Zeroizing::new([9; 32]));
    assert_eq!(
        crate::open_star_record(&star, &master).unwrap().entry_id,
        late.id
    );
}

/// Writes a ZIP with `kronoer.json` and the given files.
fn zip_of(json: &serde_json::Value, files: &[(String, Vec<u8>)]) -> Vec<u8> {
    use std::io::Write;
    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    let options =
        zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    zip.start_file(ARCHIVE_DATA_FILE, options).unwrap();
    zip.write_all(json.to_string().as_bytes()).unwrap();
    for (name, bytes) in files {
        zip.start_file(name.as_str(), options).unwrap();
        zip.write_all(bytes).unwrap();
    }
    zip.finish().unwrap().into_inner()
}

/// An Archive with one Book and one Entry with one Image, as `kronoer.json` and its files.
fn small_archive() -> (serde_json::Value, Vec<(String, Vec<u8>)>) {
    let book = Id::random().unwrap().to_hex();
    let image = Id::random().unwrap().to_hex();
    let json = serde_json::json!({
        "format": "kronoer-archive",
        "format_version": 1,
        "exported_at": "2026-11-24T04:30:00.000Z",
        "books": [{"id": book, "name": "Kebun", "description": "", "cover_image_id": null}],
        "locked_book_ids": [],
        "starred_entry_ids": [],
        "entries": [{
            "id": Id::random().unwrap().to_hex(), "book_id": book,
            "entry_date": "2026-11-17T08:00:00+07:00", "text": "Tomat",
            "image_ids": [image],
            "created_at": "2026-11-17T01:00:12.345Z", "updated_at": "2026-11-17T01:05:00.000Z",
            "added_later": true
        }],
        "something_new": {"ignored": true}
    });
    (json, vec![(format!("images/{image}.jpg"), jpeg(20, 10))])
}

#[test]
fn reads_an_archive_written_by_another_writer_and_ignores_what_it_does_not_know() {
    let (json, mut files) = small_archive();
    files.push(("notes/extra.txt".to_owned(), b"ignored".to_vec()));
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let summary = import(&store, &zip_of(&json, &files)).unwrap();
    assert_eq!(summary.added_entry_count(), 1);
    assert_eq!(names_of(store.list_books().unwrap()), ["Kebun"]);
}

/// Imports `archive` into an empty store, expecting it to fail and leave the store empty.
fn refused(archive: &[u8]) -> StoreError {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let error = import(&store, archive).unwrap_err();
    assert_eq!(count(&store, "book"), 0);
    assert_eq!(count(&store, "entry"), 0);
    assert!(image_files(&dir).is_empty(), "no Image file is left");
    error
}

#[test]
fn refuses_a_broken_archive_and_changes_nothing() {
    let damaged = |archive: &[u8]| {
        let error = refused(archive);
        assert!(
            matches!(error, StoreError::ArchiveDamaged(_)),
            "expected damage, got {error:?}"
        );
    };
    let (json, files) = small_archive();
    let whole = zip_of(&json, &files);
    damaged(b"not a zip at all");
    damaged(&whole[..whole.len() - 30]);
    damaged(&zip_of(&json, &[]));

    let mut no_data = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    no_data
        .start_file("README.txt", zip::write::SimpleFileOptions::default())
        .unwrap();
    damaged(&no_data.finish().unwrap().into_inner());

    let with = |change: &dyn Fn(&mut serde_json::Value)| {
        let mut json = json.clone();
        change(&mut json);
        zip_of(&json, &files)
    };
    damaged(&with(&|json| json["format"] = "something-else".into()));
    damaged(&with(&|json| json["format_version"] = 0.into()));
    damaged(&with(&|json| json["format_version"] = "1".into()));
    damaged(&with(&|json| {
        json.as_object_mut().unwrap().remove("entries");
    }));
    damaged(&with(&|json| {
        json["entries"][0]["book_id"] = Id::random().unwrap().to_hex().into()
    }));
    damaged(&with(&|json| json["entries"][0]["id"] = "NOT-AN-ID".into()));
    damaged(&with(&|json| {
        json["entries"][0]["entry_date"] = "2026-11-17".into()
    }));
    damaged(&with(&|json| {
        json["entries"][0]["updated_at"] = "yesterday".into()
    }));
    damaged(&with(&|json| {
        json["locked_book_ids"] = serde_json::json!([Id::random().unwrap().to_hex()])
    }));
    damaged(&with(&|json| {
        let entry = json["entries"][0].clone();
        json["entries"].as_array_mut().unwrap().push(entry);
    }));
    damaged(&with(&|json| {
        let image = json["entries"][0]["image_ids"][0].clone();
        json["books"][0]["cover_image_id"] = image;
    }));

    // A damaged file inside the ZIP: its data no longer matches its checksum.
    let mut spoiled = whole.clone();
    let at = spoiled
        .windows(5)
        .position(|w| w == b"Tomat")
        .expect("kronoer.json is stored as it is");
    spoiled[at] = b'X';
    damaged(&spoiled);
}

#[test]
fn refuses_an_archive_with_a_newer_format() {
    let (mut json, files) = small_archive();
    json["format_version"] = 2.into();
    json["entries"] = "a newer structure".into();
    assert!(matches!(
        refused(&zip_of(&json, &files)),
        StoreError::ArchiveNewer(2)
    ));
}

#[test]
fn refuses_an_image_that_does_not_open_or_is_too_large() {
    let (json, mut files) = small_archive();
    let image = |files: &mut Vec<(String, Vec<u8>)>, bytes: Vec<u8>| files[0].1 = bytes;
    for bytes in [
        b"not a jpeg".to_vec(),
        jpeg(2049, 8),
        jpeg(8, 2049),
        jpeg(20, 10)[..300].to_vec(),
    ] {
        image(&mut files, bytes);
        let error = refused(&zip_of(&json, &files));
        assert!(
            matches!(error, StoreError::ArchiveImage(_)),
            "expected an Image failure, got {error:?}"
        );
    }
    image(&mut files, jpeg(2048, 8));
    let dir = TempDir::new().unwrap();
    assert!(import(&open(&dir), &zip_of(&json, &files)).is_ok());
}

#[test]
fn an_import_that_is_stopped_or_fails_leaves_nothing_behind() {
    let from = TempDir::new().unwrap();
    let source = source(&from);
    let archive = export(&source.store);

    let dir = TempDir::new().unwrap();
    let store = open_other(&dir);
    let result = store.import_archive(std::io::Cursor::new(&archive), |step| {
        !matches!(step, ImportProgress::Adding { done: 2, .. })
    });
    assert!(matches!(result, Err(StoreError::Cancelled)));
    assert_eq!(count(&store, "book"), 0);
    assert!(image_files(&dir).is_empty());

    store.fail_before_commit.store(true, Ordering::SeqCst);
    assert!(import(&store, &archive).is_err());
    assert_eq!(count(&store, "book"), 0);
    assert_eq!(count(&store, "entry"), 0);
    assert!(image_files(&dir).is_empty());

    // Nothing stands in the way of the next one.
    assert_eq!(import(&store, &archive).unwrap().added_entry_count(), 3);
}
