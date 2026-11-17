use std::fmt;

use zeroize::Zeroizing;

use crate::{Error, Id, random};

/// The length of every symmetric key, in bytes.
pub(crate) const KEY_LEN: usize = 32;

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
        let secret = Zeroizing::new(secret);
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
}
