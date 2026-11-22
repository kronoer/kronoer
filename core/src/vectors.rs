//! Generates and checks `spec/test-vectors/entry-format.json`.
//!
//! The test fails if the file differs from what this crate produces. To write the file again after
//! a deliberate format change, run `KRONOER_WRITE_VECTORS=1 cargo test -p kronoer-core vectors`.

use std::borrow::Cow;
use std::path::PathBuf;

use serde_json::{Value, json};
use zeroize::Zeroizing;

use crate::book::{self, seal_book_record_with, wrap_book_key_with};
use crate::entry::{self, Header, Payload, seal_blob, seal_entry_with};
use crate::image::{self, SealedImage, seal_image_with};
use crate::keys::{KEY_LEN, Purpose};
use crate::star::{self, seal_star_record_with};
use crate::{
    BookKey, BookRecord, Entry, EntryDate, Id, ImageRef, ImageVariant, MasterKey, StarRecord, hex,
    open_book_record, open_entry, open_image, open_star_record, star_record_id, unwrap_book_key,
};

const MASTER_KEY: [u8; KEY_LEN] = bytes_from(0xf0);
const OTHER_MASTER_KEY: [u8; KEY_LEN] = bytes_from(0xf1);
const WRAP_NONCE: [u8; 24] = bytes_from(0x88);
const RECORD_NONCE: [u8; 24] = bytes_from(0xc8);
const OTHER_BOOK_ID: Id = Id::from_bytes(bytes_from(0x10));
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
        bytes[i] = first.wrapping_add(i as u8);
        i += 1;
    }
    bytes
}

struct ImageCase {
    description: &'static str,
    id: Id,
    key: [u8; KEY_LEN],
    full_nonce: [u8; 24],
    thumbnail_nonce: [u8; 24],
    full: &'static [u8],
    thumbnail: &'static [u8],
}

// The image bytes are stand-ins: the format seals whatever bytes it is given.
const IMAGE_CASES: [ImageCase; 2] = [
    ImageCase {
        description: "An Image with stand-in bytes for its full size and its thumbnail",
        id: Id::from_bytes(bytes_from(0xa0)),
        key: bytes_from(0x80),
        full_nonce: bytes_from(0x10),
        thumbnail_nonce: bytes_from(0x30),
        full: b"Full-size image bytes.",
        thumbnail: b"Thumbnail bytes.",
    },
    ImageCase {
        description: "An Image with an empty thumbnail",
        id: Id::from_bytes(bytes_from(0xc0)),
        key: bytes_from(0x90),
        full_nonce: bytes_from(0x50),
        thumbnail_nonce: bytes_from(0x70),
        full: b"Another image.",
        thumbnail: b"",
    },
];

struct SealCase {
    description: &'static str,
    book_key_version: u32,
    entry_date: &'static str,
    text: &'static str,
    /// Indexes into `IMAGE_CASES`.
    images: &'static [usize],
    created_at: i64,
    updated_at: i64,
}

const SEAL_CASES: [SealCase; 4] = [
    SealCase {
        description: "Text with a line break and an emoji, written in Jakarta",
        book_key_version: 1,
        entry_date: "2026-11-17T23:30:00+07:00",
        text: "Rain this afternoon.\nCoffee ☕ on the porch.",
        images: &[],
        created_at: 1_794_933_000_000,
        updated_at: 1_794_933_660_000,
    },
    SealCase {
        description: "Empty text, a negative UTC offset, and Book key version 2",
        book_key_version: 2,
        entry_date: "2024-02-29T08:15:30-03:30",
        text: "",
        images: &[],
        created_at: 1_709_207_130_000,
        updated_at: 1_709_207_130_000,
    },
    SealCase {
        description: "Times before and at the Unix epoch",
        book_key_version: 1,
        entry_date: "1969-12-31T00:00:00+00:00",
        text: "Before 1970.",
        images: &[],
        created_at: -86_400_000,
        updated_at: 0,
    },
    SealCase {
        description: "Two Images, the second listed first",
        book_key_version: 1,
        entry_date: "2026-11-18T07:05:00+07:00",
        text: "Two photos from the beach.",
        images: &[1, 0],
        created_at: 1_794_960_300_000,
        updated_at: 1_794_960_300_000,
    },
];

