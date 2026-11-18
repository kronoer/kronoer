# Entry format

Status: Draft
Version: 0.2

This document defines how Kronoer stores an Entry and its Images: the bytes written on the device and, with sync, sent to the server unchanged. The reference implementation is `core/`.

Book records are only reserved in this version; their section is filled in by a later version of this document.

## Terminology

- **Entry**: one piece of writing in a Book: plain text plus attached Images.
- **Book**: a named collection of Entries, personal or shared.
- **Image**: a picture attached to an Entry. It is stored as two Image blobs: the **full** image and a **thumbnail**.
- **Book key**: the 32-byte secret that opens one Book. Every Book has one. It has a **Book key version**, an unsigned integer starting at 1.
- **Entry key**: the 32-byte random key that protects one sealed Entry. A new Entry key is made every time an Entry is sealed.
- **Image key**: the 32-byte random key that protects one Image. It is made once, when the Image is attached, and kept as long as the Image stays attached.
- **Image blob**: the bytes that hold one sealed variant (full or thumbnail) of an Image.
- **Image reference**: what an Entry's payload holds about one Image: its ID, its Image key, and the hash of each of its Image blobs.
- **Entry date**: the date and time an Entry is about, chosen by its author, with the UTC offset of the place it was written.
- **Entry blob**: the bytes that hold one sealed Entry.
- **Header**: the part of an Entry blob that is not encrypted. It is authenticated.
- **Payload**: the encrypted part of an Entry blob.
- **Writer** and **reader**: an implementation that seals an Entry, and one that opens it.

## Conventions

### Encoding

