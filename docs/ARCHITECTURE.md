# Architecture

The components of Kronoer, where data lives, and how it is encrypted. This file is the source of truth for the architecture; change it in the same pull request as the code it describes.

## Components

| Component      | Technology                         | Role                                             | Phase |
| -------------- | ---------------------------------- | ------------------------------------------------ | ----- |
| App            | Flutter (Android first)            | UI, local storage, i18n                          | MVP   |
| Core           | Rust via flutter_rust_bridge       | All cryptography and the entry/Book format       | MVP   |
| Server         | Go (Connect-RPC, pgx, sqlc, goose) | Auth, sync, shared Books, key distribution, push | V1    |
| Database       | PostgreSQL                         | Metadata, wrapped keys, encrypted entries        | V1    |
| Object storage | S3-compatible                      | Encrypted images, uploaded via presigned URLs    | V1    |

The server never holds a key that can open content.

## Repository

Public monorepo. Folders: `app/`, `core/`, `spec/`, `server/`, `proto/`.

Licenses: `core/` and `spec/` are `MIT OR Apache-2.0`; `app/` and `proto/` are `AGPL-3.0-only`; the server's license is decided when the server is built (V1).

## Storage

| Data                    | Where                                                                          | Login |
| ----------------------- | ------------------------------------------------------------------------------ | ----- |
| Personal Book (default) | Device: SQLCipher database of per-entry encrypted blobs, encrypted image files | No    |
| Personal Book with sync | Device + server, same encrypted blobs                                          | Yes   |
| Shared Book             | Server is the source of truth; devices keep a cache                            | Yes   |

- Local and server use **the same per-entry encrypted format**, so sync uploads blobs as they are.
- No Google Drive backup. Users without sync are protected by export & import.
- Export is an unencrypted archive (text, dates, images, Book names) with a clear warning.

### On the device

The core owns local storage (`kronoer_core::store`); the app reaches it through `kronoer_bridge` and sends and receives only plaintext content and IDs.

- **One SQLCipher database** (`rusqlite` with bundled SQLCipher and vendored OpenSSL), opened with the `kronoer/v1/sqlcipher` subkey as a raw key and SQLCipher 4's cipher settings pinned, in WAL mode. The schema version is `PRAGMA user_version`; the core runs migrations when it opens the database and refuses a newer one.
- **Tables:** `book` (name, last activity, sealed Book record), `book_key` (wrapped Book keys by version), `entry` (header fields, created and updated times, sealed blob), `entry_image` (Images of each Entry, in order), and `entry_search` (FTS5, `unicode61 remove_diacritics 2`, keeps the text for snippets and list previews).
- **The blobs are the data.** Every plaintext column and the search index are written in the same transaction as the blob, and `rebuild_index` rebuilds them from the blobs.
- **Images** are files named `<Image ID>.full` and `<Image ID>.thumb`, each one sealed Image blob. A save writes new files atomically (temporary file, sync, rename) before its transaction and deletes them if the transaction fails. A delete removes rows first and files after. At open, files no Entry refers to and older than one hour are removed.
- **Order and search:** Entries are listed and searched by Entry date as written (local time), newest first, paged by date and ID. Search matches every typed word as a word prefix, with or without diacritics, and returns snippets and the match count per Book.
- **Keys:** a `Keyring` holds the master key and the Book keys unwrapped so far; Dart holds it only as an opaque handle. Every commit fires a change event that the app can watch.

## App

- Feature folders under `app/lib/src/`: `books/`, `entries/`, `settings/`, `welcome/`, shared `ui/` and `theme/`, and `storage/`.
- Navigation: go_router. Every screen has a path, so deep links build the same back stack.
- State: Riverpod without code generation.
- Screens reach data only through the `BookRepository` and `EntryRepository` providers. Until the master key is kept in Android Keystore, `InMemoryStore` implements both and loses everything when the app closes; the core's store (`CoreStore` in the bridge) replaces it behind the same interfaces. IDs are opaque strings of 32 hexadecimal digits, created by the core (`newId()`).

## Cryptography

The format is defined in `spec/entry-format.md`, with test vectors in `spec/test-vectors/`. Everything is encoded as deterministic CBOR and encrypted with XChaCha20-Poly1305.

- **Master key:** random, stored in Android Keystore (iOS Keychain later). Never derived from a password. It never encrypts anything itself: HKDF-SHA256 derives one subkey per purpose (`kronoer/v1/book-key-wrap`, and `kronoer/v1/sqlcipher` for the local database).
- **Book key:** random and versioned; every Book has one, personal Books too. In a personal Book it is wrapped with the `book-key-wrap` subkey; in a shared Book it is also wrapped for each member with HPKE (V1).
- **Book record:** the Book's name, sealed with the Book key. Its header (format version, Book ID, Book key version) stays readable and is bound to the encryption as associated data, like the wrapped Book key's.
- **Entry key:** random and new on every save; encrypts the Entry's text, then is sealed with the Book key. The header (format version, Entry and Book IDs, Book key version, Entry date) stays readable and is bound to both encryptions as associated data.
- **Image key:** random per Image, kept while the Image stays attached. It seals two blobs, the full image and a thumbnail; the Entry's encrypted payload holds the key and the SHA-256 hash of each blob, so a swapped or changed blob is rejected before decryption.
- **Open keys stay in the core:** keys are wiped from memory when dropped, and Dart only handles encrypted blobs and plaintext content.
- **Entry signature (V1):** Ed25519 by the author over all entry fields, added with shared Books. Every edit is re-signed.
- **Key rotation:** a new Book key version is created when a member leaves or is removed.
- **Safety code:** fingerprint of a member's identity key. Comparing it is optional; the app warns when it changes.

## Accounts & devices (V1)

- Login: Google and passkey. Sign in with Apple arrives with iOS. No email/password.
- Moving or adding a device: Block Store restore, QR link from an existing device, or an optional printable recovery key. If all three are lost, synced data cannot be recovered.
- Push notifications for shared Books carry no content; the Book name is filled in on the device.

## Accepted security limits

- Entries already shared cannot be pulled back from a former member's device. The official app wipes its cache on removal; a modified app can keep it.
- The server sees metadata: who writes, when, and sizes.
- A member who never compares safety codes can be fooled by a malicious server inserting a fake key.
