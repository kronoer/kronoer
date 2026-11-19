use std::collections::HashMap;
use std::fmt;

use zeroize::Zeroizing;

use crate::keys::{KEY_LEN, Purpose};
use crate::{BookKey, Id, MasterKey};

/// The open keys of one device: the master key and every Book key unwrapped so far.
///
/// Keys never leave it in the clear, and are wiped from memory when it is dropped. `Debug` shows
/// only how many Book keys it holds.
pub struct Keyring {
    master: MasterKey,
    book_keys: HashMap<(Id, u32), BookKey>,
}

impl Keyring {
    /// A keyring holding only the master key.
    pub fn new(master: MasterKey) -> Keyring {
        Keyring {
            master,
            book_keys: HashMap::new(),
        }
    }

    pub(crate) fn master(&self) -> &MasterKey {
        &self.master
    }

    pub(crate) fn database_key(&self) -> Zeroizing<[u8; KEY_LEN]> {
        self.master.subkey(Purpose::Sqlcipher)
    }

    pub(crate) fn book_key(&self, book_id: Id, version: u32) -> Option<&BookKey> {
        self.book_keys.get(&(book_id, version))
    }

    pub(crate) fn insert(&mut self, key: BookKey) {
        self.book_keys.insert((key.book_id(), key.version()), key);
    }

    pub(crate) fn forget_book(&mut self, book_id: Id) {
        self.book_keys.retain(|(id, _), _| *id != book_id);
    }
}

impl fmt::Debug for Keyring {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Keyring")
            .field("book_keys", &self.book_keys.len())
            .finish_non_exhaustive()
    }
}
