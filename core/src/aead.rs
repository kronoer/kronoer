//! XChaCha20-Poly1305, the only cipher in the format.

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use zeroize::Zeroizing;

use crate::Error;
use crate::keys::KEY_LEN;

/// The length of a nonce, in bytes.
pub(crate) const NONCE_LEN: usize = 24;

/// The length of the tag appended to every ciphertext, in bytes.
pub(crate) const TAG_LEN: usize = 16;

pub(crate) fn seal(
    key: &[u8; KEY_LEN],
    nonce: &[u8; NONCE_LEN],
    plaintext: &[u8],
    aad: &[u8],
) -> Vec<u8> {
    let key: &Key = key.into();
    let nonce: &XNonce = nonce.into();
    XChaCha20Poly1305::new(key)
        .encrypt(
            nonce,
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .expect("XChaCha20-Poly1305 encrypts any message that fits in memory")
}

/// Decrypts and authenticates. The plaintext is wiped from memory when dropped.
pub(crate) fn open(
    key: &[u8; KEY_LEN],
    nonce: &[u8; NONCE_LEN],
    sealed: &[u8],
    aad: &[u8],
) -> Result<Zeroizing<Vec<u8>>, Error> {
    let key: &Key = key.into();
    let nonce: &XNonce = nonce.into();
    XChaCha20Poly1305::new(key)
        .decrypt(nonce, Payload { msg: sealed, aad })
        .map(Zeroizing::new)
        .map_err(|_| Error::DecryptionFailed)
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: [u8; KEY_LEN] = [1; KEY_LEN];
    const NONCE: [u8; NONCE_LEN] = [2; NONCE_LEN];

    #[test]
    fn round_trips_and_appends_the_tag() {
        let sealed = seal(&KEY, &NONCE, b"rain today", b"aad");

        assert_eq!(sealed.len(), b"rain today".len() + TAG_LEN);
        assert_eq!(
            open(&KEY, &NONCE, &sealed, b"aad").unwrap().as_slice(),
            b"rain today"
        );
    }

    #[test]
    fn rejects_changed_aad_ciphertext_or_key() {
        let sealed = seal(&KEY, &NONCE, b"rain today", b"aad");
        let mut flipped = sealed.clone();
        flipped[0] ^= 1;

        assert_eq!(
            open(&KEY, &NONCE, &sealed, b"aaD"),
            Err(Error::DecryptionFailed)
        );
        assert_eq!(
            open(&KEY, &NONCE, &flipped, b"aad"),
            Err(Error::DecryptionFailed)
        );
        assert_eq!(
            open(&[3; KEY_LEN], &NONCE, &sealed, b"aad"),
            Err(Error::DecryptionFailed)
        );
    }

    /// Test vector A.3 of draft-irtf-cfrg-xchacha-03, so the cipher is the one the spec names.
    #[test]
    fn matches_the_xchacha_draft_vector() {
        let key: [u8; KEY_LEN] = std::array::from_fn(|i| 0x80 + i as u8);
        let nonce: [u8; NONCE_LEN] = std::array::from_fn(|i| 0x40 + i as u8);
        let aad = crate::hex::decode("50515253c0c1c2c3c4c5c6c7").unwrap();
        let plaintext = b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
        let expected = crate::hex::decode(concat!(
            "bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb",
            "731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452",
            "2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9",
            "21f9664c97637da9768812f615c68b13b52e",
            "c0875924c1c7987947deafd8780acf49",
        ))
        .unwrap();

        assert_eq!(seal(&key, &nonce, plaintext, &aad), expected);
    }
}
