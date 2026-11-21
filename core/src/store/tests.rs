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
    store
        .set_book_cover(book.id, b"second full", b"second thumb")
        .unwrap();
    let second = image_files(&dir);
    assert_eq!(second.len(), 2);
    assert!(first.iter().all(|name| !second.contains(name)));

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
        store.list_entries(book.id, None, 10).unwrap(),
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

#[test]
fn pages_through_entries_with_the_same_date() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let book = store.create_book("Kebun").unwrap();
    let mut ids: Vec<Id> = (0..5)
        .map(|i| {
            store
                .save_entry(draft(
                    book.id,
                    "2026-11-17T08:00:00+07:00",
                    &format!("Sama {i}"),
                ))
                .unwrap()
                .id
        })
        .collect();
    ids.sort_by(|a, b| b.cmp(a));

    let mut listed = Vec::new();
    let mut after: Option<EntryCursor> = None;
    loop {
        let page = store.list_entries(book.id, after.as_ref(), 2).unwrap();
        let Some(last) = page.last() else { break };
        after = Some(last.into());
        listed.extend(page.iter().map(|entry| entry.id));
    }

    assert_eq!(listed, ids);
}

#[test]
fn lists_entries_newest_date_first_in_pages() {
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

    let first = store.list_entries(book.id, None, 2).unwrap();
    let second = store
        .list_entries(book.id, Some(&first.last().unwrap().into()), 2)
        .unwrap();
    let third = store
        .list_entries(book.id, Some(&second.last().unwrap().into()), 2)
        .unwrap();
    let texts: Vec<&str> = first
        .iter()
        .chain(&second)
        .chain(&third)
        .map(|entry| entry.text.as_str())
        .collect();

    assert_eq!(texts, ["Hari 5", "Hari 4", "Hari 3", "Hari 2", "Hari 1"]);
}

#[test]
fn lists_entries_of_every_book_newest_date_first_in_pages() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let kebun = store.create_book("Kebun").unwrap();
    let jalan = store.create_book("Jalan").unwrap();
    for (book, date_text, text) in [
        (kebun.id, "2026-11-03T08:00:00+07:00", "Kebun 3"),
        (jalan.id, "2026-11-05T08:00:00+07:00", "Jalan 5"),
        (kebun.id, "2019-06-01T08:00:00+07:00", "Kebun 2019"),
        (jalan.id, "2026-11-01T08:00:00+07:00", "Jalan 1"),
        (kebun.id, "2026-11-04T08:00:00+07:00", "Kebun 4"),
    ] {
        store.save_entry(draft(book, date_text, text)).unwrap();
    }

    let first = store.list_all_entries(None, 2).unwrap();
    let second = store
        .list_all_entries(Some(&first.last().unwrap().into()), 2)
        .unwrap();
    let third = store
        .list_all_entries(Some(&second.last().unwrap().into()), 2)
        .unwrap();
    let rest = store
        .list_all_entries(Some(&third.last().unwrap().into()), 2)
        .unwrap();
    let listed: Vec<(Id, &str)> = first
        .iter()
        .chain(&second)
        .chain(&third)
        .map(|entry| (entry.book_id, entry.text.as_str()))
        .collect();

    assert_eq!(
        listed,
        [
            (jalan.id, "Jalan 5"),
            (kebun.id, "Kebun 4"),
            (kebun.id, "Kebun 3"),
            (jalan.id, "Jalan 1"),
            (kebun.id, "Kebun 2019"),
        ]
    );
    assert!(rest.is_empty());
}

#[test]
fn pages_through_entries_of_every_book_with_the_same_date() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let books = [
        store.create_book("Kebun").unwrap(),
        store.create_book("Jalan").unwrap(),
    ];
    let mut ids: Vec<Id> = (0..6)
        .map(|i| {
            store
                .save_entry(draft(
                    books[i % 2].id,
                    "2026-11-17T08:00:00+07:00",
                    &format!("Sama {i}"),
                ))
                .unwrap()
                .id
        })
        .collect();
    ids.sort_by(|a, b| b.cmp(a));

    let mut listed = Vec::new();
    let mut after: Option<EntryCursor> = None;
    loop {
        let page = store.list_all_entries(after.as_ref(), 4).unwrap();
        let Some(last) = page.last() else { break };
        after = Some(last.into());
        listed.extend(page.iter().map(|entry| entry.id));
    }

    assert_eq!(listed, ids);
}

#[test]
fn every_book_listing_seeks_the_date_index() {
    let dir = TempDir::new().unwrap();
    let store = open(&dir);
    let inner = lock(&store.inner);
    let plan: Vec<String> = inner
        .conn
        .prepare(&format!(
            "EXPLAIN QUERY PLAN {SELECT_ENTRY} WHERE (e.entry_date, e.id) < (?1, ?2)
             ORDER BY e.entry_date DESC, e.id DESC LIMIT ?3"
        ))
        .unwrap()
        .query_map(
            params![
                "2026-11-17T08:00:00+07:00",
                Id::from_hex(&"01".repeat(16)).unwrap(),
                2
            ],
            |row| row.get(3),
        )
        .unwrap()
        .collect::<rusqlite::Result<_>>()
        .unwrap();

    assert!(
        plan.iter()
            .any(|step| step.contains("USING INDEX entry_by_date (")),
        "{plan:?}"
    );
    assert!(
        !plan.iter().any(|step| step.contains("TEMP B-TREE")),
        "{plan:?}"
    );
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
    assert_eq!(store.list_entries(book.id, None, 10).unwrap(), vec![saved]);
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
        store.list_entries(book.id, None, 10).unwrap(),
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
