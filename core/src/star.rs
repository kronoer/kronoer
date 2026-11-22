//! The Star record of `spec/entry-format.md`: one per Starred Entry, sealed with a subkey of the
//! master key, so it is the user's own and never shared with a Book.
//!
//! Its readable header holds only a record ID computed from the Entry ID with another subkey, so
//! the same star made on two devices is the same record, while whoever holds the record cannot
//! tell which Entry it points to.

use hmac::{Hmac, KeyInit, Mac};
use minicbor::Decoder;
use sha2::Sha256;

use crate::aead::{self, NONCE_LEN, TAG_LEN};
use crate::cbor::{self, WriteResult, Writer};
use crate::entry::FORMAT_VERSION;
use crate::keys::Purpose;
use crate::{Error, Id, MasterKey, random};

const STAR_RECORD_CONTEXT: &str = "kronoer/v1/star-record";

const HEADER_LEN: u64 = 2;
const RECORD_LEN: u64 = 3;
const PAYLOAD_LEN: u64 = 3;

/// What a Star record holds, as it is before sealing and after opening.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct StarRecord {
    /// The Starred Entry.
    pub entry_id: Id,
    /// The Book the Entry is in.
    pub book_id: Id,
    /// When the Entry was starred, in milliseconds since the Unix epoch.
    pub starred_at: i64,
}

/// The record ID of the Star record for an Entry: the first 16 bytes of HMAC-SHA256 of the Entry
/// ID, keyed with the master key's `kronoer/v1/star-id` subkey.
pub fn star_record_id(entry_id: Id, master_key: &MasterKey) -> Id {
    let subkey = master_key.subkey(Purpose::StarId);
    let mut mac = <Hmac<Sha256> as KeyInit>::new_from_slice(subkey.as_slice())
        .expect("HMAC takes a key of any length");
    mac.update(entry_id.as_bytes());
    let tag = mac.finalize().into_bytes();
    let mut id = [0u8; Id::LEN];
    id.copy_from_slice(&tag[..Id::LEN]);
    Id::from_bytes(id)
}

/// Seals a Star record with the master key's `kronoer/v1/star-record` subkey.
pub fn seal_star_record(record: &StarRecord, master_key: &MasterKey) -> Result<Vec<u8>, Error> {
    let nonce = random::bytes::<NONCE_LEN>()?;
    Ok(seal_star_record_with(record, master_key, &nonce))
}

/// Opens a Star record.
///
/// Opening fails if the record was sealed with another master key, was changed in any way, or
/// its record ID is not the one of the Entry it holds ([`Error::WrongEntry`]).
pub fn open_star_record(blob: &[u8], master_key: &MasterKey) -> Result<StarRecord, Error> {
    let sealed = Sealed::decode(blob)?;
    let payload = aead::open(
        &master_key.subkey(Purpose::StarRecord),
        &sealed.nonce,
        &sealed.sealed_payload,
        &aad(sealed.record_id),
    )?;
    let record = decode_payload(&payload)?;
    if star_record_id(record.entry_id, master_key) != sealed.record_id {
        return Err(Error::WrongEntry);
    }
    Ok(record)
}

/// [`seal_star_record`] with the nonce given, for test vectors.
pub(crate) fn seal_star_record_with(
    record: &StarRecord,
    master_key: &MasterKey,
    nonce: &[u8; NONCE_LEN],
) -> Vec<u8> {
    seal_with_record_id(
        record,
        star_record_id(record.entry_id, master_key),
        master_key,
        nonce,
    )
}

