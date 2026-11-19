//! The Android side of the device: where its files live, and the Android Keystore key that wraps
//! the master key.
//!
//! Kotlin loads this library and calls `KronoerCore.init` once when the process starts, before
//! Dart runs. The master key passes through the JVM only as the input and output of the Keystore
//! cipher; those arrays are zeroed right after use, and the key never reaches Dart.

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use jni::objects::{JByteArray, JObject, JString, JValue};
use jni::{JNIEnv, JavaVM};
use kronoer_core::store::{MasterKeyStore, PlatformKeyError, MASTER_KEY_LEN};
use kronoer_core::Zeroizing;

const KEYSTORE: &str = "AndroidKeyStore";
/// The Keystore alias of the wrapping key. A new wrapping scheme gets a new alias.
const ALIAS: &str = "kronoer-master-key-wrap-v1";
const TRANSFORMATION: &str = "AES/GCM/NoPadding";
/// Associated data for the wrap, so the Keystore output is only ever read as a master key.
const AAD: &[u8] = b"kronoer/v1/master-key-wrap";
const IV_LEN: usize = 12;
const TAG_BITS: i32 = 128;
const ENCRYPT_MODE: i32 = 1;
const DECRYPT_MODE: i32 = 2;
const PURPOSE_ENCRYPT: i32 = 1;
const PURPOSE_DECRYPT: i32 = 2;

const BUILDER: &str = "android/security/keystore/KeyGenParameterSpec$Builder";
const BUILDER_RETURN_STRINGS: &str =
    "([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;";

/// What `KronoerCore.init` gave: the JVM, and the app's directories.
pub(crate) struct Device {
    vm: JavaVM,
    files_dir: PathBuf,
    no_backup_dir: PathBuf,
}

impl Device {
    /// The app's private files directory, which holds the store.
    pub(crate) fn files_dir(&self) -> &Path {
        &self.files_dir
    }

    /// The app's directory that is never backed up, which holds the master key file.
    pub(crate) fn no_backup_dir(&self) -> &Path {
        &self.no_backup_dir
    }
}

static DEVICE: OnceLock<Device> = OnceLock::new();

/// The device, once Kotlin has called `KronoerCore.init`.
pub(crate) fn device() -> Option<&'static Device> {
    DEVICE.get()
}

/// `app.kronoer.KronoerCore.init(filesDir: String, noBackupDir: String)`.
#[unsafe(no_mangle)]
pub extern "system" fn Java_app_kronoer_KronoerCore_init<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    files_dir: JString<'local>,
    no_backup_dir: JString<'local>,
) {
    let device = (|| -> jni::errors::Result<Device> {
        Ok(Device {
            vm: env.get_java_vm()?,
            files_dir: PathBuf::from(String::from(env.get_string(&files_dir)?)),
            no_backup_dir: PathBuf::from(String::from(env.get_string(&no_backup_dir)?)),
        })
    })();
    match device {
        Ok(device) => {
            let _ = DEVICE.set(device);
        }
        Err(error) => {
            let _ = env.throw_new("java/lang/IllegalStateException", error.to_string());
        }
    }
}

/// The Android Keystore, wrapping the master key with an AES-256-GCM key that cannot leave it.
///
/// The wrapping key has no conditions at all: no user authentication, and no unlocked-device
/// requirement, so changing or removing the lock screen never deletes or invalidates it.
pub(crate) struct AndroidKeystore;

impl MasterKeyStore for AndroidKeystore {
    fn wrap(&self, master_key: &[u8; MASTER_KEY_LEN]) -> Result<Vec<u8>, PlatformKeyError> {
        with_env(|env| {
            let key = match wrapping_key(env)? {
                Some(key) => key,
                None => {
                    generate_wrapping_key(env)?;
                    wrapping_key(env)?.ok_or_else(|| {
                        Failure::from("the new wrapping key is not in the Keystore")
                    })?
                }
            };
            let cipher = cipher(env)?;
            env.call_method(
                &cipher,
                "init",
                "(ILjava/security/Key;)V",
                &[JValue::Int(ENCRYPT_MODE), JValue::Object(&key)],
            )?;
            update_aad(env, &cipher)?;
            let iv: JByteArray = env.call_method(&cipher, "getIV", "()[B", &[])?.l()?.into();
            let iv = env.convert_byte_array(&iv)?;
            if iv.len() != IV_LEN {
                return Err(Failure::from(
                    "the Keystore chose an IV of an unexpected length",
                ));
            }

            let input = env.byte_array_from_slice(master_key.as_slice())?;
            let sealed = env.call_method(&cipher, "doFinal", "([B)[B", &[JValue::Object(&input)]);
            // JNI allows no array writes while an exception is pending, so read it out first.
            let sealed = sealed.map_err(|error| Failure::Other(describe(env, error)));
            env.set_byte_array_region(&input, 0, &[0; MASTER_KEY_LEN])?;
            let sealed: JByteArray = sealed?.l()?.into();
            let sealed = env.convert_byte_array(&sealed)?;
            Ok([iv, sealed].concat())
        })
    }