Every structure is encoded as CBOR ([RFC 8949](https://www.rfc-editor.org/rfc/rfc8949)) in its deterministic form ([section 4.2.1](https://www.rfc-editor.org/rfc/rfc8949#section-4.2.1)):

- Integers, lengths, and other arguments use the shortest encoding.
- Arrays and strings have definite lengths.
- No tags, floating-point values, or maps are used in this version.

A writer MUST produce this form. A reader MUST reject any input that is not in this form, including input with bytes after the outermost item. Decoding the input and encoding the result again, then comparing the two byte strings, is one way to check this.

Structures are described in CDDL ([RFC 8610](https://www.rfc-editor.org/rfc/rfc8610)). Every structure is an array, so its fields are identified by position.

### Randomness

Every key, nonce, and identifier described as random MUST come from a cryptographically secure random number generator.

### Encryption

All encryption in this document uses XChaCha20-Poly1305 ([draft-irtf-cfrg-xchacha-03](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03)): a 32-byte key, a 24-byte random nonce, and a 16-byte tag appended to the ciphertext.

`Seal(key, nonce, plaintext, aad)` is the ciphertext followed by the tag. `Open(key, nonce, sealed, aad)` returns the plaintext or fails.

### Hashing

`Hash(bytes)` is SHA-256 ([FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)): 32 bytes.

## Identifiers

```cddl
id = bstr .size 16
```

An identifier is 16 random bytes. It carries no time or order. Entries, Books, and Images each have one.

The text form of an identifier, used outside the format (in APIs, file names, and logs), is 32 lowercase hexadecimal digits.

## Entry date

```cddl
entry-date = tstr
```

An Entry date is the local date and time where the author was, followed by that place's UTC offset, in this exact form:

```text
YYYY-MM-DDTHH:MM:SS+HH:MM
YYYY-MM-DDTHH:MM:SS-HH:MM
```

It is a restricted form of an RFC 3339 `date-time` ([RFC 3339, section 5.6](https://www.rfc-editor.org/rfc/rfc3339#section-5.6)), and it MUST meet all of these:

- Exactly 25 characters, with the separators shown: an uppercase `T`, and no fractional seconds.
- The year is 0001 to 9999, and the date exists in the proleptic Gregorian calendar (2024-02-29 exists, 2026-02-29 does not).
- The hour is 00 to 23, the minute 00 to 59, and the second 00 to 59. Leap seconds are not allowed.
- The offset is at most 18:00 either way, and its minutes are 00 to 59. `Z` is not used. An offset of zero is written `+00:00`, never `-00:00`.

A reader SHOULD show the local date and time as written, without converting it to the reader's own time zone, so an Entry stays on the day it was written about.

Example: an Entry written at 23:30 in Jakarta on 17 November 2026 has the Entry date `2026-11-17T23:30:00+07:00`.

## Times

```cddl
time = int
```

A time is the number of milliseconds since 1970-01-01T00:00:00Z, ignoring leap seconds.

## Entry

### Entry blob

```cddl
entry-blob = [
  header: entry-header,
  entry-key-nonce: bstr .size 24,
  sealed-entry-key: bstr .size 48,
  payload-nonce: bstr .size 24,
  sealed-payload: bstr,
]

entry-header = [
  format-version: 1,
  entry-id: id,
  book-id: id,
  book-key-version: uint .ge 1,
  entry-date: entry-date,
]

entry-payload = [
  text: tstr,
  images: [* image-ref],
  created-at: time,
  updated-at: time,
]

image-ref = [
  image-id: id,
  image-key: bstr .size 32,
  full-hash: bstr .size 32,
  thumbnail-hash: bstr .size 32,
]
```

- `format-version` is the version of the data, not of this document. It is 1 for everything this document defines.
- `book-key-version` names the version of the Book key that sealed the Entry key.
- `sealed-entry-key` is the sealed Entry key: 32 bytes of key and a 16-byte tag.
- `sealed-payload` is the sealed, encoded `entry-payload`, so it is at least 16 bytes.
- `text` is the Entry's plain text, in UTF-8. It MAY be empty. It is stored as written, without Unicode normalization.
- `images` lists the Images attached to the Entry, in the order they are shown. It MAY be empty. No two references in it have the same `image-id`.
- `image-key` is the Image's Image key, and `full-hash` and `thumbnail-hash` are `Hash` of the Image's full and thumbnail blobs. See [Image](#image).
- `created-at` is when the Entry was first written, and `updated-at` is when it was last changed.

### Associated data

The header is bound to both encryptions through associated data. For a context string `context`:

```text
AAD(context) = the deterministic CBOR encoding of [context, entry-header]
```

where `context` is a text string and `entry-header` is the header of the blob being sealed or opened. The contexts are:

| Context                    | Used to seal       |
| -------------------------- | ------------------ |
| `kronoer/v1/entry-key`     | the Entry key      |
| `kronoer/v1/entry-payload` | the Entry payload  |

Using a different context for each keeps a sealed Entry key from being accepted as a payload, and the other way around.

### Sealing

To seal an Entry with a Book key, a writer:

1. Checks that the Entry date is valid, that the Entry's Book ID is the Book of the Book key, and that no Image is listed twice.
2. Makes a new random Entry key, a random `entry-key-nonce`, and a random `payload-nonce`. A writer MUST NOT reuse an Entry key, even when sealing a new version of the same Entry.
3. Encodes `entry-header` and `entry-payload`.
4. Computes `sealed-entry-key = Seal(Book key, entry-key-nonce, Entry key, AAD("kronoer/v1/entry-key"))`.
5. Computes `sealed-payload = Seal(Entry key, payload-nonce, entry-payload, AAD("kronoer/v1/entry-payload"))`.
6. Encodes `entry-blob`.

### Opening

A reader opens an Entry blob with the Entry ID it expects (the one under which it stored or requested the blob) and the Book key of the Book it expects. It:

1. Decodes `entry-blob`, rejecting any input that is not deterministic CBOR, does not match the structure, or holds an invalid Entry date. While decoding, it checks `format-version` as soon as it reads it: if it is not 1, the reader stops with `unsupported-version` before reading the rest of the header.
2. Checks that the input contains nothing after `entry-blob`.
3. Checks that `entry-id` is the expected Entry ID, that `book-id` is the Book of the Book key, and that `book-key-version` is the version of the Book key.
4. Computes the Entry key as `Open(Book key, entry-key-nonce, sealed-entry-key, AAD("kronoer/v1/entry-key"))`.
5. Computes the payload as `Open(Entry key, payload-nonce, sealed-payload, AAD("kronoer/v1/entry-payload"))`.
6. Decodes `entry-payload` with the same strictness as step 1, rejecting a payload that lists the same `image-id` twice.

If any step fails, the reader MUST stop and MUST NOT return any part of the Entry.

Opening an Entry does not open its Images. A reader opens each Image blob when it needs it, with the Image reference from the payload.

### Errors

Implementations may report failures in their own way. The test vectors name them with these codes:

| Code                  | Meaning                                                                  |
| --------------------- | ------------------------------------------------------------------------ |
| `malformed`           | The input does not match the structure, or a field holds an invalid value. |
| `non-canonical`       | The input is CBOR but not in deterministic form.                         |
| `unsupported-version` | `format-version` is not one the reader supports.                         |
| `invalid-entry-date`  | The Entry date breaks a rule in [Entry date](#entry-date).               |
| `wrong-entry`         | The header's Entry ID is not the expected one.                           |
| `wrong-book`          | The header's Book ID is not the Book of the Book key.                    |
| `wrong-key-version`   | The header names a different Book key version.                           |
| `hash-mismatch`       | An Image blob's hash is not the one in its Image reference.              |
| `wrong-image`         | The Image blob's header names a different Image.                         |
| `decryption-failed`   | A tag did not verify: the data was changed, or the key is wrong.         |

The same codes are used for Image blobs.

## Image

Every Image is sealed into two Image blobs under the same Image key: the full image and a thumbnail. Both are sealed once, when the Image is attached, and stay as they are while the Image stays attached. Sealing a new version of the Entry copies the Image reference unchanged and does not touch the blobs.

The plaintext of an Image blob is the bytes of an image file. This document does not fix the file type or the pixel size of either variant, and a reader does not look inside the bytes to open them.

### Image blob

```cddl
image-blob = [
  header: image-header,
  nonce: bstr .size 24,
  sealed-image: bstr,
]

image-header = [
  format-version: 1,
  image-id: id,
]
```

- `format-version` is the same data version as in `entry-header`.
- `sealed-image` is the sealed image bytes, so it is at least 16 bytes.

The two blobs of an Image have the same header. Their associated data differs by context:

```text
AAD(context) = the deterministic CBOR encoding of [context, image-header]
```

| Context                      | Used to seal   |
| ---------------------------- | -------------- |
| `kronoer/v1/image-full`      | the full image |
| `kronoer/v1/image-thumbnail` | the thumbnail  |

Using a different context for each keeps a thumbnail from opening as the full image, and the other way around.

### Sealing an Image

To seal an Image from the bytes of its full image and its thumbnail, a writer:

1. Makes a new random Image ID, a new random Image key, and a random nonce for each blob.
2. Encodes `image-header`.
3. For each variant, computes `sealed-image = Seal(Image key, nonce, image bytes, AAD(context))` and encodes `image-blob`.
4. Makes the Image reference: the Image ID, the Image key, and `Hash` of each encoded `image-blob`.

The writer then adds the Image reference to the Entry's `images` and seals the Entry.

### Opening an Image

A reader opens an Image blob with the Image reference from the Entry's payload and the variant it expects. It:

1. Checks that `Hash` of the input is the hash in the Image reference for that variant.
2. Decodes `image-blob` with the same strictness as an Entry blob, checking `format-version` as soon as it reads it, and checks that the input contains nothing after it.
3. Checks that `image-id` is the ID in the Image reference.
4. Computes the image bytes as `Open(Image key, nonce, sealed-image, AAD(context))`, with the context of the expected variant.

If any step fails, the reader MUST stop and MUST NOT return any part of the image.

## Book record

Reserved. A later version of this document defines the encrypted Book record and how Book keys are created and stored.

## Security considerations

- **Swapped Entries.** The header is authenticated by both encryptions, and a reader checks the Entry ID, Book ID, and Book key version against what it expects. A storage layer or server that hands back another Entry's blob, from the same Book or another, is detected.
- **Older versions.** A storage layer or server can hand back an older blob of the same Entry, and this format does not detect it. The sync protocol has to.
- **Swapped or changed Images.** An Entry's payload is authenticated, so its Image references, their order, and their hashes cannot be changed without the Book key. Each reference pins its two blobs by hash, so a storage layer or server that hands back another Image's blob, the other variant, an older blob, or a changed one is detected before decryption. The hash also commits to the Image key, which XChaCha20-Poly1305 alone does not do.
- **Readable metadata.** The header is not encrypted: anyone who holds a blob sees the Entry ID, Book ID, Book key version, and Entry date. The size of `sealed-payload` reveals the approximate length of the text, and its number of Images. An Image blob shows only its Image ID; which Entry holds it is inside the encrypted payload, though how blobs are stored or synced may still reveal it. The size of an Image blob reveals the size of the image file.
- **No signatures.** Anyone who holds a Book key can write a valid Entry for that Book. For a personal Book that is only its owner. Signatures arrive with shared Books.
- **Nonces.** Each Entry key seals one payload, each Image key seals two blobs, and nonces are 24 random bytes, so nonce reuse is not a practical risk.

## Test vectors

[`test-vectors/entry-format.json`](test-vectors/entry-format.json) holds vectors for this document, following the [test vector conventions](test-vectors/README.md):

- A **seal-entry** vector gives every input, including the Entry key, both nonces, and the Image references, and the expected `header`, `payload` (the encoded `entry-payload` before encryption), and `blob`. Sealing with those inputs MUST produce exactly `blob`, and opening `blob` MUST give back the inputs.
- An **open-entry** vector gives a `blob`, the Book key and its Book ID and version, the expected Entry ID, and the expected `error` code. Opening MUST fail with that error.
- A **seal-image** vector gives every input, including the Image ID, the Image key, both nonces, and the image bytes, and the expected `header`, both blobs, and both hashes. Sealing with those inputs MUST produce exactly those blobs, and opening each blob MUST give back its image bytes.
- An **open-image** vector gives a `blob`, an Image reference, the expected variant, and the expected `error` code. Opening MUST fail with that error. Some of these references pin a blob that a writer would never produce, so that a vector can reach the checks after the hash.

## Changes

- 0.2 (2026-11-18): Images. Image references in `entry-payload`, the Image blob, hashing with SHA-256, the errors `hash-mismatch` and `wrong-image`, and vector kinds renamed to `seal-entry` and `open-entry`. `format-version` stays 1.
- 0.1 (2026-11-17): First draft. Identifiers, Entry date, times, and the Entry blob. Image and Book record reserved.