fn book_key(version: u32) -> BookKey {
    BookKey::new(BOOK_ID, version, BOOK_SECRET).unwrap()
}

fn seal_image(case: &ImageCase) -> SealedImage {
    seal_image_with(
        case.id,
        &case.key,
        &case.full_nonce,
        &case.thumbnail_nonce,
        case.full,
        case.thumbnail,
    )
}

fn image_ref(index: usize) -> ImageRef {
    seal_image(&IMAGE_CASES[index]).image
}

fn image_ref_json(image: &ImageRef) -> Value {
    json!({
        "image_id": image.id().to_hex(),
        "image_key": hex::encode(image.key()),
        "full_hash": hex::encode(image.hash(ImageVariant::Full)),
        "thumbnail_hash": hex::encode(image.hash(ImageVariant::Thumbnail)),
    })
}

fn variant_name(variant: ImageVariant) -> &'static str {
    match variant {
        ImageVariant::Full => "full",
        ImageVariant::Thumbnail => "thumbnail",
    }
}

fn seal_image_vector(case: &ImageCase) -> Value {
    let sealed = seal_image(case);

    // Opening each blob must give back exactly what was sealed.
    let opened_full = open_image(&sealed.full, &sealed.image, ImageVariant::Full).unwrap();
    let opened_thumbnail =
        open_image(&sealed.thumbnail, &sealed.image, ImageVariant::Thumbnail).unwrap();
    assert_eq!(opened_full, case.full, "{}", case.description);
    assert_eq!(opened_thumbnail, case.thumbnail, "{}", case.description);

    json!({
        "description": case.description,
        "kind": "seal-image",
        "inputs": {
            "image_id": case.id.to_hex(),
            "image_key": hex::encode(&case.key),
            "full_nonce": hex::encode(&case.full_nonce),
            "thumbnail_nonce": hex::encode(&case.thumbnail_nonce),
            "full": hex::encode(case.full),
            "thumbnail": hex::encode(case.thumbnail),
        },
        "outputs": {
            "header": hex::encode(&image::Header { image_id: case.id }.encode()),
            "full_blob": hex::encode(&sealed.full),
            "thumbnail_blob": hex::encode(&sealed.thumbnail),
            "full_hash": hex::encode(sealed.image.hash(ImageVariant::Full)),
            "thumbnail_hash": hex::encode(sealed.image.hash(ImageVariant::Thumbnail)),
        },
    })
}

/// An Image blob that must fail to open, and the error it must fail with.
fn open_image_vector(
    description: &str,
    blob: &[u8],
    image: &ImageRef,
    variant: ImageVariant,
    error: &str,
) -> Value {
    let result = open_image(blob, image, variant);
    assert_eq!(result.map_err(|e| e.code()), Err(error), "{description}");

    json!({
        "description": description,
        "kind": "open-image",
        "inputs": {
            "blob": hex::encode(blob),
            "variant": variant_name(variant),
            "image": image_ref_json(image),
        },
        "outputs": {
            "error": error,
        },
    })
}

/// `image` with the hash of one variant set to match `blob`. It stands for an Entry that pins a
/// bad blob, so a vector can reach the checks after the hash.
fn pinned(image: &ImageRef, variant: ImageVariant, blob: &[u8]) -> ImageRef {
    let mut full_hash = *image.hash(ImageVariant::Full);
    let mut thumbnail_hash = *image.hash(ImageVariant::Thumbnail);
    match variant {
        ImageVariant::Full => full_hash = image::hash(blob),
        ImageVariant::Thumbnail => thumbnail_hash = image::hash(blob),
    }
    ImageRef::new(image.id(), *image.key(), full_hash, thumbnail_hash)
}

