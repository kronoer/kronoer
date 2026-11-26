//! The Image blobs of `spec/entry-format.md`: every Image is sealed twice, at full size and as a
//! thumbnail, with its own Image key, and the Entry that holds it pins both blobs by hash.

use std::fmt;

use minicbor::Decoder;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

use crate::aead::{self, NONCE_LEN, TAG_LEN};
use crate::cbor::{self, WriteResult, Writer};
use crate::entry::FORMAT_VERSION;
use crate::keys::KEY_LEN;
use crate::{Error, Id, random};

/// The length of a SHA-256 hash, in bytes.
pub(crate) const HASH_LEN: usize = 32;

const BLOB_LEN: u64 = 3;
const HEADER_LEN: u64 = 2;
const REF_LEN: u64 = 4;

/// One of the two blobs every Image is sealed into.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ImageVariant {
    /// The image at full size.
    Full,
    /// A small copy of the image, for lists and previews.
    Thumbnail,
}

impl ImageVariant {
    /// The associated data context, so one variant's blob never opens as the other.
    fn context(self) -> &'static str {
        match self {
            ImageVariant::Full => "kronoer/v1/image-full",
            ImageVariant::Thumbnail => "kronoer/v1/image-thumbnail",
        }
    }
}

/// What an Entry stores about one attached Image: its ID, its Image key, and the hash of each of
/// its two blobs.
///
/// The key is wiped from memory when dropped, and never shown by `Debug`. Keep the reference as it
/// is while the Image stays attached: its blobs are not sealed again when the Entry changes.
#[derive(Clone, PartialEq, Eq)]
pub struct ImageRef {
    id: Id,
    key: Zeroizing<[u8; KEY_LEN]>,
    full_hash: [u8; HASH_LEN],
    thumbnail_hash: [u8; HASH_LEN],
}

impl ImageRef {
    /// The Image's ID.
    pub fn id(&self) -> Id {
        self.id
    }

    /// The SHA-256 hash of one of the Image's blobs.
    pub fn hash(&self, variant: ImageVariant) -> &[u8; HASH_LEN] {
        match variant {
            ImageVariant::Full => &self.full_hash,
            ImageVariant::Thumbnail => &self.thumbnail_hash,
        }
    }

    pub(crate) fn new(
        id: Id,
        key: [u8; KEY_LEN],
        full_hash: [u8; HASH_LEN],
        thumbnail_hash: [u8; HASH_LEN],
    ) -> ImageRef {
        ImageRef {
            id,
            key: Zeroizing::new(key),
            full_hash,
            thumbnail_hash,
        }
    }

    pub(crate) fn key(&self) -> &[u8; KEY_LEN] {
        &self.key
    }

    pub(crate) fn write(&self, w: &mut Writer) -> WriteResult {
        w.array(REF_LEN)?
            .bytes(self.id.as_bytes())?
            .bytes(self.key.as_slice())?
            .bytes(&self.full_hash)?
            .bytes(&self.thumbnail_hash)?;
        Ok(())
    }

    pub(crate) fn read(d: &mut Decoder<'_>) -> Result<ImageRef, Error> {
        cbor::array_of(d, REF_LEN)?;
        Ok(ImageRef {
            id: Id::from_bytes(cbor::bytes_of(d)?),
            key: Zeroizing::new(cbor::bytes_of(d)?),
            full_hash: cbor::bytes_of(d)?,
            thumbnail_hash: cbor::bytes_of(d)?,
        })
    }
}

impl fmt::Debug for ImageRef {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ImageRef")
            .field("id", &self.id)
            .finish_non_exhaustive()
    }
}

/// A newly sealed Image: the reference to put in its Entry, and its two blobs to store.
#[derive(Debug)]
pub struct SealedImage {
    /// The reference to add to the Entry's Images.
    pub image: ImageRef,
    /// The blob of the full-size image.
    pub full: Vec<u8>,
    /// The blob of the thumbnail.
    pub thumbnail: Vec<u8>,
}

/// Seals a new Image from the bytes of its full-size image and its thumbnail, with a new random
/// Image ID and Image key.
///
/// The bytes are sealed as given: this function does not read, resize, or convert images.
pub fn seal_image(full: &[u8], thumbnail: &[u8]) -> Result<SealedImage, Error> {
    let id = Id::random()?;
    let key = random::secret::<KEY_LEN>()?;
    let full_nonce = random::bytes::<NONCE_LEN>()?;
    let thumbnail_nonce = random::bytes::<NONCE_LEN>()?;
    Ok(seal_image_with(
        id,
        &key,
        &full_nonce,
        &thumbnail_nonce,
        full,
        thumbnail,
    ))
}

