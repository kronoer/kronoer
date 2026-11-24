//! The Lock record of `spec/entry-format.md`: one per Locked Book, sealed with a subkey of the
//! master key, so it is the user's own and never shared, even when the Book is.
//!
//! Its readable header holds only a record ID computed from the Book ID with another subkey, so
//! the same lock made on two devices is the same record, while whoever holds the record cannot
//! tell which Book it points to. A lock is not encryption: the Book's Entries are sealed the same
//! whether it is locked or not.

use hmac::{Hmac, KeyInit, Mac};
use minicbor::Decoder;
use sha2::Sha256;

use crate::aead::{self, NONCE_LEN, TAG_LEN};
use crate::cbor::{self, WriteResult, Writer};
use crate::entry::FORMAT_VERSION;
use crate::keys::Purpose;
use crate::{Error, Id, MasterKey, random};

const LOCK_RECORD_CONTEXT: &str = "kronoer/v1/lock-record";

const HEADER_LEN: u64 = 2;
const RECORD_LEN: u64 = 3;
const PAYLOAD_LEN: u64 = 2;

/// What a Lock record holds, as it is before sealing and after opening.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct LockRecord {
    /// The Locked Book.
    pub book_id: Id,
    /// When the Book was locked, in milliseconds since the Unix epoch.
    pub locked_at: i64,
}

/// The record ID of the Lock record for a Book: the first 16 bytes of HMAC-SHA256 of the Book ID,
/// keyed with the master key's `kronoer/v1/lock-id` subkey.
pub fn lock_record_id(book_id: Id, master_key: &MasterKey) -> Id {
    let subkey = master_key.subkey(Purpose::LockId);
    let mut mac = <Hmac<Sha256> as KeyInit>::new_from_slice(subkey.as_slice())
        .expect("HMAC takes a key of any length");
    mac.update(book_id.as_bytes());
    let tag = mac.finalize().into_bytes();
    let mut id = [0u8; Id::LEN];
    id.copy_from_slice(&tag[..Id::LEN]);
    Id::from_bytes(id)
}

/// Seals a Lock record with the master key's `kronoer/v1/lock-record` subkey.
pub fn seal_lock_record(record: &LockRecord, master_key: &MasterKey) -> Result<Vec<u8>, Error> {
    let nonce = random::bytes::<NONCE_LEN>()?;
    Ok(seal_lock_record_with(record, master_key, &nonce))
}

/// Opens a Lock record.
///
/// Opening fails if the record was sealed with another master key, was changed in any way, or
/// its record ID is not the one of the Book it holds ([`Error::WrongBook`]).
pub fn open_lock_record(blob: &[u8], master_key: &MasterKey) -> Result<LockRecord, Error> {
    let sealed = Sealed::decode(blob)?;
    let payload = aead::open(
        &master_key.subkey(Purpose::LockRecord),
        &sealed.nonce,
        &sealed.sealed_payload,
        &aad(sealed.record_id),
    )?;
    let record = decode_payload(&payload)?;
    if lock_record_id(record.book_id, master_key) != sealed.record_id {
        return Err(Error::WrongBook);
    }
    Ok(record)
}

/// [`seal_lock_record`] with the nonce given, for test vectors.
pub(crate) fn seal_lock_record_with(
    record: &LockRecord,
    master_key: &MasterKey,
    nonce: &[u8; NONCE_LEN],
) -> Vec<u8> {
    seal_with_record_id(
        record,
        lock_record_id(record.book_id, master_key),
        master_key,
        nonce,
    )
}

/// Seals a Lock record under the record ID given, which a writer never chooses: only for tests of
/// records whose ID does not match their Book.
pub(crate) fn seal_with_record_id(
    record: &LockRecord,
    record_id: Id,
    master_key: &MasterKey,
    nonce: &[u8; NONCE_LEN],
) -> Vec<u8> {
    let payload = encode_payload(record);
    let sealed_payload = aead::seal(
        &master_key.subkey(Purpose::LockRecord),
        nonce,
        &payload,
        &aad(record_id),
    );
    Sealed {
        record_id,
        nonce: *nonce,
        sealed_payload,
    }
    .encode()
}

/// The encoded `lock-header`: `[format-version, record-id]`.
#[cfg(test)]
pub(crate) fn encode_header(record_id: Id) -> Vec<u8> {
    cbor::encode(|w| write_header(w, record_id))
}

/// The encoded `lock-payload`: `[book-id, locked-at]`.
pub(crate) fn encode_payload(record: &LockRecord) -> Vec<u8> {
    cbor::encode(|w| {
        w.array(PAYLOAD_LEN)?
            .bytes(record.book_id.as_bytes())?
            .i64(record.locked_at)?;
        Ok(())
    })
}

fn write_header(w: &mut Writer, record_id: Id) -> WriteResult {
    w.array(HEADER_LEN)?
        .u64(FORMAT_VERSION)?
        .bytes(record_id.as_bytes())?;
    Ok(())
}

/// The associated data: the encoding of `[context, header]`.
fn aad(record_id: Id) -> Vec<u8> {
    cbor::encode(|w| {
        w.array(2)?.str(LOCK_RECORD_CONTEXT)?;
        write_header(w, record_id)
    })
}

fn decode_payload(input: &[u8]) -> Result<LockRecord, Error> {
    let mut d = Decoder::new(input);
    cbor::array_of(&mut d, PAYLOAD_LEN)?;
    let book_id = Id::from_bytes(cbor::bytes_of(&mut d)?);
    let locked_at = cbor::int(&mut d)?;
    cbor::finish(&d, input)?;
    let record = LockRecord { book_id, locked_at };
    cbor::check_canonical(input, &encode_payload(&record))?;
    Ok(record)
}

