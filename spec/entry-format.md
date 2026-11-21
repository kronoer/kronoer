# Entry format

Status: Draft
Version: 0.4

This document defines how Kronoer stores an Entry, its Images, and its Book, and the keys that protect them: the bytes written on the device and, with sync, sent to the server unchanged. The reference implementation is `core/`.

## Terminology

- **Master key**: the 32-byte random secret of one device that the keys of its personal Books come from. It never encrypts anything itself.
- **Subkey**: a key derived from the master key for one purpose.
- **Wrapped Book key**: the bytes that hold a Book key sealed with a subkey, for storing next to its Book.
- **Book record**: the bytes that hold a Book's name, sealed with its Book key.

- **Entry**: one piece of writing in a Book: plain text plus attached Images.
- **Book**: a named collection of Entries, personal or shared.
- **Text style**: a mark in an Entry's text that changes how part of it looks when shown. See [Text styles](#text-styles).
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

### Key derivation

`Derive(key, label)` is HKDF-SHA256 ([RFC 5869](https://www.rfc-editor.org/rfc/rfc5869)) with `key` as the input keying material, an empty salt, the UTF-8 bytes of `label` as the info, and 32 bytes of output.

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

## Keys

### Master key

Each device has one master key: 32 random bytes made once, when the device first needs a key. How the device keeps it is outside this document. It is never derived from a password or from the app lock.

The master key never encrypts anything. Each use has its own subkey:

```text
subkey = Derive(master key, label)
```

| Label                      | Subkey used to                                |
| -------------------------- | --------------------------------------------- |
| `kronoer/v1/book-key-wrap` | wrap the Book keys of personal Books          |
| `kronoer/v1/sqlcipher`     | open the local database on the device         |

Keys that are shared, rotated, or made for each item (Book keys, Entry keys, and Image keys) are random, never derived.

### Book key

A Book key is 32 random bytes, made when its Book is created. Every Book has one, personal Books too. A new version of a Book's key is a new random key with a version one higher; the versions of one Book never share a key.

A personal Book's key is stored as a wrapped Book key:

```cddl
wrapped-book-key = [
  header: book-header,
  nonce: bstr .size 24,
  sealed-book-key: bstr .size 48,
]

book-header = [
  format-version: 1,
  book-id: id,
  book-key-version: uint .ge 1,
]
```

- `format-version` is the same data version as in `entry-header`.
- `book-key-version` is the version of the wrapped Book key.
- `sealed-book-key` is the sealed Book key: 32 bytes of key and a 16-byte tag.

The header is bound to the encryption through associated data, as for an Entry:

```text
AAD(context) = the deterministic CBOR encoding of [context, book-header]
```

with the context `kronoer/v1/book-key`.

To wrap a Book key, a writer makes a random nonce and computes:

```text
sealed-book-key = Seal(Derive(master key, "kronoer/v1/book-key-wrap"), nonce, Book key, AAD("kronoer/v1/book-key"))
```

To unwrap a Book key, a reader takes the Book ID it expects (the one under which it stored or requested the wrapped key) and the master key. It:

1. Decodes `wrapped-book-key` with the same strictness as an Entry blob, checking `format-version` as soon as it reads it, and checks that the input contains nothing after it.
2. Checks that `book-id` is the expected Book ID.
3. Computes the Book key as `Open(Derive(master key, "kronoer/v1/book-key-wrap"), nonce, sealed-book-key, AAD("kronoer/v1/book-key"))`. Its version is `book-key-version`.

If any step fails, the reader MUST stop and MUST NOT return the key.

Shared Books wrap their Book key for each member in a way a later version of this document defines.

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

### Text styles

This section is informative: it changes nothing in what is stored or checked. `text` may hold Text styles, marks that a reader showing the text reads as styles. The marks stay in `text` as written, and a reader that ignores them shows them as written. Readers that show styles follow these rules, so the same text looks the same everywhere.

Inline styles:

- `*bold*`, `_italic_`, `~strikethrough~`, and `` `inline code` `` style the text between a pair of the same mark. Styles combine, as in `*_bold italic_*`.
- An opening mark is at the start of a line or after a character that is not a letter or a digit, and is followed by a character that is not white space. A closing mark follows a character that is not white space, and is at the end of a line or before a character that is not a letter or a digit. The first closing mark that fits closes it. So `2 * 3 * 4` and `file_name_here` have no style.
- A pair never spans a line break. A mark without its pair is shown as written. There is no escape.
- Nothing inside inline code is styled.

Blocks:

- The text between a pair of ```` ``` ```` is a monospace block, and may span lines. A line break right after the opening mark and right before the closing one belongs to the marks. Nothing inside the block is styled. A pair with only white space between is shown as written.
- A line starting with `- ` or `* ` is a bulleted list item. A line starting with one or more digits, a period, and a space (`12. `) is a numbered list item; its number is shown as written. Lists do not nest.
- Consecutive lines starting with `> ` form one quote. Quotes do not nest.
- Other lines up to a blank line, or to a line of another kind, form a paragraph.
- Inline styles apply inside list items, quotes, and paragraphs.

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
| `wrong-book`          | The header's Book ID is not the Book of the Book key, or not the expected Book. |
| `wrong-key-version`   | The header names a different Book key version.                           |
| `hash-mismatch`       | An Image blob's hash is not the one in its Image reference.              |
| `wrong-image`         | The Image blob's header names a different Image.                         |
| `decryption-failed`   | A tag did not verify: the data was changed, or the key is wrong.         |

The same codes are used for Image blobs, wrapped Book keys, and Book records.

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

A Book record holds what a Book is, apart from its Entries: in this version, its name. It is sealed with the Book key, so everyone who can read the Book's Entries can read its name.

```cddl
book-record = [
  header: book-header,
  nonce: bstr .size 24,
  sealed-payload: bstr,
]

book-payload = [
  name: tstr,
]
```

- `header` is a `book-header`, as in a wrapped Book key. Its `book-key-version` names the version of the Book key that sealed the record.
- `sealed-payload` is the sealed, encoded `book-payload`, so it is at least 16 bytes.
- `name` is the Book's name in UTF-8, stored as written, without Unicode normalization. It MAY be empty.

The associated data is `AAD("kronoer/v1/book-record")`, built from `book-header` as for a wrapped Book key. The different context keeps a wrapped Book key from opening as a Book record, and the other way around.

### Sealing a Book record

To seal a Book record with a Book key, a writer:

1. Checks that the record's Book ID is the Book of the Book key.
2. Makes a random nonce. A writer makes a new nonce, and a new record, every time the name changes.
3. Encodes `book-header` and `book-payload`.
4. Computes `sealed-payload = Seal(Book key, nonce, book-payload, AAD("kronoer/v1/book-record"))`.
5. Encodes `book-record`.

### Opening a Book record

A reader opens a Book record with the Book key of the Book it expects. It:

1. Decodes `book-record` with the same strictness as an Entry blob, checking `format-version` as soon as it reads it, and checks that the input contains nothing after it.
2. Checks that `book-id` is the Book of the Book key, and that `book-key-version` is the version of the Book key.
3. Computes the payload as `Open(Book key, nonce, sealed-payload, AAD("kronoer/v1/book-record"))`.
4. Decodes `book-payload` with the same strictness as step 1.

If any step fails, the reader MUST stop and MUST NOT return any part of the record.

## Security considerations

- **Swapped Entries.** The header is authenticated by both encryptions, and a reader checks the Entry ID, Book ID, and Book key version against what it expects. A storage layer or server that hands back another Entry's blob, from the same Book or another, is detected.
- **Older versions.** A storage layer or server can hand back an older blob of the same Entry, an older Book record of the same Book (showing a name it had before), or a wrapped Book key of an older version of the same Book (after which Entries sealed with the newer version fail with `wrong-key-version`). This format does not detect any of these. The sync protocol has to.
- **Swapped or changed Images.** An Entry's payload is authenticated, so its Image references, their order, and their hashes cannot be changed without the Book key. Each reference pins its two blobs by hash, so a storage layer or server that hands back another Image's blob, the other variant, an older blob, or a changed one is detected before decryption. The hash also commits to the Image key, which XChaCha20-Poly1305 alone does not do.
- **Readable metadata.** The header is not encrypted: anyone who holds a blob sees the Entry ID, Book ID, Book key version, and Entry date. The size of `sealed-payload` reveals the approximate length of the text, and its number of Images. An Image blob shows only its Image ID; which Entry holds it is inside the encrypted payload, though how blobs are stored or synced may still reveal it. The size of an Image blob reveals the size of the image file.
- **No signatures.** Anyone who holds a Book key can write a valid Entry for that Book. For a personal Book that is only its owner. Signatures arrive with shared Books.
- **Nonces.** Each Entry key seals one payload, each Image key seals two blobs, and nonces are 24 random bytes, so nonce reuse is not a practical risk. A Book key and the wrapping subkey seal many items, which 24-byte random nonces also allow.
- **One key, one purpose.** The master key only feeds HKDF, and every subkey has its own label, so a key made for one purpose never opens data of another. A wrong master key, or a wrapped Book key moved to another Book, fails to unwrap.
- **Swapped Books.** A wrapped Book key and a Book record each bind their Book ID and Book key version as associated data. A storage layer or server that hands back another Book's wrapped key or record, or changes the version in the header, is detected.
- **Book metadata.** A wrapped Book key and a Book record show their Book ID and Book key version. The size of `sealed-payload` in a Book record reveals the approximate length of the name.

## Test vectors

[`test-vectors/entry-format.json`](test-vectors/entry-format.json) holds vectors for this document, following the [test vector conventions](test-vectors/README.md):

- A **seal-entry** vector gives every input, including the Entry key, both nonces, and the Image references, and the expected `header`, `payload` (the encoded `entry-payload` before encryption), and `blob`. Sealing with those inputs MUST produce exactly `blob`, and opening `blob` MUST give back the inputs.
- An **open-entry** vector gives a `blob`, the Book key and its Book ID and version, the expected Entry ID, and the expected `error` code. Opening MUST fail with that error.
- A **seal-image** vector gives every input, including the Image ID, the Image key, both nonces, and the image bytes, and the expected `header`, both blobs, and both hashes. Sealing with those inputs MUST produce exactly those blobs, and opening each blob MUST give back its image bytes.
- An **open-image** vector gives a `blob`, an Image reference, the expected variant, and the expected `error` code. Opening MUST fail with that error. Some of these references pin a blob that a writer would never produce, so that a vector can reach the checks after the hash.
- A **derive-subkey** vector gives a master key and a label, and the expected subkey.
- A **wrap-book-key** vector gives every input, including the master key and the nonce, and the expected `header` and `wrapped` bytes. Wrapping with those inputs MUST produce exactly `wrapped`, and unwrapping it MUST give back the Book key and its version.
- An **unwrap-book-key** vector gives `wrapped` bytes, the expected Book ID, a master key, and the expected `error` code. Unwrapping MUST fail with that error.
- A **seal-book-record** vector gives every input, including the nonce, and the expected `header`, `payload` (the encoded `book-payload` before encryption), and `blob`. Sealing with those inputs MUST produce exactly `blob`, and opening it MUST give back the name.
- An **open-book-record** vector gives a `blob`, a Book key with its Book ID and version, and the expected `error` code. Opening MUST fail with that error.

## Changes

- 0.4 (2026-11-21): Text styles, an informative section on the marks `text` may hold. Nothing stored or checked changes; `format-version` stays 1.

- 0.3 (2026-11-19): Keys and Book records. The master key, subkeys with HKDF-SHA256 and their labels, the wrapped Book key, the Book record, and the vector kinds `derive-subkey`, `wrap-book-key`, `unwrap-book-key`, `seal-book-record`, and `open-book-record`. `format-version` stays 1.

- 0.2 (2026-11-18): Images. Image references in `entry-payload`, the Image blob, hashing with SHA-256, the errors `hash-mismatch` and `wrong-image`, and vector kinds renamed to `seal-entry` and `open-entry`. `format-version` stays 1.
- 0.1 (2026-11-17): First draft. Identifiers, Entry date, times, and the Entry blob. Image and Book record reserved.