/// Opens one of an Image's blobs and returns the image bytes.
///
/// Opening fails if the blob is not exactly the one `image` pins for that variant, belongs to
/// another Image, or was changed in any way.
pub fn open_image(blob: &[u8], image: &ImageRef, variant: ImageVariant) -> Result<Vec<u8>, Error> {
    if hash(blob) != *image.hash(variant) {
        return Err(Error::HashMismatch);
    }
    let blob = Blob::decode(blob)?;
    if blob.header.image_id != image.id {
        return Err(Error::WrongImage);
    }
    let mut plaintext = aead::open(
        image.key(),
        &blob.nonce,
        &blob.sealed_image,
        &blob.header.aad(variant.context()),
    )?;
    Ok(std::mem::take(&mut *plaintext))
}

/// [`seal_image`] with the random values given, for test vectors.
pub(crate) fn seal_image_with(
    id: Id,
    key: &[u8; KEY_LEN],
    full_nonce: &[u8; NONCE_LEN],
    thumbnail_nonce: &[u8; NONCE_LEN],
    full: &[u8],
    thumbnail: &[u8],
) -> SealedImage {
    let seal = |variant: ImageVariant, nonce: &[u8; NONCE_LEN], plaintext: &[u8]| {
        let header = Header { image_id: id };
        let sealed_image = aead::seal(key, nonce, plaintext, &header.aad(variant.context()));
        Blob {
            header,
            nonce: *nonce,
            sealed_image,
        }
        .encode()
    };
    let full = seal(ImageVariant::Full, full_nonce, full);
    let thumbnail = seal(ImageVariant::Thumbnail, thumbnail_nonce, thumbnail);

    SealedImage {
        image: ImageRef::new(id, *key, hash(&full), hash(&thumbnail)),
        full,
        thumbnail,
    }
}

/// The SHA-256 hash of a blob.
pub(crate) fn hash(blob: &[u8]) -> [u8; HASH_LEN] {
    Sha256::digest(blob).into()
}

/// The part of an Image blob that is not encrypted. It is authenticated as associated data.
#[derive(Debug)]
pub(crate) struct Header {
    pub(crate) image_id: Id,
}

impl Header {
    fn write(&self, w: &mut Writer) -> WriteResult {
        w.array(HEADER_LEN)?
            .u64(FORMAT_VERSION)?
            .bytes(self.image_id.as_bytes())?;
        Ok(())
    }

    /// Reads a header, checking the format version before anything after it.
    fn read(d: &mut Decoder<'_>) -> Result<Header, Error> {
        let len = cbor::array(d)?;
        let version = cbor::uint(d)?;
        if version != FORMAT_VERSION {
            return Err(Error::UnsupportedVersion(version));
        }
        if len != HEADER_LEN {
            return Err(Error::Malformed);
        }
        Ok(Header {
            image_id: Id::from_bytes(cbor::bytes_of(d)?),
        })
    }

    /// The associated data for one context: the encoding of `[context, header]`.
    fn aad(&self, context: &str) -> Vec<u8> {
        cbor::encode(|w| {
            w.array(2)?.str(context)?;
            self.write(w)
        })
    }

    #[cfg(test)]
    pub(crate) fn encode(&self) -> Vec<u8> {
        cbor::encode(|w| self.write(w))
    }
}

struct Blob {
    header: Header,
    nonce: [u8; NONCE_LEN],
    sealed_image: Vec<u8>,
}

impl Blob {
    fn encode(&self) -> Vec<u8> {
        cbor::encode(|w| {
            w.array(BLOB_LEN)?;
            self.header.write(w)?;
            w.bytes(&self.nonce)?.bytes(&self.sealed_image)?;
            Ok(())
        })
    }