fn open_image_vectors() -> Vec<Value> {
    use ImageVariant::{Full, Thumbnail};

    let sealed = seal_image(&IMAGE_CASES[0]);
    let image = &sealed.image;
    let full = &sealed.full;
    let id = IMAGE_CASES[0].id.as_bytes();

    // The outer array, the header array, then the format version.
    const VERSION_AT: usize = 2;
    assert_eq!(full[VERSION_AT], 0x01);

    let mut last_byte_changed = full.clone();
    *last_byte_changed.last_mut().unwrap() ^= 0x01;
    let mut version_2 = full.clone();
    version_2[VERSION_AT] = 0x02;
    let mut trailing_byte = full.clone();
    trailing_byte.push(0x00);
    let another_id = replaced(full, id, IMAGE_CASES[1].id.as_bytes());
    let long_id_length = replaced(
        full,
        &[&[0x50], &id[..]].concat(),
        &[&[0x58, 0x10], &id[..]].concat(),
    );
    let another_key = ImageRef::new(
        image.id(),
        IMAGE_CASES[1].key,
        *image.hash(Full),
        *image.hash(Thumbnail),
    );

    vec![
        open_image_vector(
            "The thumbnail blob opened as the full image",
            &sealed.thumbnail,
            image,
            Full,
            "hash-mismatch",
        ),
        open_image_vector(
            "Another Image's blob",
            &seal_image(&IMAGE_CASES[1]).full,
            image,
            Full,
            "hash-mismatch",
        ),
        open_image_vector(
            "One bit of the sealed image changed",
            &last_byte_changed,
            image,
            Full,
            "hash-mismatch",
        ),
        open_image_vector(
            "One bit of the sealed image changed, with a hash that matches",
            &last_byte_changed,
            &pinned(image, Full, &last_byte_changed),
            Full,
            "decryption-failed",
        ),
        open_image_vector(
            "The thumbnail blob opened as the full image, with a hash that matches",
            &sealed.thumbnail,
            &pinned(image, Full, &sealed.thumbnail),
            Full,
            "decryption-failed",
        ),
        open_image_vector(
            "Opened with another Image key",
            full,
            &another_key,
            Full,
            "decryption-failed",
        ),
        open_image_vector(
            "Another Image's ID in the header, with a hash that matches",
            &another_id,
            &pinned(image, Full, &another_id),
            Full,
            "wrong-image",
        ),
        open_image_vector(
            "Format version 2, with a hash that matches",
            &version_2,
            &pinned(image, Full, &version_2),
            Full,
            "unsupported-version",
        ),
        open_image_vector(
            "The Image ID's length encoded in two bytes instead of one, with a hash that matches",
            &long_id_length,
            &pinned(image, Full, &long_id_length),
            Full,
            "non-canonical",
        ),
        open_image_vector(
            "A byte after the blob, with a hash that matches",
            &trailing_byte,
            &pinned(image, Full, &trailing_byte),
            Full,
            "malformed",
        ),
    ]
}

