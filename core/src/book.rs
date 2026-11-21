//! The wrapped Book key and the Book record of `spec/entry-format.md`.
//!
//! A personal Book's key is wrapped with a subkey of the master key, so it can be stored next to
//! the Book. The Book record holds the Book's name, Description, and Cover, sealed with the Book
//! key.

use minicbor::Decoder;
use minicbor::data::Type;
use zeroize::Zeroizing;

use crate::aead::{self, NONCE_LEN, TAG_LEN};
use crate::cbor::{self, WriteResult, Writer};
use crate::entry::FORMAT_VERSION;
use crate::keys::{KEY_LEN, Purpose};
use crate::{BookKey, Error, Id, ImageRef, MasterKey, random};

const BOOK_KEY_CONTEXT: &str = "kronoer/v1/book-key";
const BOOK_RECORD_CONTEXT: &str = "kronoer/v1/book-record";

const HEADER_LEN: u64 = 3;
const WRAPPED_KEY_LEN: u64 = 3;
const RECORD_LEN: u64 = 3;
const PAYLOAD_LEN: u64 = 3;
const SEALED_BOOK_KEY_LEN: usize = KEY_LEN + TAG_LEN;

/// What a Book is, as it is before sealing and after opening.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct BookRecord {
    /// The Book's ID.
    pub id: Id,
    /// The Book's name, as its owner wrote it.
    pub name: String,
    /// The Book's Description, as its owner wrote it. It may be empty.
    pub description: String,
    /// The Book's Cover, sealed like an Image, or `None` when it has none.
    pub cover: Option<ImageRef>,
}

/// Wraps a Book key with the master key, for storing next to its Book.
pub fn wrap_book_key(book_key: &BookKey, master_key: &MasterKey) -> Result<Vec<u8>, Error> {
    let nonce = random::bytes::<NONCE_LEN>()?;
    Ok(wrap_book_key_with(book_key, master_key, &nonce))
}

/// Unwraps a Book key.
///
/// `book_id` is the Book the wrapped key was stored or requested under. Unwrapping fails if the
/// wrapped key belongs to another Book, was wrapped with another master key, or was changed in any
/// way. The key's version comes from the wrapped key.
pub fn unwrap_book_key(
    wrapped: &[u8],
    book_id: Id,
    master_key: &MasterKey,
) -> Result<BookKey, Error> {
    let wrapped = WrappedKey::decode(wrapped)?;
    let header = &wrapped.header;
    if header.book_id != book_id {
        return Err(Error::WrongBook);
    }

    let plaintext = aead::open(
        &master_key.subkey(Purpose::BookKeyWrap),
        &wrapped.nonce,
        &wrapped.sealed_book_key,
        &header.aad(BOOK_KEY_CONTEXT),
    )?;
    if plaintext.len() != KEY_LEN {
        return Err(Error::Malformed);
    }
    let mut secret = Zeroizing::new([0u8; KEY_LEN]);
    secret.copy_from_slice(&plaintext);
    BookKey::from_secret(header.book_id, header.book_key_version, secret)
}

/// Seals a Book record with its Book's key.
///
/// Fails with [`Error::WrongBook`] if the record belongs to another Book.
pub fn seal_book_record(record: &BookRecord, book_key: &BookKey) -> Result<Vec<u8>, Error> {
    let nonce = random::bytes::<NONCE_LEN>()?;
    seal_book_record_with(record, book_key, &nonce)
}

/// Opens a Book record with its Book's key.
///
/// Opening fails if the record belongs to another Book, was sealed with another Book key version,
/// or was changed in any way.
pub fn open_book_record(blob: &[u8], book_key: &BookKey) -> Result<BookRecord, Error> {
    let record = Record::decode(blob)?;
    let header = &record.header;
    if header.book_id != book_key.book_id() {
        return Err(Error::WrongBook);
    }
    if header.book_key_version != book_key.version() {
        return Err(Error::WrongKeyVersion);
    }

    let payload = aead::open(
        book_key.secret(),
        &record.nonce,
        &record.sealed_payload,
        &header.aad(BOOK_RECORD_CONTEXT),
    )?;
    let payload = Payload::decode(&payload)?;
    Ok(BookRecord {
        id: header.book_id,
        name: payload.name.to_owned(),
        description: payload.description.to_owned(),
        cover: payload.cover,
    })
}

