//! The Entry blob of `spec/entry-format.md`: sealing an Entry with a Book key and opening it again.

use std::borrow::Cow;

use minicbor::Decoder;
use zeroize::Zeroizing;

use crate::aead::{self, NONCE_LEN, TAG_LEN};
use crate::cbor::{self, WriteResult, Writer};
use crate::keys::KEY_LEN;
use crate::{BookKey, EntryDate, Error, Id, ImageRef, random};

/// The version of the data this crate writes and reads.
pub const FORMAT_VERSION: u64 = 1;

const ENTRY_KEY_CONTEXT: &str = "kronoer/v1/entry-key";
const ENTRY_PAYLOAD_CONTEXT: &str = "kronoer/v1/entry-payload";

const BLOB_LEN: u64 = 5;
const HEADER_LEN: u64 = 5;
const PAYLOAD_LEN: u64 = 4;
const SEALED_ENTRY_KEY_LEN: usize = KEY_LEN + TAG_LEN;

/// One piece of writing in a Book, as it is before sealing and after opening.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Entry {
    /// The Entry's ID.
    pub id: Id,
    /// The Book the Entry belongs to.
    pub book_id: Id,
    /// The date and time the Entry is about.
    pub date: EntryDate,
    /// The Entry's plain text, which may be empty.
    pub text: String,
    /// The Images attached to the Entry, in the order they are shown. No Image appears twice.
    pub images: Vec<ImageRef>,
    /// When the Entry was first written, in milliseconds since the Unix epoch.
    pub created_at: i64,
    /// When the Entry was last changed, in milliseconds since the Unix epoch.
    pub updated_at: i64,
}

/// Seals an Entry with its Book's key, using a new random Entry key.
///
/// Fails with [`Error::WrongBook`] if the Entry belongs to another Book, and with
/// [`Error::Malformed`] if it lists the same Image twice.
pub fn seal_entry(entry: &Entry, book_key: &BookKey) -> Result<Vec<u8>, Error> {
    let entry_key = random::secret::<KEY_LEN>()?;
    let entry_key_nonce = random::bytes::<NONCE_LEN>()?;
    let payload_nonce = random::bytes::<NONCE_LEN>()?;
    seal_entry_with(
        entry,
        book_key,
        &entry_key,
        &entry_key_nonce,
        &payload_nonce,
    )
}

/// Opens an Entry blob.
///
/// `entry_id` is the ID the blob was stored or requested under. Opening fails if the blob belongs
/// to another Entry or Book, was sealed with another Book key version, or was changed in any way.
pub fn open_entry(blob: &[u8], entry_id: Id, book_key: &BookKey) -> Result<Entry, Error> {
    let blob = Blob::decode(blob)?;
    let header = &blob.header;
    if header.entry_id != entry_id {
        return Err(Error::WrongEntry);
    }
    if header.book_id != book_key.book_id() {
        return Err(Error::WrongBook);
    }
    if header.book_key_version != book_key.version() {
        return Err(Error::WrongKeyVersion);
    }

    let entry_key = aead::open(
        book_key.secret(),
        &blob.entry_key_nonce,
        &blob.sealed_entry_key,
        &header.aad(ENTRY_KEY_CONTEXT),
    )?;
    let entry_key: &[u8; KEY_LEN] = entry_key
        .as_slice()
        .try_into()
        .map_err(|_| Error::Malformed)?;
    let payload = aead::open(
        entry_key,
        &blob.payload_nonce,
        &blob.sealed_payload,
        &header.aad(ENTRY_PAYLOAD_CONTEXT),
    )?;
    let payload = Payload::decode(&payload)?;

    Ok(Entry {
        id: header.entry_id,
        book_id: header.book_id,
        date: blob.header.entry_date,
        text: payload.text.to_owned(),
        images: payload.images.into_owned(),
        created_at: payload.created_at,
        updated_at: payload.updated_at,
    })
}

/// [`seal_entry`] with the random values given, for test vectors.
pub(crate) fn seal_entry_with(
    entry: &Entry,
    book_key: &BookKey,
    entry_key: &[u8; KEY_LEN],
    entry_key_nonce: &[u8; NONCE_LEN],
    payload_nonce: &[u8; NONCE_LEN],
) -> Result<Vec<u8>, Error> {
    if entry.book_id != book_key.book_id() {
        return Err(Error::WrongBook);
    }
    if has_duplicate_image(&entry.images) {
        return Err(Error::Malformed);
    }
    let header = Header {
        entry_id: entry.id,
        book_id: entry.book_id,
        book_key_version: book_key.version(),
        entry_date: entry.date.clone(),
    };
    let payload = Payload {
        text: &entry.text,
        images: Cow::Borrowed(&entry.images),
        created_at: entry.created_at,
        updated_at: entry.updated_at,
    }
    .encode();

    Ok(seal_blob(
        header,
        &payload,
        book_key,
        entry_key,
        entry_key_nonce,
        payload_nonce,
    ))
}

