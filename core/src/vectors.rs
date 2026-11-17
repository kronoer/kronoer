//! Generates and checks `spec/test-vectors/entry-format.json`.
//!
//! The test fails if the file differs from what this crate produces. To write the file again after
//! a deliberate format change, run `KRONOER_WRITE_VECTORS=1 cargo test -p kronoer-core vectors`.

use std::path::PathBuf;

use serde_json::{Value, json};

use crate::entry::{Header, Payload, seal_entry_with};
use crate::keys::KEY_LEN;
use crate::{BookKey, Entry, EntryDate, Id, hex, open_entry};

const BOOK_SECRET: [u8; KEY_LEN] = bytes_from(0x00);
const ENTRY_KEY: [u8; KEY_LEN] = bytes_from(0x20);
const ENTRY_KEY_NONCE: [u8; 24] = bytes_from(0x40);
const PAYLOAD_NONCE: [u8; 24] = bytes_from(0x60);
const BOOK_ID: Id = Id::from_bytes(bytes_from(0xb0));
const ENTRY_ID: Id = Id::from_bytes(bytes_from(0xe0));

/// `N` bytes counting up from `first`, so every input is easy to spot in a hex dump.
const fn bytes_from<const N: usize>(first: u8) -> [u8; N] {
    let mut bytes = [0u8; N];
    let mut i = 0;
    while i < N {
        bytes[i] = first + i as u8;
        i += 1;
    }
    bytes
}

struct SealCase {
    description: &'static str,
    book_key_version: u32,
    entry_date: &'static str,
    text: &'static str,
    created_at: i64,
    updated_at: i64,
}

const SEAL_CASES: [SealCase; 3] = [
    SealCase {
        description: "Text with a line break and an emoji, written in Jakarta",
        book_key_version: 1,
        entry_date: "2026-11-17T23:30:00+07:00",
        text: "Rain this afternoon.\nCoffee ☕ on the porch.",
        created_at: 1_794_933_000_000,
        updated_at: 1_794_933_660_000,
    },
    SealCase {
        description: "Empty text, a negative UTC offset, and Book key version 2",
        book_key_version: 2,
        entry_date: "2024-02-29T08:15:30-03:30",
        text: "",
        created_at: 1_709_207_130_000,
        updated_at: 1_709_207_130_000,
    },
    SealCase {
        description: "Times before and at the Unix epoch",
        book_key_version: 1,
        entry_date: "1969-12-31T00:00:00+00:00",
        text: "Before 1970.",
        created_at: -86_400_000,
        updated_at: 0,
    },
];

fn book_key(version: u32) -> BookKey {
    BookKey::new(BOOK_ID, version, BOOK_SECRET).unwrap()
}

fn entry(case: &SealCase) -> Entry {
    Entry {
        id: ENTRY_ID,
        book_id: BOOK_ID,
        date: EntryDate::parse(case.entry_date).unwrap(),
        text: case.text.to_owned(),
        created_at: case.created_at,
        updated_at: case.updated_at,
    }
}

fn seal(case: &SealCase) -> Vec<u8> {
    seal_entry_with(
        &entry(case),
        &book_key(case.book_key_version),
        &ENTRY_KEY,
        &ENTRY_KEY_NONCE,
        &PAYLOAD_NONCE,
    )
    .unwrap()
}

fn seal_vector(case: &SealCase) -> Value {
    let header = Header {
        entry_id: ENTRY_ID,
        book_id: BOOK_ID,
        book_key_version: case.book_key_version,
        entry_date: EntryDate::parse(case.entry_date).unwrap(),
    };
    let payload = Payload {
        text: case.text,
        created_at: case.created_at,
        updated_at: case.updated_at,
    };
    let blob = seal(case);

    // Opening the blob must give back exactly what was sealed.
    let opened = open_entry(&blob, ENTRY_ID, &book_key(case.book_key_version)).unwrap();
    assert_eq!(opened, entry(case), "{}", case.description);

    json!({
        "description": case.description,
        "kind": "seal",
        "inputs": {
            "book_id": BOOK_ID.to_hex(),
            "book_key": hex::encode(&BOOK_SECRET),
            "book_key_version": case.book_key_version,
            "entry_id": ENTRY_ID.to_hex(),
            "entry_date": case.entry_date,
            "text": case.text,
            "created_at": case.created_at,
            "updated_at": case.updated_at,
            "entry_key": hex::encode(&ENTRY_KEY),
            "entry_key_nonce": hex::encode(&ENTRY_KEY_NONCE),
            "payload_nonce": hex::encode(&PAYLOAD_NONCE),
        },
        "outputs": {
            "header": hex::encode(&header.encode()),
            "payload": hex::encode(&payload.encode()),
            "blob": hex::encode(&blob),
        },
    })
}