/// Opens a Book record written before Book records held a Description and a Cover, when the
/// payload was only `[name]`, and returns its name. Only the store's migration reads these.
pub(crate) fn open_book_record_name_only(blob: &[u8], book_key: &BookKey) -> Result<String, Error> {
    let record = Record::decode(blob)?;
    let header = &record.header;
    if header.book_id != book_key.book_id() {
        return Err(Error::WrongBook);
    }
    if header.book_key_version != book_key.version() {
        return Err(Error::WrongKeyVersion);
    }
    let payload = aead::open(
        book_key.secret(),
        &record.nonce,
        &record.sealed_payload,
        &header.aad(BOOK_RECORD_CONTEXT),
    )?;
    let mut d = Decoder::new(&payload);
    cbor::array_of(&mut d, 1)?;
    let name = cbor::text(&mut d)?;
    cbor::finish(&d, &payload)?;
    Ok(name.to_owned())
}

/// Seals a Book record the way it was before Book records held a Description and a Cover, for
/// tests of reading old records.
#[cfg(test)]
pub(crate) fn seal_name_only_book_record(name: &str, book_key: &BookKey) -> Vec<u8> {
    let payload = cbor::encode(|w| {
        w.array(1)?.str(name)?;
        Ok(())
    });
    let nonce = [3; NONCE_LEN];
    let header = Header::of(book_key);
    Record {
        sealed_payload: aead::seal(
            book_key.secret(),
            &nonce,
            &payload,
            &header.aad(BOOK_RECORD_CONTEXT),
        ),
        header,
        nonce,
    }
    .encode()
}

/// [`wrap_book_key`] with the nonce given, for test vectors.
pub(crate) fn wrap_book_key_with(
    book_key: &BookKey,
    master_key: &MasterKey,
    nonce: &[u8; NONCE_LEN],
) -> Vec<u8> {
    let header = Header::of(book_key);
    let sealed_book_key = aead::seal(
        &master_key.subkey(Purpose::BookKeyWrap),
        nonce,
        book_key.secret(),
        &header.aad(BOOK_KEY_CONTEXT),
    );

    WrappedKey {
        header,
        nonce: *nonce,
        sealed_book_key: sealed_book_key
            .try_into()
            .expect("a sealed key is the key plus a tag"),
    }
    .encode()
}

/// [`seal_book_record`] with the nonce given, for test vectors.
pub(crate) fn seal_book_record_with(
    record: &BookRecord,
    book_key: &BookKey,
    nonce: &[u8; NONCE_LEN],
) -> Result<Vec<u8>, Error> {
    if record.id != book_key.book_id() {
        return Err(Error::WrongBook);
    }
    let header = Header::of(book_key);
    let payload = Payload::encode(&record.name, &record.description, record.cover.as_ref());
    let sealed_payload = aead::seal(
        book_key.secret(),
        nonce,
        &payload,
        &header.aad(BOOK_RECORD_CONTEXT),
    );

    Ok(Record {
        header,
        nonce: *nonce,
        sealed_payload,
    }
    .encode())
}

/// The part of a wrapped Book key or a Book record that is not encrypted. It is authenticated as
/// associated data.
#[derive(Debug)]
pub(crate) struct Header {
    pub(crate) book_id: Id,
    pub(crate) book_key_version: u32,
}

impl Header {
    fn of(book_key: &BookKey) -> Header {
        Header {
            book_id: book_key.book_id(),
            book_key_version: book_key.version(),
        }
    }

