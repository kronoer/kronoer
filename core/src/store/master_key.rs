//! Keeping the device's master key: wrapped by a platform key that never leaves the platform's
//! key store, in a small versioned file.
//!
//! The file holds the deterministic CBOR encoding of `[1, wrapped]`: the file format version, then
//! the master key as the platform wrapped it.

use std::fmt;
use std::fs;
use std::path::Path;

use minicbor::Decoder;
use zeroize::Zeroizing;

use super::files::write_atomically;
use super::{DATABASE_FILE, Keyring, Store, StoreError};
use crate::keys::KEY_LEN;
use crate::{MasterKey, cbor, random};

/// The version of the master key file this crate writes and reads.
const KEY_FILE_VERSION: u64 = 1;
const KEY_FILE_LEN: u64 = 2;

/// The length of a master key, in bytes.
pub const MASTER_KEY_LEN: usize = KEY_LEN;

/// A platform key store that wraps and unwraps the master key with a key that cannot be exported,
/// such as the Android Keystore.
pub trait MasterKeyStore {
    /// Wraps a new master key, creating the platform's wrapping key first if it does not exist.
    fn wrap(&self, master_key: &[u8; MASTER_KEY_LEN]) -> Result<Vec<u8>, PlatformKeyError>;

    /// Unwraps a master key that [`MasterKeyStore::wrap`] wrapped. Never creates a wrapping key:
    /// if there is none, the master key is lost and unwrapping fails.
    fn unwrap(&self, wrapped: &[u8]) -> Result<Zeroizing<[u8; MASTER_KEY_LEN]>, PlatformKeyError>;
}

/// Why the platform key store failed, as the platform described it.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct PlatformKeyError(pub String);

impl fmt::Display for PlatformKeyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for PlatformKeyError {}

/// Why the store could not be opened on the device.
#[derive(Debug)]
pub enum DeviceError {
    /// There is a database but no master key file: a new master key would not open it, so none is
    /// made. Nothing is changed.
    MasterKeyMissing,
    /// The master key file is there, but the platform could not unwrap it. Nothing is changed.
    CannotUnwrap(PlatformKeyError),
    /// The platform could not wrap a new master key. Nothing is written.
    CannotWrap(PlatformKeyError),
    /// The master key file is not one this crate reads.
    KeyFileDamaged,
    /// Reading or writing the master key file failed.
    Io(std::io::Error),
    /// The store did not open.
    Store(StoreError),
}

impl fmt::Display for DeviceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DeviceError::MasterKeyMissing => {
                f.write_str("the database exists but its master key file is gone")
            }
            DeviceError::CannotUnwrap(error) => write!(f, "cannot unwrap the master key: {error}"),
            DeviceError::CannotWrap(error) => write!(f, "cannot wrap a new master key: {error}"),
            DeviceError::KeyFileDamaged => f.write_str("the master key file is damaged"),
            DeviceError::Io(error) => write!(f, "master key file: {error}"),
            DeviceError::Store(error) => error.fmt(f),
        }
    }
}

impl std::error::Error for DeviceError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            DeviceError::CannotUnwrap(error) | DeviceError::CannotWrap(error) => Some(error),
            DeviceError::Io(error) => Some(error),
            DeviceError::Store(error) => Some(error),
            DeviceError::MasterKeyMissing | DeviceError::KeyFileDamaged => None,
        }
    }
}

impl From<StoreError> for DeviceError {
    fn from(error: StoreError) -> DeviceError {
        DeviceError::Store(error)
    }
}

impl From<std::io::Error> for DeviceError {
    fn from(error: std::io::Error) -> DeviceError {
        DeviceError::Io(error)
    }
}

impl From<crate::Error> for DeviceError {
    fn from(error: crate::Error) -> DeviceError {
        DeviceError::Store(error.into())
    }
}

