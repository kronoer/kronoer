# Entry format

Status: Draft
Version: 0.1

This document defines how Kronoer stores an Entry: the bytes written on the device and, with sync, sent to the server unchanged. The reference implementation is `core/`.

Images and Book records are only reserved in this version; their sections are filled in by later versions of this document.

## Terminology

- **Entry**: one piece of writing in a Book: plain text plus attached Images.
- **Book**: a named collection of Entries, personal or shared.
- **Image**: a picture attached to an Entry. Reserved in this version.
- **Book key**: the 32-byte secret that opens one Book. Every Book has one. It has a **Book key version**, an unsigned integer starting at 1.
- **Entry key**: the 32-byte random key that protects one sealed Entry. A new Entry key is made every time an Entry is sealed.
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
  images: [],
  created-at: time,
  updated-at: time,
]
```

- `format-version` is the version of the data, not of this document. It is 1 for everything this document defines.
- `book-key-version` names the version of the Book key that sealed the Entry key.
- `sealed-entry-key` is the sealed Entry key: 32 bytes of key and a 16-byte tag.
- `sealed-payload` is the sealed, encoded `entry-payload`, so it is at least 16 bytes.
- `text` is the Entry's plain text, in UTF-8. It MAY be empty. It is stored as written, without Unicode normalization.
- `images` is reserved for references to Images. In this version it MUST be an empty array.
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

1. Checks that the Entry date is valid and that the Entry's Book ID is the Book of the Book key.
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
6. Decodes `entry-payload` with the same strictness as step 1.

If any step fails, the reader MUST stop and MUST NOT return any part of the Entry.

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
| `decryption-failed`   | A tag did not verify: the data was changed, or the key is wrong.         |

## Image

Reserved. A later version of this document defines Image blobs and the references stored in `images`.

## Book record

Reserved. A later version of this document defines the encrypted Book record and how Book keys are created and stored.

## Security considerations

- **Swapped Entries.** The header is authenticated by both encryptions, and a reader checks the Entry ID, Book ID, and Book key version against what it expects. A storage layer or server that hands back another Entry's blob, from the same Book or another, is detected.
- **Older versions.** A storage layer or server can hand back an older blob of the same Entry, and this format does not detect it. The sync protocol has to.
- **Readable metadata.** The header is not encrypted: anyone who holds a blob sees the Entry ID, Book ID, Book key version, and Entry date. The size of `sealed-payload` reveals the approximate length of the text.
- **No signatures.** Anyone who holds a Book key can write a valid Entry for that Book. For a personal Book that is only its owner. Signatures arrive with shared Books.
- **Nonces.** Each Entry key seals one payload, and nonces are 24 random bytes, so nonce reuse is not a practical risk.

## Test vectors

[`test-vectors/entry-format.json`](test-vectors/entry-format.json) holds vectors for this document, following the [test vector conventions](test-vectors/README.md):

- A **seal** vector gives every input, including the Entry key and both nonces, and the expected `header`, `payload` (the encoded `entry-payload` before encryption), and `blob`. Sealing with those inputs MUST produce exactly `blob`, and opening `blob` MUST give back the inputs.
- An **open** vector gives a `blob`, the Book key and its Book ID and version, and the expected Entry ID, and the expected `error` code. Opening MUST fail with that error.

## Changes

- 0.1 (2026-11-17): First draft. Identifiers, Entry date, times, and the Entry blob. Image and Book record reserved.
