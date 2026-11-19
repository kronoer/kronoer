//! Kronoer core: all cryptography and the entry/Book format.
//!
//! The format is defined in `spec/entry-format.md`; this crate is its reference implementation.
//! Keys are wiped from memory when dropped and never leave this crate in the clear.

mod aead;
mod book;
mod cbor;
mod entry;
mod entry_date;
mod error;
mod hex;
mod id;
mod image;
mod keys;
mod random;
#[cfg(test)]
mod vectors;

pub use book::{BookRecord, open_book_record, seal_book_record, unwrap_book_key, wrap_book_key};
pub use entry::{Entry, FORMAT_VERSION, open_entry, seal_entry};
pub use entry_date::EntryDate;
pub use error::Error;
pub use id::Id;
pub use image::{ImageRef, ImageVariant, SealedImage, open_image, seal_image};
pub use keys::{BookKey, MasterKey};
/// Re-exported so callers wrap secrets in the same type the core keeps them in.
pub use zeroize::Zeroizing;

/// The version of this crate, as set in `Cargo.toml`.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_semver() {
        let parts: Vec<&str> = version().split(".").collect();

        assert_eq!(parts.len(), 3);
        assert!(parts.iter().all(|p| p.parse::<u32>().is_ok()));
    }
}