impl Store {
    /// Opens the device's store in `dir`, with the master key kept in `key_file` and wrapped by
    /// `platform`.
    ///
    /// On first launch, when there is neither a key file nor a database, a new random master key
    /// is made, wrapped, and written to `key_file` before the store is created. A new master key
    /// is never made while the database exists: a missing key file is
    /// [`DeviceError::MasterKeyMissing`], and a key file the platform cannot unwrap is
    /// [`DeviceError::CannotUnwrap`]. Either way no file is changed. The master key goes straight
    /// into the store's [`Keyring`] and is never returned.
    pub fn open_on_device(
        dir: &Path,
        key_file: &Path,
        platform: &dyn MasterKeyStore,
    ) -> Result<Store, DeviceError> {
        let master_key = match fs::read(key_file) {
            Ok(contents) => {
                let wrapped = decode_key_file(&contents)?;
                let secret = platform
                    .unwrap(wrapped)
                    .map_err(DeviceError::CannotUnwrap)?;
                MasterKey::from_secret(secret)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                if dir.join(DATABASE_FILE).exists() {
                    return Err(DeviceError::MasterKeyMissing);
                }
                let secret = random::secret::<MASTER_KEY_LEN>()?;
                let wrapped = platform.wrap(&secret).map_err(DeviceError::CannotWrap)?;
                if let Some(parent) = key_file.parent() {
                    fs::create_dir_all(parent)?;
                }
                write_atomically(key_file, &encode_key_file(&wrapped))?;
                MasterKey::from_secret(secret)
            }
            Err(error) => return Err(error.into()),
        };
        Ok(Store::open(dir, Keyring::new(master_key))?)
    }
}

fn encode_key_file(wrapped: &[u8]) -> Vec<u8> {
    cbor::encode(|w| {
        w.array(KEY_FILE_LEN)?
            .u64(KEY_FILE_VERSION)?
            .bytes(wrapped)?;
        Ok(())
    })
}