    fn decode(input: &[u8]) -> Result<Blob, Error> {
        let mut d = Decoder::new(input);
        let len = cbor::array(&mut d)?;
        let header = Header::read(&mut d)?;
        if len != BLOB_LEN {
            return Err(Error::Malformed);
        }
        let nonce = cbor::bytes_of(&mut d)?;
        let sealed_image = cbor::bytes(&mut d)?.to_vec();
        if sealed_image.len() < TAG_LEN {
            return Err(Error::Malformed);
        }
        cbor::finish(&d, input)?;

        let blob = Blob {
            header,
            nonce,
            sealed_image,
        };
        cbor::check_canonical(input, &blob.encode())?;
        Ok(blob)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FULL: &[u8] = b"Full-size image bytes.";
    const THUMBNAIL: &[u8] = b"Thumbnail bytes.";

    fn sealed() -> SealedImage {
        seal_image(FULL, THUMBNAIL).unwrap()
    }

    /// `image` with one variant's hash set to match `blob`, to reach the checks after the hash.
    fn pinned(image: &ImageRef, variant: ImageVariant, blob: &[u8]) -> ImageRef {
        let mut image = image.clone();
        match variant {
            ImageVariant::Full => image.full_hash = hash(blob),
            ImageVariant::Thumbnail => image.thumbnail_hash = hash(blob),
        }
        image
    }

    #[test]
    fn round_trips_both_variants() {
        let sealed = sealed();

        assert_eq!(
            open_image(&sealed.full, &sealed.image, ImageVariant::Full).unwrap(),
            FULL
        );
        assert_eq!(
            open_image(&sealed.thumbnail, &sealed.image, ImageVariant::Thumbnail).unwrap(),
            THUMBNAIL
        );
    }

    #[test]
    fn round_trips_empty_images() {
        let sealed = seal_image(b"", b"").unwrap();

        assert!(
            open_image(&sealed.full, &sealed.image, ImageVariant::Full)
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn every_image_gets_its_own_id_key_and_nonces() {
        let first = sealed();
        let second = sealed();

        assert_ne!(first.image.id, second.image.id);
        assert_ne!(first.image.key, second.image.key);
        assert_ne!(first.full, second.full);
        let first_full = Blob::decode(&first.full).unwrap();
        let first_thumbnail = Blob::decode(&first.thumbnail).unwrap();
        assert_ne!(first_full.nonce, first_thumbnail.nonce);
    }

    #[test]
    fn rejects_the_other_variants_blob() {
        let sealed = sealed();

        assert_eq!(
            open_image(&sealed.thumbnail, &sealed.image, ImageVariant::Full),
            Err(Error::HashMismatch)
        );
        let image = pinned(&sealed.image, ImageVariant::Full, &sealed.thumbnail);
        assert_eq!(
            open_image(&sealed.thumbnail, &image, ImageVariant::Full),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn rejects_another_images_blob() {
        let first = sealed();
        let second = sealed();

        assert_eq!(
            open_image(&second.full, &first.image, ImageVariant::Full),
            Err(Error::HashMismatch)
        );
        let image = pinned(&first.image, ImageVariant::Full, &second.full);
        assert_eq!(
            open_image(&second.full, &image, ImageVariant::Full),
            Err(Error::WrongImage)
        );
    }

    #[test]
    fn rejects_any_changed_byte() {
        let sealed = sealed();

        for at in 0..sealed.full.len() {
            let mut changed = sealed.full.clone();
            changed[at] ^= 0x01;
            assert_eq!(
                open_image(&changed, &sealed.image, ImageVariant::Full),
                Err(Error::HashMismatch),
                "byte {at}"
            );
            let image = pinned(&sealed.image, ImageVariant::Full, &changed);
            assert!(
                open_image(&changed, &image, ImageVariant::Full).is_err(),
                "byte {at} with a matching hash"
            );
        }
    }

    #[test]
    fn rejects_the_wrong_key() {
        let sealed = sealed();
        let mut image = sealed.image.clone();
        image.key = Zeroizing::new([0; KEY_LEN]);

        assert_eq!(
            open_image(&sealed.full, &image, ImageVariant::Full),
            Err(Error::DecryptionFailed)
        );
    }

    #[test]
    fn rejects_other_format_versions() {
        let sealed = sealed();
        let mut blob = sealed.full.clone();
        // 0x83 (array of 3), 0x82 (header, array of 2), then the version.
        assert_eq!(blob[2], 0x01);
        blob[2] = 0x02;
        let image = pinned(&sealed.image, ImageVariant::Full, &blob);

        assert_eq!(
            open_image(&blob, &image, ImageVariant::Full),
            Err(Error::UnsupportedVersion(2))
        );
    }

    #[test]
    fn reads_back_what_it_writes() {
        let image = sealed().image;
        let encoded = cbor::encode(|w| image.write(w));

        assert_eq!(ImageRef::read(&mut Decoder::new(&encoded)).unwrap(), image);
    }

    #[test]
    fn debug_hides_the_key() {
        let image = ImageRef::new(Id::from_bytes([0; 16]), [0xab; KEY_LEN], [0; 32], [0; 32]);
        let shown = format!("{image:?}");

        assert!(shown.contains("ImageRef"));
        assert!(!shown.contains("ab, ab") && !shown.contains("171"));
    }
}