/// Seals a Star record under the record ID given, which a writer never chooses: only for tests of
/// records whose ID does not match their Entry.
pub(crate) fn seal_with_record_id(
    record: &StarRecord,
    record_id: Id,
    master_key: &MasterKey,
    nonce: &[u8; NONCE_LEN],
) -> Vec<u8> {
    let payload = encode_payload(record);
    let sealed_payload = aead::seal(
        &master_key.subkey(Purpose::StarRecord),
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

/// The encoded `star-header`: `[format-version, record-id]`.
#[cfg(test)]
pub(crate) fn encode_header(record_id: Id) -> Vec<u8> {
    cbor::encode(|w| write_header(w, record_id))
}

/// The encoded `star-payload`: `[entry-id, book-id, starred-at]`.
pub(crate) fn encode_payload(record: &StarRecord) -> Vec<u8> {
    cbor::encode(|w| {
        w.array(PAYLOAD_LEN)?
            .bytes(record.entry_id.as_bytes())?
            .bytes(record.book_id.as_bytes())?
            .i64(record.starred_at)?;
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
        w.array(2)?.str(STAR_RECORD_CONTEXT)?;
        write_header(w, record_id)
    })
}

fn decode_payload(input: &[u8]) -> Result<StarRecord, Error> {
    let mut d = Decoder::new(input);
    cbor::array_of(&mut d, PAYLOAD_LEN)?;
    let entry_id = Id::from_bytes(cbor::bytes_of(&mut d)?);
    let book_id = Id::from_bytes(cbor::bytes_of(&mut d)?);
    let starred_at = cbor::int(&mut d)?;
    cbor::finish(&d, input)?;
    let record = StarRecord {
        entry_id,
        book_id,
        starred_at,
    };
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

    /// Reads a Star record, checking the format version before anything after it.
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

    fn master(byte: u8) -> MasterKey {
        MasterKey::from_secret(Zeroizing::new([byte; KEY_LEN]))
    }

    fn record() -> StarRecord {
        StarRecord {
            entry_id: Id::from_bytes([1; Id::LEN]),
            book_id: Id::from_bytes([2; Id::LEN]),
            starred_at: 1_795_105_800_000,
        }
    }

    #[test]
    fn round_trips() {
        let master = master(7);
        let blob = seal_star_record(&record(), &master).unwrap();
        assert_eq!(open_star_record(&blob, &master), Ok(record()));
    }

    #[test]
    fn the_record_id_is_the_same_for_the_same_entry_and_master_key() {
        let entry = record().entry_id;
        let other = Id::from_bytes([3; Id::LEN]);
        assert_eq!(
            star_record_id(entry, &master(7)),
            star_record_id(entry, &master(7))
        );
        assert_ne!(
            star_record_id(entry, &master(7)),
            star_record_id(other, &master(7))
        );
        assert_ne!(
            star_record_id(entry, &master(7)),
            star_record_id(entry, &master(8))
        );
        // The ID hides the Entry ID.
        assert_ne!(star_record_id(entry, &master(7)), entry);
    }

    #[test]
    fn two_seals_differ_but_share_the_record_id() {
        let master = master(7);
        let first = seal_star_record(&record(), &master).unwrap();
        let second = seal_star_record(&record(), &master).unwrap();
        assert_ne!(first, second);
        assert_eq!(
            Sealed::decode(&first).unwrap().record_id,
            Sealed::decode(&second).unwrap().record_id
        );
    }

    #[test]
    fn another_master_key_does_not_open_it() {
        let blob = seal_star_record(&record(), &master(7)).unwrap();
        assert_eq!(
            open_star_record(&blob, &master(8)),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn a_changed_record_id_does_not_open() {
        let master = master(7);
        let blob = seal_star_record(&record(), &master).unwrap();
        let mut sealed = Sealed::decode(&blob).unwrap();
        sealed.record_id = Id::from_bytes([9; Id::LEN]);
        assert_eq!(
            open_star_record(&sealed.encode(), &master),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn a_record_id_of_another_entry_is_refused() {
        // Sealed under another Entry's record ID, so the tag verifies.
        let master = master(7);
        let other = star_record_id(Id::from_bytes([3; Id::LEN]), &master);
        let blob = seal_with_record_id(&record(), other, &master, &[5; NONCE_LEN]);
        assert_eq!(open_star_record(&blob, &master), Err(Error::WrongEntry));
    }

    #[test]
    fn refuses_other_versions_and_shapes() {
        let master = master(7);
        let blob = seal_star_record(&record(), &master).unwrap();
        let mut newer = blob.clone();
        // [3-array, [2-array, version 1, ...: the version is the third byte.
        assert_eq!(&newer[..3], &[0x83, 0x82, 0x01]);
        newer[2] = 0x02;
        assert_eq!(
            open_star_record(&newer, &master),
            Err(Error::UnsupportedVersion(2))
        );
        let mut longer = blob.clone();
        longer.push(0);
        assert_eq!(open_star_record(&longer, &master), Err(Error::Malformed));
        assert_eq!(
            open_star_record(&blob[..10], &master),
            Err(Error::Malformed)
        );
    }
}
