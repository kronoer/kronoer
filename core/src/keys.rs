use std::fmt;

use hkdf::Hkdf;
use sha2::Sha256;
use zeroize::Zeroizing;

use crate::{Error, Id, random};

/// The length of every symmetric key, in bytes.
pub(crate) const KEY_LEN: usize = 32;

/// What a subkey of the master key is for. Each purpose has its own HKDF label, so no two
/// purposes ever share a key.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Purpose {
    /// Wrapping the Book keys of personal Books.
    BookKeyWrap,
    /// Opening the local SQLCipher database.
    Sqlcipher,
    /// Sealing the user's Star records.
    StarRecord,
    /// Computing the record ID of a Star record from its Entry ID.
    StarId,
}

impl Purpose {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Purpose::BookKeyWrap => "kronoer/v1/book-key-wrap",
            Purpose::Sqlcipher => "kronoer/v1/sqlcipher",
            Purpose::StarRecord => "kronoer/v1/star-record",
            Purpose::StarId => "kronoer/v1/star-id",
        }
    }
}

/// The secret every other key on the device comes from, directly or through a Book key.
///
/// It never encrypts anything itself: each use gets its own subkey, derived with HKDF-SHA256. The
/// secret is wiped from memory when the key is dropped, and never shown by `Debug`.
pub struct MasterKey {
    secret: Zeroizing<[u8; KEY_LEN]>,
}

impl MasterKey {
    /// Makes a new random master key.
    pub fn generate() -> Result<MasterKey, Error> {
        Ok(MasterKey {
            secret: random::secret()?,
        })
    }

    /// Builds a master key from its bytes, as unwrapped from the platform's key store.
    ///
    /// The secret comes already wrapped in [`Zeroizing`], so no copy of it stays behind unwiped.
    pub fn from_secret(secret: Zeroizing<[u8; KEY_LEN]>) -> MasterKey {
        MasterKey { secret }
    }

    /// The subkey for one purpose: HKDF-SHA256 with an empty salt and the purpose's label.
    pub(crate) fn subkey(&self, purpose: Purpose) -> Zeroizing<[u8; KEY_LEN]> {
        let mut subkey = Zeroizing::new([0u8; KEY_LEN]);
        hkdf_sha256(
            self.secret.as_slice(),
            purpose.label().as_bytes(),
            subkey.as_mut(),
        );
        subkey
    }
}

impl fmt::Debug for MasterKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("MasterKey").finish_non_exhaustive()
    }
}

/// HKDF-SHA256 (RFC 5869) with an empty salt, filling `out`.
fn hkdf_sha256(input_key: &[u8], info: &[u8], out: &mut [u8]) {
    Hkdf::<Sha256>::new(Some(&[]), input_key)
        .expand(info, out)
        .expect("the output is at most 255 SHA-256 blocks");
}

/// The secret that opens one Book, with the Book it belongs to and its version.
///
/// The secret is wiped from memory when the key is dropped, and never shown by `Debug`.
pub struct BookKey {
    book_id: Id,
    version: u32,
    secret: Zeroizing<[u8; KEY_LEN]>,
}

impl BookKey {
    /// Makes a new random Book key, version 1, for a Book.
    pub fn generate(book_id: Id) -> Result<BookKey, Error> {
        Ok(BookKey {
            book_id,
            version: 1,
            secret: random::secret()?,
        })
    }

    /// Builds a Book key from its parts. Versions start at 1.
    pub fn new(book_id: Id, version: u32, secret: [u8; KEY_LEN]) -> Result<BookKey, Error> {
        BookKey::from_secret(book_id, version, Zeroizing::new(secret))
    }

    /// [`BookKey::new`] for a secret that is already wrapped in [`Zeroizing`], so no copy of it
    /// stays behind unwiped.
    pub(crate) fn from_secret(
        book_id: Id,
        version: u32,
        secret: Zeroizing<[u8; KEY_LEN]>,
    ) -> Result<BookKey, Error> {
        if version == 0 {
            return Err(Error::InvalidKeyVersion);
        }
        Ok(BookKey {
            book_id,
            version,
            secret,
        })
    }

    /// The Book this key opens.
    pub fn book_id(&self) -> Id {
        self.book_id
    }

    /// The version of this key.
    pub fn version(&self) -> u32 {
        self.version
    }

    pub(crate) fn secret(&self) -> &[u8; KEY_LEN] {
        &self.secret
    }
}

impl fmt::Debug for BookKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BookKey")
            .field("book_id", &self.book_id)
            .field("version", &self.version)
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_version_zero() {
        let book_id = Id::random().unwrap();

        assert_eq!(
            BookKey::new(book_id, 0, [7; KEY_LEN]).unwrap_err(),
            Error::InvalidKeyVersion
        );
    }

    #[test]
    fn debug_hides_the_secret() {
        let key = BookKey::new(Id::from_bytes([0; 16]), 3, [0xab; KEY_LEN]).unwrap();
        let shown = format!("{key:?}");

        assert!(shown.contains("version: 3"));
        assert!(!shown.contains("ab, ab") && !shown.contains("171"));
    }

    #[test]
    fn debug_hides_the_master_key() {
        let shown = format!(
            "{:?}",
            MasterKey::from_secret(Zeroizing::new([0xab; KEY_LEN]))
        );

        assert_eq!(shown, "MasterKey { .. }");
    }

    /// Test case 3 of RFC 5869, the one with an empty salt, so the derivation is the one the spec
    /// names.
    #[test]
    fn hkdf_matches_rfc_5869_with_an_empty_salt() {
        let mut out = [0u8; 42];
        hkdf_sha256(&[0x0b; 22], b"", &mut out);

        assert_eq!(
            crate::hex::encode(&out),
            concat!(
                "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d",
                "9d201395faa4b61a96c8",
            )
        );
    }

    #[test]
    fn subkeys_depend_on_the_master_key_and_never_equal_it() {
        let master = MasterKey::from_secret(Zeroizing::new([7; KEY_LEN]));
        let other = MasterKey::from_secret(Zeroizing::new([8; KEY_LEN]));
        let subkey = master.subkey(Purpose::BookKeyWrap);

        assert_eq!(*subkey, *master.subkey(Purpose::BookKeyWrap));
        assert_ne!(*subkey, *other.subkey(Purpose::BookKeyWrap));
        assert_ne!(*subkey, [7; KEY_LEN]);
    }

    #[test]
    fn generated_master_keys_differ() {
        let first = MasterKey::generate().unwrap();
        let second = MasterKey::generate().unwrap();

        assert_ne!(*first.secret, *second.secret);
    }
}
