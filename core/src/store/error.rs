use std::fmt;

use crate::Error;

/// Why a store operation failed.
#[derive(Debug)]
pub enum StoreError {
    /// A blob, wrapped key, or record failed to seal or open: it was changed, swapped, or sealed
    /// with another key.
    Format(Error),
    /// No Book, Entry, or Image has the given ID.
    NotFound,
    /// The request cannot be done as asked, for the reason given.
    Invalid(&'static str),
    /// Pinning would make more than [`super::MAX_PINNED_BOOKS`] Pinned Books.
    TooManyPinned,
    /// An Entry refers to an Image whose file is gone.
    ImageMissing,
    /// The database does not open with this device's key: the key is not the one it was created
    /// with, or the file is not a database.
    WrongKey,
    /// The database was written by a newer version of the app, with this schema version.
    NewerSchema(u32),
    /// The database failed.
    Database(rusqlite::Error),
    /// Reading or writing an image file failed.
    Io(std::io::Error),
}

impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StoreError::Format(error) => error.fmt(f),
            StoreError::NotFound => f.write_str("no such Book, Entry, or Image"),
            StoreError::Invalid(reason) => f.write_str(reason),
            StoreError::TooManyPinned => {
                write!(f, "at most {} Books can be pinned", super::MAX_PINNED_BOOKS)
            }
            StoreError::ImageMissing => f.write_str("the Image's file is missing"),
            StoreError::WrongKey => f.write_str("the database does not open with this key"),
            StoreError::NewerSchema(version) => {
                write!(f, "the database has newer schema version {version}")
            }
            StoreError::Database(error) => write!(f, "database: {error}"),
            StoreError::Io(error) => write!(f, "image files: {error}"),
        }
    }
}

impl std::error::Error for StoreError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            StoreError::Format(error) => Some(error),
            StoreError::NotFound
            | StoreError::Invalid(_)
            | StoreError::TooManyPinned
            | StoreError::ImageMissing
            | StoreError::WrongKey
            | StoreError::NewerSchema(_) => None,
            StoreError::Database(error) => Some(error),
            StoreError::Io(error) => Some(error),
        }
    }
}

impl From<Error> for StoreError {
    fn from(error: Error) -> StoreError {
        StoreError::Format(error)
    }
}

impl From<rusqlite::Error> for StoreError {
    fn from(error: rusqlite::Error) -> StoreError {
        match error {
            rusqlite::Error::QueryReturnedNoRows => StoreError::NotFound,
            error => StoreError::Database(error),
        }
    }
}

impl From<std::io::Error> for StoreError {
    fn from(error: std::io::Error) -> StoreError {
        StoreError::Io(error)
    }
}