    fn unwrap(&self, wrapped: &[u8]) -> Result<Zeroizing<[u8; MASTER_KEY_LEN]>, PlatformKeyError> {
        if wrapped.len() <= IV_LEN {
            return Err(PlatformKeyError(
                "the wrapped master key is too short".to_owned(),
            ));
        }
        let (iv, sealed) = wrapped.split_at(IV_LEN);
        with_env(|env| {
            let key = wrapping_key(env)?
                .ok_or_else(|| Failure::from("the Keystore has no wrapping key"))?;
            let iv = env.byte_array_from_slice(iv)?;
            let spec = env.new_object(
                "javax/crypto/spec/GCMParameterSpec",
                "(I[B)V",
                &[JValue::Int(TAG_BITS), JValue::Object(&iv)],
            )?;
            let cipher = cipher(env)?;
            env.call_method(
                &cipher,
                "init",
                "(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V",
                &[
                    JValue::Int(DECRYPT_MODE),
                    JValue::Object(&key),
                    JValue::Object(&spec),
                ],
            )?;
            update_aad(env, &cipher)?;

            let input = env.byte_array_from_slice(sealed)?;
            let plain: JByteArray = env
                .call_method(&cipher, "doFinal", "([B)[B", &[JValue::Object(&input)])?
                .l()?
                .into();
            let bytes = Zeroizing::new(env.convert_byte_array(&plain)?);
            env.set_byte_array_region(&plain, 0, &vec![0; bytes.len()])?;
            if bytes.len() != MASTER_KEY_LEN {
                return Err(Failure::from(
                    "the unwrapped master key has the wrong length",
                ));
            }
            let mut secret = Zeroizing::new([0; MASTER_KEY_LEN]);
            secret.copy_from_slice(&bytes);
            Ok(secret)
        })
    }
}

/// Why a JNI call sequence failed.
enum Failure {
    Jni(jni::errors::Error),
    Other(String),
}

impl From<jni::errors::Error> for Failure {
    fn from(error: jni::errors::Error) -> Failure {
        Failure::Jni(error)
    }
}

impl From<&str> for Failure {
    fn from(message: &str) -> Failure {
        Failure::Other(message.to_owned())
    }
}