fn entry(case: &SealCase) -> Entry {
    Entry {
        id: ENTRY_ID,
        book_id: BOOK_ID,
        date: EntryDate::parse(case.entry_date).unwrap(),
        text: case.text.to_owned(),
        images: case.images.iter().map(|&i| image_ref(i)).collect(),
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

fn header(case: &SealCase) -> Header {
    Header {
        entry_id: ENTRY_ID,
        book_id: BOOK_ID,
        book_key_version: case.book_key_version,
        entry_date: EntryDate::parse(case.entry_date).unwrap(),
    }
}

fn seal_entry_vector(case: &SealCase) -> Value {
    let entry = entry(case);
    let payload = Payload {
        text: case.text,
        images: Cow::Borrowed(&entry.images),
        created_at: case.created_at,
        updated_at: case.updated_at,
    };
    let blob = seal(case);

    // Opening the blob must give back exactly what was sealed.
    let opened = open_entry(&blob, ENTRY_ID, &book_key(case.book_key_version)).unwrap();
    assert_eq!(opened, entry, "{}", case.description);

    json!({
        "description": case.description,
        "kind": "seal-entry",
        "inputs": {
            "book_id": BOOK_ID.to_hex(),
            "book_key": hex::encode(&BOOK_SECRET),
            "book_key_version": case.book_key_version,
            "entry_id": ENTRY_ID.to_hex(),
            "entry_date": case.entry_date,
            "text": case.text,
            "images": entry.images.iter().map(image_ref_json).collect::<Vec<_>>(),
            "created_at": case.created_at,
            "updated_at": case.updated_at,
            "entry_key": hex::encode(&ENTRY_KEY),
            "entry_key_nonce": hex::encode(&ENTRY_KEY_NONCE),
            "payload_nonce": hex::encode(&PAYLOAD_NONCE),
        },
        "outputs": {
            "header": hex::encode(&header(case).encode()),
            "payload": hex::encode(&payload.encode()),
            "blob": hex::encode(&blob),
        },
    })
}

/// An Entry blob that must fail to open, and the error it must fail with.
fn open_entry_vector(
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
        "kind": "open-entry",
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

/// The blob of `case` with a payload a writer must never produce: the same Image listed twice.
fn same_image_twice(case: &SealCase) -> Vec<u8> {
    let images = [image_ref(0), image_ref(0)];
    let payload = Payload {
        text: case.text,
        images: Cow::Borrowed(&images),
        created_at: case.created_at,
        updated_at: case.updated_at,
    }
    .encode();
    seal_blob(
        header(case),
        &payload,
        &book_key(case.book_key_version),
        &ENTRY_KEY,
        &ENTRY_KEY_NONCE,
        &PAYLOAD_NONCE,
    )
}

fn open_entry_vectors() -> Vec<Value> {
    let blob = seal(&SEAL_CASES[0]);
    let date = SEAL_CASES[0].entry_date.as_bytes();

    // Outer array, header array, format version, then the two IDs: 0x50 and 16 bytes each.
    const VERSION_AT: usize = 2;
    const KEY_VERSION_AT: usize = 3 + 2 * 17;
    assert_eq!(blob[VERSION_AT], 0x01);
    assert_eq!(blob[KEY_VERSION_AT], 0x01);
    assert_eq!(u64::from(blob[VERSION_AT]), entry::FORMAT_VERSION);

    let mut version_2 = blob.clone();
    version_2[VERSION_AT] = 0x02;
    let mut last_byte_changed = blob.clone();
    *last_byte_changed.last_mut().unwrap() ^= 0x01;
    let mut trailing_byte = blob.clone();
    trailing_byte.push(0x00);

    vec![
        open_entry_vector(
            "The Entry date in the header changed by one day",
            &replaced(&blob, date, b"2026-11-18T23:30:00+07:00"),
            ENTRY_ID,
            1,
            "decryption-failed",
        ),
        open_entry_vector(
            "One bit of the sealed payload changed",
            &last_byte_changed,
            ENTRY_ID,
            1,
            "decryption-failed",
        ),
        open_entry_vector(
            "Opened as another Entry",
            &blob,
            Id::from_bytes(bytes_from(0xd0)),
            1,
            "wrong-entry",
        ),
        open_entry_vector(
            "Opened with Book key version 2 of the same Book",
            &blob,
            ENTRY_ID,
            2,
            "wrong-key-version",
        ),
        open_entry_vector(
            "Format version 2",
            &version_2,
            ENTRY_ID,
            1,
            "unsupported-version",
        ),
        open_entry_vector(
            "Book key version 1 encoded in two bytes instead of one",
            &replaced(&blob, &[0x01, 0x78], &[0x18, 0x01, 0x78]),
            ENTRY_ID,
            1,
            "non-canonical",
        ),
        open_entry_vector(
            "A UTC offset of +24:00",
            &replaced(&blob, date, b"2026-11-17T23:30:00+24:00"),
            ENTRY_ID,
            1,
            "invalid-entry-date",
        ),
        open_entry_vector(
            "A byte after the blob",
            &trailing_byte,
            ENTRY_ID,
            1,
            "malformed",
        ),
        open_entry_vector(
            "The same Image listed twice in the payload",
            &same_image_twice(&SEAL_CASES[3]),
            ENTRY_ID,
            1,
            "malformed",
        ),
    ]
}

fn master_key() -> MasterKey {
    MasterKey::from_secret(Zeroizing::new(MASTER_KEY))
}

fn derive_subkey_vector(description: &str, purpose: Purpose) -> Value {
    json!({
        "description": description,
        "kind": "derive-subkey",
        "inputs": {
            "master_key": hex::encode(&MASTER_KEY),
            "label": purpose.label(),
        },
        "outputs": {
            "subkey": hex::encode(master_key().subkey(purpose).as_slice()),
        },
    })
}

fn wrap(book_key_version: u32) -> Vec<u8> {
    wrap_book_key_with(&book_key(book_key_version), &master_key(), &WRAP_NONCE)
}

fn wrap_book_key_vector(description: &str, book_key_version: u32) -> Value {
    let wrapped = wrap(book_key_version);

    // Unwrapping must give back exactly the Book key that was wrapped.
    let unwrapped = unwrap_book_key(&wrapped, BOOK_ID, &master_key()).unwrap();
    assert_eq!(unwrapped.version(), book_key_version, "{description}");
    assert_eq!(unwrapped.secret(), &BOOK_SECRET, "{description}");

    json!({
        "description": description,
        "kind": "wrap-book-key",
        "inputs": {
            "master_key": hex::encode(&MASTER_KEY),
            "book_id": BOOK_ID.to_hex(),
            "book_key": hex::encode(&BOOK_SECRET),
            "book_key_version": book_key_version,
            "nonce": hex::encode(&WRAP_NONCE),
        },
        "outputs": {
            "header": hex::encode(&book::Header {
                book_id: BOOK_ID,
                book_key_version,
            }
            .encode()),
            "wrapped": hex::encode(&wrapped),
        },
    })
}

/// A wrapped Book key that must fail to unwrap, and the error it must fail with.
fn unwrap_book_key_vector(
    description: &str,
    wrapped: &[u8],
    book_id: Id,
    master: [u8; KEY_LEN],
    error: &str,
) -> Value {
    let result = unwrap_book_key(
        wrapped,
        book_id,
        &MasterKey::from_secret(Zeroizing::new(master)),
    );
    assert_eq!(
        result.map(|_| ()).map_err(|e| e.code()),
        Err(error),
        "{description}"
    );

    json!({
        "description": description,
        "kind": "unwrap-book-key",
        "inputs": {
            "wrapped": hex::encode(wrapped),
            "book_id": book_id.to_hex(),
            "master_key": hex::encode(&master),
        },
        "outputs": {
            "error": error,
        },
    })
}

fn unwrap_book_key_vectors() -> Vec<Value> {
    let wrapped = wrap(1);

    // Outer array, header array, format version, the Book ID (0x50 and 16 bytes), the key version.
    const VERSION_AT: usize = 2;
    const KEY_VERSION_AT: usize = 3 + 17;
    assert_eq!(wrapped[VERSION_AT], 0x01);
    assert_eq!(wrapped[KEY_VERSION_AT], 0x01);

    let mut version_2 = wrapped.clone();
    version_2[VERSION_AT] = 0x02;
    let mut key_version_2 = wrapped.clone();
    key_version_2[KEY_VERSION_AT] = 0x02;
    let mut last_byte_changed = wrapped.clone();
    *last_byte_changed.last_mut().unwrap() ^= 0x01;
    let mut trailing_byte = wrapped.clone();
    trailing_byte.push(0x00);
    let swapped = replaced(&wrapped, BOOK_ID.as_bytes(), OTHER_BOOK_ID.as_bytes());

    vec![
        unwrap_book_key_vector(
            "Unwrapped with another master key",
            &wrapped,
            BOOK_ID,
            OTHER_MASTER_KEY,
            "decryption-failed",
        ),
        unwrap_book_key_vector(
            "Unwrapped as another Book",
            &wrapped,
            OTHER_BOOK_ID,
            MASTER_KEY,
            "wrong-book",
        ),
        unwrap_book_key_vector(
            "Another Book's ID in the header, unwrapped as that Book",
            &swapped,
            OTHER_BOOK_ID,
            MASTER_KEY,
            "decryption-failed",
        ),
        unwrap_book_key_vector(
            "The Book key version in the header changed to 2",
            &key_version_2,
            BOOK_ID,
            MASTER_KEY,
            "decryption-failed",
        ),
        unwrap_book_key_vector(
            "One bit of the sealed Book key changed",
            &last_byte_changed,
            BOOK_ID,
            MASTER_KEY,
            "decryption-failed",
        ),
        unwrap_book_key_vector(
            "Format version 2",
            &version_2,
            BOOK_ID,
            MASTER_KEY,
            "unsupported-version",
        ),
        unwrap_book_key_vector(
            "Book key version 1 encoded in two bytes instead of one",
            &replaced(&wrapped, &[0x01, 0x58], &[0x18, 0x01, 0x58]),
            BOOK_ID,
            MASTER_KEY,
            "non-canonical",
        ),
        unwrap_book_key_vector(
            "A byte after the wrapped key",
            &trailing_byte,
            BOOK_ID,
            MASTER_KEY,
            "malformed",
        ),
    ]
}

struct RecordCase {
    description: &'static str,
    book_key_version: u32,
    name: &'static str,
    book_description: &'static str,
    /// An index into `IMAGE_CASES`, for the Cover.
    cover: Option<usize>,
}

const RECORD_CASES: [RecordCase; 4] = [
    RecordCase {
        description: "A Book name, without a Description or a Cover",
        book_key_version: 1,
        name: "Resep Keluarga",
        book_description: "",
        cover: None,
    },
    RecordCase {
        description: "A name with an emoji, a Description with a line break, and Book key version 2",
        book_key_version: 2,
        name: "Jurnal ☕",
        book_description: "Since moving to Yogyakarta.\nSmall things worth keeping.",
        cover: None,
    },
    RecordCase {
        description: "An empty name",
        book_key_version: 1,
        name: "",
        book_description: "",
        cover: None,
    },
    RecordCase {
        description: "A Book with a Description and a Cover",
        book_key_version: 1,
        name: "Travels",
        book_description: "Trips, one Entry a day.",
        cover: Some(0),
    },
];

fn record(case: &RecordCase) -> BookRecord {
    BookRecord {
        id: BOOK_ID,
        name: case.name.to_owned(),
        description: case.book_description.to_owned(),
        cover: case.cover.map(image_ref),
    }
}

fn seal_record(case: &RecordCase) -> Vec<u8> {
    seal_book_record_with(
        &record(case),
        &book_key(case.book_key_version),
        &RECORD_NONCE,
    )
    .unwrap()
}

fn seal_book_record_vector(case: &RecordCase) -> Value {
    let blob = seal_record(case);
    let record = record(case);

    // Opening the record must give back exactly what was sealed.
    let opened = open_book_record(&blob, &book_key(case.book_key_version)).unwrap();
    assert_eq!(opened, record, "{}", case.description);

    json!({
        "description": case.description,
        "kind": "seal-book-record",
        "inputs": {
            "book_id": BOOK_ID.to_hex(),
            "book_key": hex::encode(&BOOK_SECRET),
            "book_key_version": case.book_key_version,
            "name": case.name,
            "book_description": case.book_description,
            "cover": record.cover.as_ref().map_or(Value::Null, image_ref_json),
            "nonce": hex::encode(&RECORD_NONCE),
        },
        "outputs": {
            "header": hex::encode(&book::Header {
                book_id: BOOK_ID,
                book_key_version: case.book_key_version,
            }
            .encode()),
            "payload": hex::encode(&book::Payload::encode(
                case.name,
                case.book_description,
                record.cover.as_ref(),
            )),
            "blob": hex::encode(&blob),
        },
    })
}

/// A Book record that must fail to open, and the error it must fail with.
fn open_book_record_vector(
    description: &str,
    blob: &[u8],
    book_id: Id,
    book_key_version: u32,
    error: &str,
) -> Value {
    let key = BookKey::new(book_id, book_key_version, BOOK_SECRET).unwrap();
    let result = open_book_record(blob, &key);
    assert_eq!(
        result.map(|_| ()).map_err(|e| e.code()),
        Err(error),
        "{description}"
    );

    json!({
        "description": description,
        "kind": "open-book-record",
        "inputs": {
            "blob": hex::encode(blob),
            "book_id": book_id.to_hex(),
            "book_key": hex::encode(&BOOK_SECRET),
            "book_key_version": book_key_version,
        },
        "outputs": {
            "error": error,
        },
    })
}

fn open_book_record_vectors() -> Vec<Value> {
    let blob = seal_record(&RECORD_CASES[0]);

    const VERSION_AT: usize = 2;
    assert_eq!(blob[VERSION_AT], 0x01);

    let mut version_2 = blob.clone();
    version_2[VERSION_AT] = 0x02;
    let mut last_byte_changed = blob.clone();
    *last_byte_changed.last_mut().unwrap() ^= 0x01;
    let mut trailing_byte = blob.clone();
    trailing_byte.push(0x00);
    let swapped = replaced(&blob, BOOK_ID.as_bytes(), OTHER_BOOK_ID.as_bytes());

    vec![
        open_book_record_vector(
            "Opened with another Book's key",
            &blob,
            OTHER_BOOK_ID,
            1,
            "wrong-book",
        ),
        open_book_record_vector(
            "Another Book's ID in the header, opened with that Book's key",
            &swapped,
            OTHER_BOOK_ID,
            1,
            "decryption-failed",
        ),
        open_book_record_vector(
            "Opened with Book key version 2 of the same Book",
            &blob,
            BOOK_ID,
            2,
            "wrong-key-version",
        ),
        open_book_record_vector(
            "One bit of the sealed name changed",
            &last_byte_changed,
            BOOK_ID,
            1,
            "decryption-failed",
        ),
        open_book_record_vector(
            "A wrapped Book key opened as a Book record",
            &wrap(1),
            BOOK_ID,
            1,
            "decryption-failed",
        ),
        open_book_record_vector(
            "Format version 2",
            &version_2,
            BOOK_ID,
            1,
            "unsupported-version",
        ),
        open_book_record_vector(
            "A byte after the record",
            &trailing_byte,
            BOOK_ID,
            1,
            "malformed",
        ),
    ]
}

const STAR_NONCE: [u8; 24] = bytes_from(0x50);

struct StarCase {
    description: &'static str,
    starred_at: i64,
}

const STAR_CASES: [StarCase; 2] = [
    StarCase {
        description: "A Star record",
        starred_at: 1_795_105_800_000,
    },
    StarCase {
        description: "A Star record starred before 1970",
        starred_at: -1,
    },
];

fn star(case: &StarCase) -> StarRecord {
    StarRecord {
        entry_id: ENTRY_ID,
        book_id: BOOK_ID,
        starred_at: case.starred_at,
    }
}

fn star_record_id_vector() -> Value {
    json!({
        "description": "The record ID of the Star record for an Entry",
        "kind": "star-record-id",
        "inputs": {
            "master_key": hex::encode(&MASTER_KEY),
            "entry_id": ENTRY_ID.to_hex(),
        },
        "outputs": {
            "record_id": star_record_id(ENTRY_ID, &master_key()).to_hex(),
        },
    })
}

fn seal_star_record_vector(case: &StarCase) -> Value {
    let record = star(case);
    let blob = seal_star_record_with(&record, &master_key(), &STAR_NONCE);

    // Opening the record must give back exactly what was sealed.
    let opened = open_star_record(&blob, &master_key()).unwrap();
    assert_eq!(opened, record, "{}", case.description);

    json!({
        "description": case.description,
        "kind": "seal-star-record",
        "inputs": {
            "master_key": hex::encode(&MASTER_KEY),
            "entry_id": ENTRY_ID.to_hex(),
            "book_id": BOOK_ID.to_hex(),
            "starred_at": case.starred_at,
            "nonce": hex::encode(&STAR_NONCE),
        },
        "outputs": {
            "header": hex::encode(&star::encode_header(star_record_id(ENTRY_ID, &master_key()))),
            "payload": hex::encode(&star::encode_payload(&record)),
            "blob": hex::encode(&blob),
        },
    })
}

/// A Star record that must fail to open, and the error it must fail with.
fn open_star_record_vector(
    description: &str,
    blob: &[u8],
    master: [u8; KEY_LEN],
    error: &str,
) -> Value {
    let key = MasterKey::from_secret(Zeroizing::new(master));
    let result = open_star_record(blob, &key);
    assert_eq!(
        result.map(|_| ()).map_err(|e| e.code()),
        Err(error),
        "{description}"
    );

    json!({
        "description": description,
        "kind": "open-star-record",
        "inputs": {
            "blob": hex::encode(blob),
            "master_key": hex::encode(&master),
        },
        "outputs": {
            "error": error,
        },
    })
}

fn open_star_record_vectors() -> Vec<Value> {
    let record = star(&STAR_CASES[0]);
    let blob = seal_star_record_with(&record, &master_key(), &STAR_NONCE);

    const VERSION_AT: usize = 2;
    assert_eq!(blob[VERSION_AT], 0x01);

    let mut version_2 = blob.clone();
    version_2[VERSION_AT] = 0x02;
    let mut last_byte_changed = blob.clone();
    *last_byte_changed.last_mut().unwrap() ^= 0x01;
    let mut trailing_byte = blob.clone();
    trailing_byte.push(0x00);
    // Sealed under another Entry's record ID, so the tag verifies but the ID does not match.
    let other_record_id = star_record_id(Id::from_bytes(bytes_from(0xd0)), &master_key());
    let mismatched =
        star::seal_with_record_id(&record, other_record_id, &master_key(), &STAR_NONCE);

    vec![
        open_star_record_vector(
            "Opened with another master key",
            &blob,
            OTHER_MASTER_KEY,
            "decryption-failed",
        ),
        open_star_record_vector(
            "One bit of the sealed payload changed",
            &last_byte_changed,
            MASTER_KEY,
            "decryption-failed",
        ),
        open_star_record_vector(
            "A record ID that is not the one of the Entry inside",
            &mismatched,
            MASTER_KEY,
            "wrong-entry",
        ),
        open_star_record_vector(
            "Format version 2",
            &version_2,
            MASTER_KEY,
            "unsupported-version",
        ),
        open_star_record_vector(
            "A byte after the record",
            &trailing_byte,
            MASTER_KEY,
            "malformed",
        ),
    ]
}

fn vectors() -> Value {
    let mut vectors: Vec<Value> = SEAL_CASES.iter().map(seal_entry_vector).collect();
    vectors.extend(open_entry_vectors());
    vectors.extend(IMAGE_CASES.iter().map(seal_image_vector));
    vectors.extend(open_image_vectors());
    vectors.push(derive_subkey_vector(
        "The subkey that wraps Book keys",
        Purpose::BookKeyWrap,
    ));
    vectors.push(derive_subkey_vector(
        "The subkey that seals Star records",
        Purpose::StarRecord,
    ));
    vectors.push(derive_subkey_vector(
        "The subkey that makes Star record IDs",
        Purpose::StarId,
    ));
    vectors.push(wrap_book_key_vector("A Book key, version 1", 1));
    vectors.push(wrap_book_key_vector("A Book key, version 2", 2));
    vectors.extend(unwrap_book_key_vectors());
    vectors.extend(RECORD_CASES.iter().map(seal_book_record_vector));
    vectors.extend(open_book_record_vectors());
    vectors.push(star_record_id_vector());
    vectors.extend(STAR_CASES.iter().map(seal_star_record_vector));
    vectors.extend(open_star_record_vectors());
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