fn decode_key_file(contents: &[u8]) -> Result<&[u8], DeviceError> {
    let mut d = Decoder::new(contents);
    let read = (|| {
        cbor::array_of(&mut d, KEY_FILE_LEN)?;
        if cbor::uint(&mut d)? != KEY_FILE_VERSION {
            return Err(crate::Error::Malformed);
        }
        let wrapped = cbor::bytes(&mut d)?;
        cbor::finish(&d, contents)?;
        Ok(wrapped)
    })();
    read.map_err(|_| DeviceError::KeyFileDamaged)
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;

    use tempfile::TempDir;

    use super::*;
    use crate::aead::{self, NONCE_LEN};

    const PLATFORM_KEY: [u8; KEY_LEN] = [3; KEY_LEN];
    const CONTEXT: &[u8] = b"fake platform";

    /// A platform key store that wraps with a fixed key, and can be told to fail.
    #[derive(Default)]
    struct FakePlatform {
        fail_unwrap: bool,
        fail_wrap: bool,
        wraps: Cell<u32>,
    }

    impl MasterKeyStore for FakePlatform {
        fn wrap(&self, master_key: &[u8; MASTER_KEY_LEN]) -> Result<Vec<u8>, PlatformKeyError> {
            if self.fail_wrap {
                return Err(PlatformKeyError("no key store".to_owned()));
            }
            self.wraps.set(self.wraps.get() + 1);
            let nonce = [self.wraps.get() as u8; NONCE_LEN];
            let mut wrapped = nonce.to_vec();
            wrapped.extend(aead::seal(&PLATFORM_KEY, &nonce, master_key, CONTEXT));
            Ok(wrapped)
        }

        fn unwrap(
            &self,
            wrapped: &[u8],
        ) -> Result<Zeroizing<[u8; MASTER_KEY_LEN]>, PlatformKeyError> {
            let error = || PlatformKeyError("cannot unwrap".to_owned());
            if self.fail_unwrap || wrapped.len() < NONCE_LEN {
                return Err(error());
            }
            let (nonce, sealed) = wrapped.split_at(NONCE_LEN);
            let plaintext = aead::open(&PLATFORM_KEY, nonce.try_into().unwrap(), sealed, CONTEXT)
                .map_err(|_| error())?;
            let mut secret = Zeroizing::new([0; MASTER_KEY_LEN]);
            secret.copy_from_slice(&plaintext);
            Ok(secret)
        }
    }

    struct Device {
        _root: TempDir,
        dir: std::path::PathBuf,
        key_file: std::path::PathBuf,
    }

    fn device() -> Device {
        let root = TempDir::new().unwrap();
        Device {
            dir: root.path().join("files").join("store"),
            key_file: root.path().join("no_backup").join("master-key"),
            _root: root,
        }
    }

    fn open(device: &Device, platform: &FakePlatform) -> Result<Store, DeviceError> {
        Store::open_on_device(&device.dir, &device.key_file, platform)
    }

    #[test]
    fn first_launch_makes_a_key_and_relaunch_opens_the_same_store() {
        let device = device();
        let platform = FakePlatform::default();
        let book = open(&device, &platform)
            .unwrap()
            .create_book("Kebun")
            .unwrap();
        assert_eq!(platform.wraps.get(), 1);

        let store = open(&device, &platform).unwrap();

        assert_eq!(store.get_book(book.id).unwrap().name, "Kebun");
        assert_eq!(platform.wraps.get(), 1);
    }

    #[test]
    fn the_key_file_is_versioned_and_holds_only_the_wrapped_key() {
        let device = device();
        let platform = FakePlatform::default();
        open(&device, &platform).unwrap();

        let contents = fs::read(&device.key_file).unwrap();
        let wrapped = decode_key_file(&contents).unwrap();
        assert_eq!(contents[..2], [0x82, 0x01]);
        assert_eq!(wrapped.len(), NONCE_LEN + MASTER_KEY_LEN + aead::TAG_LEN);
        assert!(!device.key_file.with_extension("tmp").exists());
    }

    #[test]
    fn a_missing_key_file_with_a_database_is_not_replaced() {
        let device = device();
        let platform = FakePlatform::default();
        open(&device, &platform)
            .unwrap()
            .create_book("Kebun")
            .unwrap();
        fs::remove_file(&device.key_file).unwrap();

        assert!(matches!(
            open(&device, &platform),
            Err(DeviceError::MasterKeyMissing)
        ));
        assert!(!device.key_file.exists());
        assert!(device.dir.join(DATABASE_FILE).exists());
        assert_eq!(platform.wraps.get(), 1);
    }

    #[test]
    fn a_key_that_does_not_unwrap_changes_nothing() {
        let device = device();
        open(&device, &FakePlatform::default())
            .unwrap()
            .create_book("Kebun")
            .unwrap();
        let key_file = fs::read(&device.key_file).unwrap();
        let failing = FakePlatform {
            fail_unwrap: true,
            ..FakePlatform::default()
        };

        assert!(matches!(
            open(&device, &failing),
            Err(DeviceError::CannotUnwrap(_))
        ));
        assert_eq!(fs::read(&device.key_file).unwrap(), key_file);
        assert_eq!(failing.wraps.get(), 0);
        let store = open(&device, &FakePlatform::default()).unwrap();
        assert_eq!(store.list_books().unwrap().len(), 1);
    }

    #[test]
    fn a_failed_wrap_writes_nothing() {
        let device = device();
        let failing = FakePlatform {
            fail_wrap: true,
            ..FakePlatform::default()
        };

        assert!(matches!(
            open(&device, &failing),
            Err(DeviceError::CannotWrap(_))
        ));
        assert!(!device.key_file.exists());
        assert!(!device.dir.exists());
    }

    #[test]
    fn a_damaged_or_newer_key_file_is_reported_and_kept() {
        let device = device();
        let platform = FakePlatform::default();
        open(&device, &platform).unwrap();
        let mut contents = fs::read(&device.key_file).unwrap();
        contents[1] = 0x02;
        fs::write(&device.key_file, &contents).unwrap();

        assert!(matches!(
            open(&device, &platform),
            Err(DeviceError::KeyFileDamaged)
        ));
        fs::write(&device.key_file, b"not cbor").unwrap();
        assert!(matches!(
            open(&device, &platform),
            Err(DeviceError::KeyFileDamaged)
        ));
        assert_eq!(fs::read(&device.key_file).unwrap(), b"not cbor");
    }
}