/// Seals an encoded payload under `header`, without checking the payload. Test vectors use it to
/// build blobs a writer must never produce.
pub(crate) fn seal_blob(
    header: Header,
    payload: &[u8],
    book_key: &BookKey,
    entry_key: &[u8; KEY_LEN],
    entry_key_nonce: &[u8; NONCE_LEN],
    payload_nonce: &[u8; NONCE_LEN],
) -> Vec<u8> {
    let sealed_entry_key = aead::seal(
        book_key.secret(),
        entry_key_nonce,
        entry_key,
        &header.aad(ENTRY_KEY_CONTEXT),
    );
    let sealed_payload = aead::seal(
        entry_key,
        payload_nonce,
        payload,
        &header.aad(ENTRY_PAYLOAD_CONTEXT),
    );

    Blob {
        header,
        entry_key_nonce: *entry_key_nonce,
        sealed_entry_key: sealed_entry_key
            .try_into()
            .expect("a sealed key is the key plus a tag"),
        payload_nonce: *payload_nonce,
        sealed_payload,
    }
    .encode()
}

fn has_duplicate_image(images: &[ImageRef]) -> bool {
    images
        .iter()
        .enumerate()
        .any(|(i, image)| images[..i].iter().any(|other| other.id() == image.id()))
}

/// The part of the blob that is not encrypted. It is authenticated as associated data.
#[derive(Debug)]
pub(crate) struct Header {
    pub(crate) entry_id: Id,
    pub(crate) book_id: Id,
    pub(crate) book_key_version: u32,
    pub(crate) entry_date: EntryDate,
}

impl Header {
    fn write(&self, w: &mut Writer) -> WriteResult {
        w.array(HEADER_LEN)?
            .u64(FORMAT_VERSION)?
            .bytes(self.entry_id.as_bytes())?
            .bytes(self.book_id.as_bytes())?
            .u32(self.book_key_version)?
            .str(self.entry_date.as_str())?;
        Ok(())
    }

    /// Reads a header, checking the format version before anything after it.
    fn read(d: &mut Decoder<'_>) -> Result<Header, Error> {
        let len = cbor::array(d)?;
        let version = cbor::uint(d)?;
        if version != FORMAT_VERSION {
            return Err(Error::UnsupportedVersion(version));
        }
        if len != HEADER_LEN {
            return Err(Error::Malformed);
        }
        let entry_id = Id::from_bytes(cbor::bytes_of(d)?);
        let book_id = Id::from_bytes(cbor::bytes_of(d)?);
        let book_key_version = u32::try_from(cbor::uint(d)?).map_err(|_| Error::Malformed)?;
        if book_key_version == 0 {
            return Err(Error::Malformed);
        }
        let entry_date = EntryDate::parse(cbor::text(d)?)?;
        Ok(Header {
            entry_id,
            book_id,
            book_key_version,
            entry_date,
        })
    }

    /// The associated data for one context: the encoding of `[context, header]`.
    pub(crate) fn aad(&self, context: &str) -> Vec<u8> {
        cbor::encode(|w| {
            w.array(2)?.str(context)?;
            self.write(w)
        })
    }

    #[cfg(test)]
    pub(crate) fn encode(&self) -> Vec<u8> {
        cbor::encode(|w| self.write(w))
    }
}

struct Blob {
    header: Header,
    entry_key_nonce: [u8; NONCE_LEN],
    sealed_entry_key: [u8; SEALED_ENTRY_KEY_LEN],
    payload_nonce: [u8; NONCE_LEN],
    sealed_payload: Vec<u8>,
}

impl Blob {
    fn encode(&self) -> Vec<u8> {
        cbor::encode(|w| {
            w.array(BLOB_LEN)?;
            self.header.write(w)?;
            w.bytes(&self.entry_key_nonce)?
                .bytes(&self.sealed_entry_key)?
                .bytes(&self.payload_nonce)?
                .bytes(&self.sealed_payload)?;
            Ok(())
        })
    }

    fn decode(input: &[u8]) -> Result<Blob, Error> {
        let mut d = Decoder::new(input);
        let len = cbor::array(&mut d)?;
        let header = Header::read(&mut d)?;
        if len != BLOB_LEN {
            return Err(Error::Malformed);
        }
        let entry_key_nonce = cbor::bytes_of(&mut d)?;
        let sealed_entry_key = cbor::bytes_of(&mut d)?;
        let payload_nonce = cbor::bytes_of(&mut d)?;
        let sealed_payload = cbor::bytes(&mut d)?.to_vec();
        if sealed_payload.len() < TAG_LEN {
            return Err(Error::Malformed);
        }
        cbor::finish(&d, input)?;

        let blob = Blob {
            header,
            entry_key_nonce,
            sealed_entry_key,
            payload_nonce,
            sealed_payload,
        };
        cbor::check_canonical(input, &blob.encode())?;
        Ok(blob)
    }
}

