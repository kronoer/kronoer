use std::fmt;

use crate::{Error, hex, random};

/// An identifier of an Entry, a Book, or an Image: 16 random bytes with no time or order in them.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Id([u8; Id::LEN]);

impl Id {
    /// The length of an ID in bytes.
    pub const LEN: usize = 16;

    /// Makes a new random ID.
    pub fn random() -> Result<Id, Error> {
        random::bytes().map(Id)
    }

    /// Wraps existing ID bytes.
    pub const fn from_bytes(bytes: [u8; Id::LEN]) -> Id {
        Id(bytes)
    }

    /// The ID's bytes.
    pub const fn as_bytes(&self) -> &[u8; Id::LEN] {
        &self.0
    }

    /// The text form: 32 lowercase hexadecimal digits.
    pub fn to_hex(&self) -> String {
        hex::encode(&self.0)
    }

    /// Reads the text form, rejecting anything but 32 lowercase hexadecimal digits.
    pub fn from_hex(text: &str) -> Result<Id, Error> {
        hex::decode(text)
            .and_then(|bytes| <[u8; Id::LEN]>::try_from(bytes).ok())
            .map(Id)
            .ok_or(Error::InvalidId)
    }
}

impl fmt::Debug for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Id({})", self.to_hex())
    }
}

impl fmt::Display for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.to_hex())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_form_round_trips() {
        let id = Id::random().unwrap();

        assert_eq!(id.to_hex().len(), 32);
        assert_eq!(Id::from_hex(&id.to_hex()), Ok(id));
    }

    #[test]
    fn random_ids_differ() {
        assert_ne!(Id::random().unwrap(), Id::random().unwrap());
    }

    #[test]
    fn rejects_wrong_text_forms() {
        assert_eq!(Id::from_hex(""), Err(Error::InvalidId));
        assert_eq!(Id::from_hex(&"0".repeat(30)), Err(Error::InvalidId));
        assert_eq!(Id::from_hex(&"A".repeat(32)), Err(Error::InvalidId));
    }
}
