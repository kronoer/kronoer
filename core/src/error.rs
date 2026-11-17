use std::fmt;

/// Why sealing or opening failed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// The input does not match the structure, or a field holds an invalid value.
    Malformed,
    /// The input is CBOR but not in deterministic form.
    NonCanonical,
    /// The data carries a format version this implementation does not read.
    UnsupportedVersion(u64),
    /// An Entry date is not in the form `YYYY-MM-DDTHH:MM:SS±HH:MM`, or names no real time.
    InvalidEntryDate,
    /// The text form of an ID is not 32 lowercase hexadecimal digits.
    InvalidId,
    /// A Book key version is 0; versions start at 1.
    InvalidKeyVersion,
    /// The header's Entry ID is not the expected one.
    WrongEntry,
    /// The Book ID is not the Book of the Book key.
    WrongBook,
    /// The header names a different Book key version than the key given.
    WrongKeyVersion,
    /// The tag did not verify: the data was changed, or the key is wrong. Decryption and
    /// verification are one step, so no plaintext is ever produced.
    DecryptionFailed,
    /// The operating system could not provide random bytes.
    RandomUnavailable,
}

impl Error {
    /// A short, stable code for the error, as used in `spec/test-vectors/`.
    pub fn code(&self) -> &'static str {
        match self {
            Error::Malformed => "malformed",
            Error::NonCanonical => "non-canonical",
            Error::UnsupportedVersion(_) => "unsupported-version",
            Error::InvalidEntryDate => "invalid-entry-date",
            Error::InvalidId => "invalid-id",
            Error::InvalidKeyVersion => "invalid-key-version",
            Error::WrongEntry => "wrong-entry",
            Error::WrongBook => "wrong-book",
            Error::WrongKeyVersion => "wrong-key-version",
            Error::DecryptionFailed => "decryption-failed",
            Error::RandomUnavailable => "random-unavailable",
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Malformed => f.write_str("the data does not match the format"),
            Error::NonCanonical => f.write_str("the data is not in deterministic CBOR"),
            Error::UnsupportedVersion(v) => write!(f, "format version {v} is not supported"),
            Error::InvalidEntryDate => f.write_str("the Entry date is not valid"),
            Error::InvalidId => f.write_str("the ID is not 32 lowercase hexadecimal digits"),
            Error::InvalidKeyVersion => f.write_str("Book key versions start at 1"),
            Error::WrongEntry => f.write_str("the blob belongs to a different Entry"),
            Error::WrongBook => f.write_str("the Entry belongs to a different Book"),
            Error::WrongKeyVersion => {
                f.write_str("the Entry was sealed with another Book key version")
            }
            Error::DecryptionFailed => {
                f.write_str("decryption failed: the data was changed or the key is wrong")
            }
            Error::RandomUnavailable => f.write_str("the system could not provide random bytes"),
        }
    }
}

impl std::error::Error for Error {}