/// The encrypted part of the blob.
pub(crate) struct Payload<'a> {
    pub(crate) text: &'a str,
    pub(crate) images: Cow<'a, [ImageRef]>,
    pub(crate) created_at: i64,
    pub(crate) updated_at: i64,
}

impl<'a> Payload<'a> {
    /// The encoded payload, wiped from memory when dropped. It holds the Image keys.
    pub(crate) fn encode(&self) -> Zeroizing<Vec<u8>> {
        Zeroizing::new(cbor::encode(|w| {
            w.array(PAYLOAD_LEN)?
                .str(self.text)?
                .array(self.images.len() as u64)?;
            for image in self.images.iter() {
                image.write(w)?;
            }
            w.i64(self.created_at)?.i64(self.updated_at)?;
            Ok(())
        }))
    }

    fn decode(input: &'a [u8]) -> Result<Payload<'a>, Error> {
        let mut d = Decoder::new(input);
        cbor::array_of(&mut d, PAYLOAD_LEN)?;
        let text = cbor::text(&mut d)?;
        let mut images = Vec::new();
        for _ in 0..cbor::array(&mut d)? {
            images.push(ImageRef::read(&mut d)?);
        }
        if has_duplicate_image(&images) {
            return Err(Error::Malformed);
        }
        let created_at = cbor::int(&mut d)?;
        let updated_at = cbor::int(&mut d)?;
        cbor::finish(&d, input)?;

        let payload = Payload {
            text,
            images: Cow::Owned(images),
            created_at,
            updated_at,
        };
        cbor::check_canonical(input, &payload.encode())?;
        Ok(payload)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn book_key() -> BookKey {
        BookKey::generate(Id::random().unwrap()).unwrap()
    }

    fn entry(book_key: &BookKey) -> Entry {
        Entry {
            id: Id::random().unwrap(),
            book_id: book_key.book_id(),
            date: EntryDate::parse("2026-11-17T23:30:00+07:00").unwrap(),
            text: "Rain this afternoon.\nCoffee ☕ on the porch.".to_owned(),
            images: Vec::new(),
            created_at: 1_795_105_800_000,
            updated_at: 1_795_105_860_000,
        }
    }

    #[test]
    fn round_trips() {
        let key = book_key();
        let entry = entry(&key);
        let blob = seal_entry(&entry, &key).unwrap();

        assert_eq!(open_entry(&blob, entry.id, &key).unwrap(), entry);
    }

    #[test]
    fn round_trips_empty_text_and_extreme_times() {
        let key = book_key();
        let entry = Entry {
            text: String::new(),
            created_at: i64::MIN,
            updated_at: i64::MAX,
            ..entry(&key)
        };
        let blob = seal_entry(&entry, &key).unwrap();

        assert_eq!(open_entry(&blob, entry.id, &key).unwrap(), entry);
    }

    #[test]
    fn round_trips_images_in_order() {
        let key = book_key();
        let images: Vec<ImageRef> = (0..3)
            .map(|_| crate::seal_image(b"full", b"thumbnail").unwrap().image)
            .collect();
        let entry = Entry {
            images: images.clone(),
            ..entry(&key)
        };
        let blob = seal_entry(&entry, &key).unwrap();
        let opened = open_entry(&blob, entry.id, &key).unwrap();

        assert_eq!(opened.images, images);
    }

    #[test]
    fn keeps_image_references_when_sealed_again() {
        let key = book_key();
        let image = crate::seal_image(b"full", b"thumbnail").unwrap().image;
        let entry = Entry {
            images: vec![image.clone()],
            ..entry(&key)
        };
        let first = open_entry(&seal_entry(&entry, &key).unwrap(), entry.id, &key).unwrap();
        let edited = Entry {
            text: "Edited.".to_owned(),
            ..first
        };
        let second = open_entry(&seal_entry(&edited, &key).unwrap(), entry.id, &key).unwrap();

        assert_eq!(second.images, vec![image]);
    }

    #[test]
    fn refuses_to_seal_the_same_image_twice() {
        let key = book_key();
        let image = crate::seal_image(b"full", b"thumbnail").unwrap().image;
        let entry = Entry {
            images: vec![image.clone(), image],
            ..entry(&key)
        };

        assert_eq!(seal_entry(&entry, &key), Err(Error::Malformed));
    }

    #[test]
    fn rejects_a_payload_with_the_same_image_twice() {
        let image = crate::seal_image(b"full", b"thumbnail").unwrap().image;
        let images = [image.clone(), image];
        let payload = Payload {
            text: "",
            images: Cow::Borrowed(&images),
            created_at: 0,
            updated_at: 0,
        }
        .encode();

        assert!(matches!(Payload::decode(&payload), Err(Error::Malformed)));
    }

    #[test]
    fn every_seal_uses_a_new_entry_key_and_nonces() {
        let key = book_key();
        let entry = entry(&key);
        let first = Blob::decode(&seal_entry(&entry, &key).unwrap()).unwrap();
        let second = Blob::decode(&seal_entry(&entry, &key).unwrap()).unwrap();

        assert_ne!(first.entry_key_nonce, second.entry_key_nonce);
        assert_ne!(first.payload_nonce, second.payload_nonce);
        assert_ne!(first.sealed_entry_key, second.sealed_entry_key);
        assert_ne!(first.sealed_payload, second.sealed_payload);
    }

    #[test]
    fn refuses_to_seal_into_another_book() {
        let key = book_key();
        let other = book_key();

        assert_eq!(seal_entry(&entry(&other), &key), Err(Error::WrongBook));
    }

    #[test]
    fn rejects_another_entry_id() {
        let key = book_key();
        let entry = entry(&key);
        let blob = seal_entry(&entry, &key).unwrap();

        assert_eq!(
            open_entry(&blob, Id::random().unwrap(), &key),
            Err(Error::WrongEntry)
        );
    }

    #[test]
    fn rejects_another_books_key() {
        let key = book_key();
        let entry = entry(&key);
        let blob = seal_entry(&entry, &key).unwrap();

        assert_eq!(
            open_entry(&blob, entry.id, &book_key()),
            Err(Error::WrongBook)
        );
    }

    #[test]
    fn rejects_another_key_version() {
        let secret = [9; KEY_LEN];
        let book_id = Id::random().unwrap();
        let v1 = BookKey::new(book_id, 1, secret).unwrap();
        let v2 = BookKey::new(book_id, 2, secret).unwrap();
        let entry = entry(&v1);
        let blob = seal_entry(&entry, &v1).unwrap();

        assert_eq!(
            open_entry(&blob, entry.id, &v2),
            Err(Error::WrongKeyVersion)
        );
    }

    #[test]
    fn rejects_the_right_ids_with_the_wrong_secret() {
        let key = book_key();
        let entry = entry(&key);
        let blob = seal_entry(&entry, &key).unwrap();
        let impostor = BookKey::new(key.book_id(), key.version(), [0; KEY_LEN]).unwrap();

        assert_eq!(
            open_entry(&blob, entry.id, &impostor),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn rejects_any_changed_byte() {
        let key = book_key();
        let entry = entry(&key);
        let blob = seal_entry(&entry, &key).unwrap();

        for at in 0..blob.len() {
            let mut changed = blob.clone();
            changed[at] ^= 0x01;
            assert!(open_entry(&changed, entry.id, &key).is_err(), "byte {at}");
        }
    }

    #[test]
    fn rejects_a_header_with_a_changed_entry_date() {
        let key = book_key();
        let entry = entry(&key);
        let mut blob = Blob::decode(&seal_entry(&entry, &key).unwrap()).unwrap();
        blob.header.entry_date = EntryDate::parse("2026-11-18T23:30:00+07:00").unwrap();

        assert_eq!(
            open_entry(&blob.encode(), entry.id, &key),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn rejects_a_sealed_entry_key_moved_into_the_payload() {
        let key = book_key();
        let entry = entry(&key);
        let mut blob = Blob::decode(&seal_entry(&entry, &key).unwrap()).unwrap();
        blob.sealed_payload = blob.sealed_entry_key.to_vec();
        blob.payload_nonce = blob.entry_key_nonce;

        assert_eq!(
            open_entry(&blob.encode(), entry.id, &key),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn rejects_other_format_versions_first() {
        let key = book_key();
        let entry = entry(&key);
        let mut blob = seal_entry(&entry, &key).unwrap();
        // The header starts at byte 1: 0x85 (array of 5), then the version.
        assert_eq!(blob[2], 0x01);
        blob[2] = 0x02;

        assert_eq!(
            open_entry(&blob, Id::random().unwrap(), &key),
            Err(Error::UnsupportedVersion(2))
        );
    }

    #[test]
    fn rejects_trailing_bytes() {
        let key = book_key();
        let entry = entry(&key);
        let mut blob = seal_entry(&entry, &key).unwrap();
        blob.push(0x00);

        assert_eq!(open_entry(&blob, entry.id, &key), Err(Error::Malformed));
    }
}