    fn write(&self, w: &mut Writer) -> WriteResult {
        w.array(HEADER_LEN)?
            .u64(FORMAT_VERSION)?
            .bytes(self.book_id.as_bytes())?
            .u32(self.book_key_version)?;
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
        let book_id = Id::from_bytes(cbor::bytes_of(d)?);
        let book_key_version = u32::try_from(cbor::uint(d)?).map_err(|_| Error::Malformed)?;
        if book_key_version == 0 {
            return Err(Error::Malformed);
        }
        Ok(Header {
            book_id,
            book_key_version,
        })
    }

    /// The associated data for one context: the encoding of `[context, header]`.
    fn aad(&self, context: &str) -> Vec<u8> {
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

struct WrappedKey {
    header: Header,
    nonce: [u8; NONCE_LEN],
    sealed_book_key: [u8; SEALED_BOOK_KEY_LEN],
}

impl WrappedKey {
    fn encode(&self) -> Vec<u8> {
        cbor::encode(|w| {
            w.array(WRAPPED_KEY_LEN)?;
            self.header.write(w)?;
            w.bytes(&self.nonce)?.bytes(&self.sealed_book_key)?;
            Ok(())
        })
    }

    fn decode(input: &[u8]) -> Result<WrappedKey, Error> {
        let mut d = Decoder::new(input);
        let len = cbor::array(&mut d)?;
        let header = Header::read(&mut d)?;
        if len != WRAPPED_KEY_LEN {
            return Err(Error::Malformed);
        }
        let nonce = cbor::bytes_of(&mut d)?;
        let sealed_book_key = cbor::bytes_of(&mut d)?;
        cbor::finish(&d, input)?;

        let wrapped = WrappedKey {
            header,
            nonce,
            sealed_book_key,
        };
        cbor::check_canonical(input, &wrapped.encode())?;
        Ok(wrapped)
    }
}

struct Record {
    header: Header,
    nonce: [u8; NONCE_LEN],
    sealed_payload: Vec<u8>,
}

impl Record {
    fn encode(&self) -> Vec<u8> {
        cbor::encode(|w| {
            w.array(RECORD_LEN)?;
            self.header.write(w)?;
            w.bytes(&self.nonce)?.bytes(&self.sealed_payload)?;
            Ok(())
        })
    }

    fn decode(input: &[u8]) -> Result<Record, Error> {
        let mut d = Decoder::new(input);
        let len = cbor::array(&mut d)?;
        let header = Header::read(&mut d)?;
        if len != RECORD_LEN {
            return Err(Error::Malformed);
        }
        let nonce = cbor::bytes_of(&mut d)?;
        let sealed_payload = cbor::bytes(&mut d)?.to_vec();
        if sealed_payload.len() < TAG_LEN {
            return Err(Error::Malformed);
        }
        cbor::finish(&d, input)?;

        let record = Record {
            header,
            nonce,
            sealed_payload,
        };
        cbor::check_canonical(input, &record.encode())?;
        Ok(record)
    }
}

/// The encrypted part of a Book record: `[name, description, cover]`, where `cover` is an Image
/// reference or `null`.
#[derive(Debug)]
pub(crate) struct Payload<'a> {
    name: &'a str,
    description: &'a str,
    cover: Option<ImageRef>,
}

impl<'a> Payload<'a> {
    /// The encoded payload, wiped from memory when dropped.
    pub(crate) fn encode(
        name: &str,
        description: &str,
        cover: Option<&ImageRef>,
    ) -> Zeroizing<Vec<u8>> {
        Zeroizing::new(cbor::encode(|w| {
            w.array(PAYLOAD_LEN)?.str(name)?.str(description)?;
            match cover {
                Some(cover) => cover.write(w),
                None => {
                    w.null()?;
                    Ok(())
                }
            }
        }))
    }