/// Runs `f` on this thread's JNI environment, in its own local reference frame, and turns a Java
/// exception into its description.
fn with_env<T>(
    f: impl FnOnce(&mut JNIEnv<'_>) -> Result<T, Failure>,
) -> Result<T, PlatformKeyError> {
    let device =
        device().ok_or_else(|| PlatformKeyError("KronoerCore.init was not called".to_owned()))?;
    let mut env = device
        .vm
        .attach_current_thread()
        .map_err(|error| PlatformKeyError(error.to_string()))?;
    match env.with_local_frame(32, |env| f(env)) {
        Ok(value) => Ok(value),
        Err(Failure::Other(message)) => Err(PlatformKeyError(message)),
        Err(Failure::Jni(error)) => Err(PlatformKeyError(describe(&mut env, error))),
    }
}

/// The pending Java exception as text, cleared, or the JNI error if there is none.
fn describe(env: &mut JNIEnv<'_>, error: jni::errors::Error) -> String {
    if !env.exception_check().unwrap_or(false) {
        return error.to_string();
    }
    let throwable = env.exception_occurred();
    let _ = env.exception_clear();
    throwable
        .ok()
        .and_then(|throwable| {
            env.call_method(&throwable, "toString", "()Ljava/lang/String;", &[])
                .and_then(|text| text.l())
                .ok()
        })
        .and_then(|text| env.get_string(&JString::from(text)).ok().map(String::from))
        .unwrap_or_else(|| error.to_string())
}

/// The wrapping key, or `None` if the Keystore has none.
fn wrapping_key<'local>(env: &mut JNIEnv<'local>) -> Result<Option<JObject<'local>>, Failure> {
    let keystore_type = env.new_string(KEYSTORE)?;
    let keystore = env
        .call_static_method(
            "java/security/KeyStore",
            "getInstance",
            "(Ljava/lang/String;)Ljava/security/KeyStore;",
            &[JValue::Object(&keystore_type)],
        )?
        .l()?;
    env.call_method(
        &keystore,
        "load",
        "(Ljava/security/KeyStore$LoadStoreParameter;)V",
        &[JValue::Object(&JObject::null())],
    )?;
    let alias = env.new_string(ALIAS)?;
    let key = env
        .call_method(
            &keystore,
            "getKey",
            "(Ljava/lang/String;[C)Ljava/security/Key;",
            &[JValue::Object(&alias), JValue::Object(&JObject::null())],
        )?
        .l()?;
    Ok((!key.is_null()).then_some(key))
}

/// Creates the wrapping key in the Keystore: AES-256 for GCM, with no user authentication and no
/// unlocked-device requirement (both off by default, and never turned on here).
fn generate_wrapping_key(env: &mut JNIEnv<'_>) -> Result<(), Failure> {
    let algorithm = env.new_string("AES")?;
    let provider = env.new_string(KEYSTORE)?;
    let generator = env
        .call_static_method(
            "javax/crypto/KeyGenerator",
            "getInstance",
            "(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/KeyGenerator;",
            &[JValue::Object(&algorithm), JValue::Object(&provider)],
        )?
        .l()?;

    let alias = env.new_string(ALIAS)?;
    let builder = env.new_object(
        BUILDER,
        "(Ljava/lang/String;I)V",
        &[
            JValue::Object(&alias),
            JValue::Int(PURPOSE_ENCRYPT | PURPOSE_DECRYPT),
        ],
    )?;
    let gcm = string_array(env, "GCM")?;
    env.call_method(
        &builder,
        "setBlockModes",
        BUILDER_RETURN_STRINGS,
        &[JValue::Object(&gcm)],
    )?;
    let no_padding = string_array(env, "NoPadding")?;
    env.call_method(
        &builder,
        "setEncryptionPaddings",
        BUILDER_RETURN_STRINGS,
        &[JValue::Object(&no_padding)],
    )?;
    env.call_method(
        &builder,
        "setKeySize",
        "(I)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
        &[JValue::Int(256)],
    )?;
    let spec = env
        .call_method(
            &builder,
            "build",
            "()Landroid/security/keystore/KeyGenParameterSpec;",
            &[],
        )?
        .l()?;

    env.call_method(
        &generator,
        "init",
        "(Ljava/security/spec/AlgorithmParameterSpec;)V",
        &[JValue::Object(&spec)],
    )?;
    env.call_method(&generator, "generateKey", "()Ljavax/crypto/SecretKey;", &[])?;
    Ok(())
}

fn cipher<'local>(env: &mut JNIEnv<'local>) -> Result<JObject<'local>, Failure> {
    let transformation = env.new_string(TRANSFORMATION)?;
    Ok(env
        .call_static_method(
            "javax/crypto/Cipher",
            "getInstance",
            "(Ljava/lang/String;)Ljavax/crypto/Cipher;",
            &[JValue::Object(&transformation)],
        )?
        .l()?)
}

fn update_aad(env: &mut JNIEnv<'_>, cipher: &JObject<'_>) -> Result<(), Failure> {
    let aad = env.byte_array_from_slice(AAD)?;
    env.call_method(cipher, "updateAAD", "([B)V", &[JValue::Object(&aad)])?;
    Ok(())
}

fn string_array<'local>(env: &mut JNIEnv<'local>, value: &str) -> Result<JObject<'local>, Failure> {
    let value = env.new_string(value)?;
    Ok(env.new_object_array(1, "java/lang/String", &value)?.into())
}