/// A blob that must fail to open, and the error it must fail with.
fn open_vector(
    description: &str,
    blob: &[u8],
    entry_id: Id,
    book_key_version: u32,
    error: &str,
) -> Value {
    let result = open_entry(blob, entry_id, &book_key(book_key_version));
    assert_eq!(result.map_err(|e| e.code()), Err(error), "{description}");

    json!({
        "description": description,
        "kind": "open",
        "inputs": {
            "blob": hex::encode(blob),
            "book_id": BOOK_ID.to_hex(),
            "book_key": hex::encode(&BOOK_SECRET),
            "book_key_version": book_key_version,
            "entry_id": entry_id.to_hex(),
        },
        "outputs": {
            "error": error,
        },
    })
}

/// `blob` with the first occurrence of `from` replaced by `to`.
fn replaced(blob: &[u8], from: &[u8], to: &[u8]) -> Vec<u8> {
    let at = blob
        .windows(from.len())
        .position(|w| w == from)
        .expect("the bytes to replace are in the blob");
    [&blob[..at], to, &blob[at + from.len()..]].concat()
}

fn open_vectors() -> Vec<Value> {
    let blob = seal(&SEAL_CASES[0]);
    let date = SEAL_CASES[0].entry_date.as_bytes();

    // Outer array, header array, format version, then the two IDs: 0x50 and 16 bytes each.
    const VERSION_AT: usize = 2;
    const KEY_VERSION_AT: usize = 3 + 2 * 17;
    assert_eq!(blob[VERSION_AT], 0x01);
    assert_eq!(blob[KEY_VERSION_AT], 0x01);

    let mut version_2 = blob.clone();
    version_2[VERSION_AT] = 0x02;
    let mut last_byte_changed = blob.clone();
    *last_byte_changed.last_mut().unwrap() ^= 0x01;
    let mut trailing_byte = blob.clone();
    trailing_byte.push(0x00);

    vec![
        open_vector(
            "The Entry date in the header changed by one day",
            &replaced(&blob, date, b"2026-11-18T23:30:00+07:00"),
            ENTRY_ID,
            1,
            "decryption-failed",
        ),
        open_vector(
            "One bit of the sealed payload changed",
            &last_byte_changed,
            ENTRY_ID,
            1,
            "decryption-failed",
        ),
        open_vector(
            "Opened as another Entry",
            &blob,
            Id::from_bytes(bytes_from(0xd0)),
            1,
            "wrong-entry",
        ),
        open_vector(
            "Opened with Book key version 2 of the same Book",
            &blob,
            ENTRY_ID,
            2,
            "wrong-key-version",
        ),
        open_vector(
            "Format version 2",
            &version_2,
            ENTRY_ID,
            1,
            "unsupported-version",
        ),
        open_vector(
            "Book key version 1 encoded in two bytes instead of one",
            &replaced(&blob, &[0x01, 0x78], &[0x18, 0x01, 0x78]),
            ENTRY_ID,
            1,
            "non-canonical",
        ),
        open_vector(
            "A UTC offset of +24:00",
            &replaced(&blob, date, b"2026-11-17T23:30:00+24:00"),
            ENTRY_ID,
            1,
            "invalid-entry-date",
        ),
        open_vector(
            "A byte after the blob",
            &trailing_byte,
            ENTRY_ID,
            1,
            "malformed",
        ),
    ]
}

fn vectors() -> Value {
    let mut vectors: Vec<Value> = SEAL_CASES.iter().map(seal_vector).collect();
    vectors.extend(open_vectors());
    Value::Array(vectors)
}

fn path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../spec/test-vectors/entry-format.json")
}

#[test]
fn entry_format_vectors_match_the_spec() {
    let vectors = vectors();
    if std::env::var_os("KRONOER_WRITE_VECTORS").is_some() {
        let text = serde_json::to_string_pretty(&vectors).unwrap() + "\n";
        std::fs::write(path(), text).unwrap();
        return;
    }

    let text = std::fs::read_to_string(path()).expect(
        "spec/test-vectors/entry-format.json exists; write it with KRONOER_WRITE_VECTORS=1",
    );
    let in_file: Value = serde_json::from_str(&text).unwrap();
    assert!(
        in_file == vectors,
        "spec/test-vectors/entry-format.json differs from what the core produces"
    );
}