    fn decode(input: &'a [u8]) -> Result<Payload<'a>, Error> {
        let mut d = Decoder::new(input);
        cbor::array_of(&mut d, PAYLOAD_LEN)?;
        let name = cbor::text(&mut d)?;
        let description = cbor::text(&mut d)?;
        let cover = match d.datatype().map_err(|_| Error::Malformed)? {
            Type::Null => {
                d.null().map_err(|_| Error::Malformed)?;
                None
            }
            _ => Some(ImageRef::read(&mut d)?),
        };
        cbor::finish(&d, input)?;
        cbor::check_canonical(input, &Payload::encode(name, description, cover.as_ref()))?;
        Ok(Payload {
            name,
            description,
            cover,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn master() -> MasterKey {
        MasterKey::from_secret(Zeroizing::new([7; KEY_LEN]))
    }

    fn book_key() -> BookKey {
        BookKey::generate(Id::random().unwrap()).unwrap()
    }

    fn record(book_key: &BookKey) -> BookRecord {
        BookRecord {
            id: book_key.book_id(),
            name: "Resep Keluarga".to_owned(),
            description: String::new(),
            cover: None,
        }
    }

    fn cover() -> ImageRef {
        ImageRef::new(Id::random().unwrap(), [5; KEY_LEN], [6; 32], [7; 32])
    }

    /// `blob` with the first occurrence of `from` replaced by `to`.
    fn replaced(blob: &[u8], from: &[u8], to: &[u8]) -> Vec<u8> {
        let at = blob
            .windows(from.len())
            .position(|w| w == from)
            .expect("the bytes to replace are in the blob");
        [&blob[..at], to, &blob[at + from.len()..]].concat()
    }

    #[test]
    fn book_keys_round_trip() {
        let key = BookKey::new(Id::random().unwrap(), 3, [9; KEY_LEN]).unwrap();
        let wrapped = wrap_book_key(&key, &master()).unwrap();
        let unwrapped = unwrap_book_key(&wrapped, key.book_id(), &master()).unwrap();

        assert_eq!(unwrapped.book_id(), key.book_id());
        assert_eq!(unwrapped.version(), 3);
        assert_eq!(unwrapped.secret(), key.secret());
    }

    #[test]
    fn a_wrapped_key_never_holds_the_secret_or_the_wrap_key() {
        let key = BookKey::new(Id::random().unwrap(), 1, [9; KEY_LEN]).unwrap();
        let wrapped = wrap_book_key(&key, &master()).unwrap();
        let wrap_key = master().subkey(Purpose::BookKeyWrap);

        assert!(!wrapped.windows(KEY_LEN).any(|w| w == key.secret()));
        assert!(!wrapped.windows(KEY_LEN).any(|w| w == wrap_key.as_slice()));
        assert!(!wrapped.windows(KEY_LEN).any(|w| w == [7; KEY_LEN]));
    }

    #[test]
    fn wrapping_twice_uses_a_new_nonce() {
        let key = book_key();

        assert_ne!(
            wrap_book_key(&key, &master()).unwrap(),
            wrap_book_key(&key, &master()).unwrap()
        );
    }

    #[test]
    fn unwrap_rejects_another_master_key() {
        let key = book_key();
        let wrapped = wrap_book_key(&key, &master()).unwrap();

        assert_eq!(
            unwrap_book_key(
                &wrapped,
                key.book_id(),
                &MasterKey::from_secret(Zeroizing::new([8; KEY_LEN]))
            )
            .unwrap_err(),
            Error::DecryptionFailed
        );
    }

    #[test]
    fn unwrap_rejects_another_books_key() {
        let key = book_key();
        let wrapped = wrap_book_key(&key, &master()).unwrap();

        assert_eq!(
            unwrap_book_key(&wrapped, Id::random().unwrap(), &master()).unwrap_err(),
            Error::WrongBook
        );
    }

    #[test]
    fn unwrap_rejects_a_swapped_book_id() {
        let key = book_key();
        let other = Id::random().unwrap();
        let wrapped = wrap_book_key(&key, &master()).unwrap();
        let swapped = replaced(&wrapped, key.book_id().as_bytes(), other.as_bytes());

        assert_eq!(
            unwrap_book_key(&swapped, other, &master()).unwrap_err(),
            Error::DecryptionFailed
        );
    }

    #[test]
    fn unwrap_rejects_any_changed_byte() {
        let key = book_key();
        let wrapped = wrap_book_key(&key, &master()).unwrap();

        for at in 0..wrapped.len() {
            let mut changed = wrapped.clone();
            changed[at] ^= 0x01;
            assert!(
                unwrap_book_key(&changed, key.book_id(), &master()).is_err(),
                "byte {at}"
            );
        }
    }

    #[test]
    fn records_round_trip() {
        let key = book_key();
        let record = record(&key);
        let blob = seal_book_record(&record, &key).unwrap();

        assert_eq!(open_book_record(&blob, &key).unwrap(), record);
    }

    #[test]
    fn records_round_trip_an_empty_name() {
        let key = book_key();
        let record = BookRecord {
            id: key.book_id(),
            name: String::new(),
            description: String::new(),
            cover: None,
        };
        let blob = seal_book_record(&record, &key).unwrap();

        assert_eq!(open_book_record(&blob, &key).unwrap(), record);
    }

    #[test]
    fn records_round_trip_a_description_and_a_cover() {
        let key = book_key();
        let record = BookRecord {
            description: "Masakan Nenek.\nDitulis ulang ☕".to_owned(),
            cover: Some(cover()),
            ..record(&key)
        };
        let blob = seal_book_record(&record, &key).unwrap();

        assert_eq!(open_book_record(&blob, &key).unwrap(), record);
    }

    #[test]
    fn a_record_hides_the_name_the_description_and_the_cover_key() {
        let key = book_key();
        let blob = seal_book_record(
            &BookRecord {
                description: "Masakan Nenek".to_owned(),
                cover: Some(cover()),
                ..record(&key)
            },
            &key,
        )
        .unwrap();

        assert!(!blob.windows(5).any(|w| w == b"Resep"));
        assert!(!blob.windows(7).any(|w| w == b"Masakan"));
        assert!(!blob.windows(KEY_LEN).any(|w| w == [5; KEY_LEN]));
    }

    #[test]
    fn opens_the_name_of_a_record_from_before_descriptions() {
        let key = book_key();
        let blob = seal_name_only_book_record("Buku Lama", &key);

        assert_eq!(
            open_book_record_name_only(&blob, &key).unwrap(),
            "Buku Lama"
        );
        assert_eq!(open_book_record(&blob, &key).unwrap_err(), Error::Malformed);
        assert_eq!(
            open_book_record_name_only(&blob, &book_key()).unwrap_err(),
            Error::WrongBook
        );
    }

    #[test]
    fn seal_rejects_a_record_of_another_book() {
        let key = book_key();
        let record = record(&book_key());

        assert_eq!(
            seal_book_record(&record, &key).unwrap_err(),
            Error::WrongBook
        );
    }

    #[test]
    fn open_rejects_another_books_key() {
        let key = book_key();
        let blob = seal_book_record(&record(&key), &key).unwrap();

        assert_eq!(
            open_book_record(&blob, &book_key()).unwrap_err(),
            Error::WrongBook
        );
    }

    #[test]
    fn open_rejects_another_key_version() {
        let key = book_key();
        let blob = seal_book_record(&record(&key), &key).unwrap();
        let version_2 = BookKey::new(key.book_id(), 2, *key.secret()).unwrap();

        assert_eq!(
            open_book_record(&blob, &version_2).unwrap_err(),
            Error::WrongKeyVersion
        );
    }

    #[test]
    fn open_rejects_the_right_book_with_the_wrong_secret() {
        let key = book_key();
        let blob = seal_book_record(&record(&key), &key).unwrap();
        let wrong = BookKey::new(key.book_id(), 1, [0; KEY_LEN]).unwrap();

        assert_eq!(
            open_book_record(&blob, &wrong).unwrap_err(),
            Error::DecryptionFailed
        );
    }

    #[test]
    fn open_rejects_any_changed_byte() {
        let key = book_key();
        let blob = seal_book_record(&record(&key), &key).unwrap();

        for at in 0..blob.len() {
            let mut changed = blob.clone();
            changed[at] ^= 0x01;
            assert!(open_book_record(&changed, &key).is_err(), "byte {at}");
        }
    }

    #[test]
    fn a_wrapped_key_never_opens_as_a_record() {
        let key = book_key();
        let wrapped = wrap_book_key(&key, &master()).unwrap();

        assert_eq!(
            open_book_record(&wrapped, &key).unwrap_err(),
            Error::DecryptionFailed
        );
    }

    #[test]
    fn rejects_other_format_versions() {
        let key = book_key();
        let mut blob = seal_book_record(&record(&key), &key).unwrap();
        let mut wrapped = wrap_book_key(&key, &master()).unwrap();
        // 0x83 (array of 3), 0x83 (header, array of 3), then the version.
        assert_eq!((blob[2], wrapped[2]), (0x01, 0x01));
        blob[2] = 0x02;
        wrapped[2] = 0x02;

        assert_eq!(
            open_book_record(&blob, &key).unwrap_err(),
            Error::UnsupportedVersion(2)
        );
        assert_eq!(
            unwrap_book_key(&wrapped, key.book_id(), &master()).unwrap_err(),
            Error::UnsupportedVersion(2)
        );
    }

    #[test]
    fn rejects_trailing_bytes() {
        let key = book_key();
        let mut blob = seal_book_record(&record(&key), &key).unwrap();
        let mut wrapped = wrap_book_key(&key, &master()).unwrap();
        blob.push(0);
        wrapped.push(0);

        assert_eq!(open_book_record(&blob, &key).unwrap_err(), Error::Malformed);
        assert_eq!(
            unwrap_book_key(&wrapped, key.book_id(), &master()).unwrap_err(),
            Error::Malformed
        );
    }

    #[test]
    fn payload_decoding_is_strict() {
        let encoded = Payload::encode("Buku", "", None);
        let decoded = Payload::decode(&encoded).unwrap();

        assert_eq!(&*encoded, &[0x83, 0x64, b'B', b'u', b'k', b'u', 0x60, 0xf6]);
        assert_eq!((decoded.name, decoded.description), ("Buku", ""));
        assert!(decoded.cover.is_none());

        let with_cover = Payload::encode("", "", Some(&cover()));
        assert!(Payload::decode(&with_cover).unwrap().cover.is_some());

        // The name's length in two bytes instead of one.
        assert_eq!(
            Payload::decode(&[0x83, 0x78, 0x04, b'B', b'u', b'k', b'u', 0x60, 0xf6]).unwrap_err(),
            Error::NonCanonical
        );
        // Only the name, as before Descriptions.
        assert_eq!(
            Payload::decode(&[0x81, 0x60]).unwrap_err(),
            Error::Malformed
        );
        // `undefined` instead of `null`, and a byte string instead of a Description.
        assert_eq!(
            Payload::decode(&[0x83, 0x60, 0x60, 0xf7]).unwrap_err(),
            Error::Malformed
        );
        assert_eq!(
            Payload::decode(&[0x83, 0x60, 0x40, 0xf6]).unwrap_err(),
            Error::Malformed
        );
        // A Cover reference with only three items.
        assert_eq!(
            Payload::decode(&[0x83, 0x60, 0x60, 0x83, 0x40, 0x40, 0x40]).unwrap_err(),
            Error::Malformed
        );
    }
}
