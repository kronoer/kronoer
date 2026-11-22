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

    store.delete_book(book.id).unwrap();

    assert_eq!(image_files(&dir).len(), 2);
    assert_eq!(
        store.get_book_cover(kept.id, ImageVariant::Full).unwrap(),
        b"kept full"
    );
}

#[test]
fn migrates_book_records_from_before_descriptions() {
    let dir = TempDir::new().unwrap();
    let keyring = keyring();
    let book_id = Id::random().unwrap();
    let key = BookKey::generate(book_id).unwrap();
    {
        // A database as the first schema version left it.
        let conn = Connection::open(dir.path().join(DATABASE_FILE)).unwrap();
        set_key(&conn, &keyring).unwrap();
        conn.execute_batch(schema::MIGRATIONS[0].sql).unwrap();
        conn.pragma_update(None, "user_version", 1).unwrap();
        conn.execute(
            "INSERT INTO book (id, name, last_activity_at, record, record_key_version)
             VALUES (?1, 'Kebun', 5, ?2, ?3)",
            params![
                book_id,
                crate::book::seal_name_only_book_record("Kebun", &key),
                key.version()
            ],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO book_key (book_id, version, wrapped) VALUES (?1, ?2, ?3)",
            params![
                book_id,
                key.version(),
                wrap_book_key(&key, keyring.master()).unwrap()
            ],
        )
        .unwrap();
    }

    let store = Store::open(dir.path(), keyring).unwrap();
    let version: u32 = lock(&store.inner)
        .conn
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .unwrap();
    assert_eq!(version, schema::VERSION);
    let book = store.get_book(book_id).unwrap();
    assert_eq!(
        (book.name.as_str(), book.description.as_str()),
        ("Kebun", "")
    );
    // Every record now opens as a record with a Description.
    store.rebuild_index().unwrap();
    store.set_book_description(book_id, "Sayur.").unwrap();
    assert_eq!(store.get_book(book_id).unwrap().description, "Sayur.");
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

    store.delete_book(book.id).unwrap();

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

    store.delete_entry(gone.id).unwrap();
    store.delete_entry(gone.id).unwrap();
    assert!(matches!(
        store.get_entry(gone.id),
        Err(StoreError::NotFound)
    ));
    assert_eq!(image_files(&dir).len(), 4);
    let garden_now = store.get_book(garden.id).unwrap();
    assert_eq!(garden_now.last_activity_at, kept.updated_at);
    assert_eq!(garden_now.last_entry_text.as_deref(), Some("Lama."));

    store.delete_book(trips.id).unwrap();
    store.delete_book(trips.id).unwrap();
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
    store.delete_entry(entry.id).unwrap();
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

    store.delete_book(books[0]).unwrap();

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

    store.delete_entry(first.id).unwrap();

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
    assert!(store.delete_entries(&gone).is_err());
    assert_eq!(entry_texts(&store, garden.id).len(), 3);
    assert_eq!(image_files(&dir).len(), 6);

    store
        .delete_entries(&[gone[0], gone[1], Id::random().unwrap()])
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