struct Sealed {
    record_id: Id,
    nonce: [u8; NONCE_LEN],
    sealed_payload: Vec<u8>,
}

impl Sealed {
    fn encode(&self) -> Vec<u8> {
        cbor::encode(|w| {
            w.array(RECORD_LEN)?;
            write_header(w, self.record_id)?;
            w.bytes(&self.nonce)?.bytes(&self.sealed_payload)?;
            Ok(())
        })
    }

    /// Reads a Lock record, checking the format version before anything after it.
    fn decode(input: &[u8]) -> Result<Sealed, Error> {
        let mut d = Decoder::new(input);
        let len = cbor::array(&mut d)?;
        let header_len = cbor::array(&mut d)?;
        let version = cbor::uint(&mut d)?;
        if version != FORMAT_VERSION {
            return Err(Error::UnsupportedVersion(version));
        }
        if len != RECORD_LEN || header_len != HEADER_LEN {
            return Err(Error::Malformed);
        }
        let record_id = Id::from_bytes(cbor::bytes_of(&mut d)?);
        let nonce = cbor::bytes_of(&mut d)?;
        let sealed_payload = cbor::bytes(&mut d)?.to_vec();
        if sealed_payload.len() < TAG_LEN {
            return Err(Error::Malformed);
        }
        cbor::finish(&d, input)?;

        let sealed = Sealed {
            record_id,
            nonce,
            sealed_payload,
        };
        cbor::check_canonical(input, &sealed.encode())?;
        Ok(sealed)
    }
}

#[cfg(test)]
mod tests {
    use zeroize::Zeroizing;

    use super::*;
    use crate::keys::KEY_LEN;
    use crate::star::{StarRecord, seal_star_record, star_record_id};

    fn master(byte: u8) -> MasterKey {
        MasterKey::from_secret(Zeroizing::new([byte; KEY_LEN]))
    }

    fn record() -> LockRecord {
        LockRecord {
            book_id: Id::from_bytes([2; Id::LEN]),
            locked_at: 1_795_105_800_000,
        }
    }

    #[test]
    fn round_trips() {
        let master = master(7);
        let blob = seal_lock_record(&record(), &master).unwrap();
        assert_eq!(open_lock_record(&blob, &master), Ok(record()));
    }

    #[test]
    fn the_record_id_is_the_same_for_the_same_book_and_master_key() {
        let book = record().book_id;
        let other = Id::from_bytes([3; Id::LEN]);
        assert_eq!(
            lock_record_id(book, &master(7)),
            lock_record_id(book, &master(7))
        );
        assert_ne!(
            lock_record_id(book, &master(7)),
            lock_record_id(other, &master(7))
        );
        assert_ne!(
            lock_record_id(book, &master(7)),
            lock_record_id(book, &master(8))
        );
        // The ID hides the Book ID, and is not a Star record's ID for the same bytes.
        assert_ne!(lock_record_id(book, &master(7)), book);
        assert_ne!(
            lock_record_id(book, &master(7)),
            star_record_id(book, &master(7))
        );
    }

    #[test]
    fn two_seals_differ_but_share_the_record_id() {
        let master = master(7);
        let first = seal_lock_record(&record(), &master).unwrap();
        let second = seal_lock_record(&record(), &master).unwrap();
        assert_ne!(first, second);
        assert_eq!(
            Sealed::decode(&first).unwrap().record_id,
            Sealed::decode(&second).unwrap().record_id
        );
    }

    #[test]
    fn another_master_key_does_not_open_it() {
        let blob = seal_lock_record(&record(), &master(7)).unwrap();
        assert_eq!(
            open_lock_record(&blob, &master(8)),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn a_star_record_does_not_open_as_a_lock_record() {
        let master = master(7);
        let star = seal_star_record(
            &StarRecord {
                entry_id: Id::from_bytes([1; Id::LEN]),
                book_id: Id::from_bytes([2; Id::LEN]),
                starred_at: 0,
            },
            &master,
        )
        .unwrap();
        assert!(open_lock_record(&star, &master).is_err());
    }

    #[test]
    fn a_changed_record_id_does_not_open() {
        let master = master(7);
        let blob = seal_lock_record(&record(), &master).unwrap();
        let mut sealed = Sealed::decode(&blob).unwrap();
        sealed.record_id = Id::from_bytes([9; Id::LEN]);
        assert_eq!(
            open_lock_record(&sealed.encode(), &master),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn a_record_id_of_another_book_is_refused() {
        // Sealed under another Book's record ID, so the tag verifies.
        let master = master(7);
        let other = lock_record_id(Id::from_bytes([3; Id::LEN]), &master);
        let blob = seal_with_record_id(&record(), other, &master, &[5; NONCE_LEN]);
        assert_eq!(open_lock_record(&blob, &master), Err(Error::WrongBook));
    }

    #[test]
    fn refuses_other_versions_and_shapes() {
        let master = master(7);
        let blob = seal_lock_record(&record(), &master).unwrap();
        let mut newer = blob.clone();
        // [3-array, [2-array, version 1, ...: the version is the third byte.
        assert_eq!(&newer[..3], &[0x83, 0x82, 0x01]);
        newer[2] = 0x02;
        assert_eq!(
            open_lock_record(&newer, &master),
            Err(Error::UnsupportedVersion(2))
        );
        let mut longer = blob.clone();
        longer.push(0);
        assert_eq!(open_lock_record(&longer, &master), Err(Error::Malformed));
        assert_eq!(
            open_lock_record(&blob[..10], &master),
            Err(Error::Malformed)
        );
    }
}
