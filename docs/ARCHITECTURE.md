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

Licenses: `core/` and `spec/` are `MIT OR Apache-2.0`; `app/`, `proto/`, and `server/` are `AGPL-3.0-only`.

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
- **Order and search:** Entries are listed and searched by Entry date as written (local time), newest first, paged by date and ID, within one Book (`list_entries`) or across all of them for the Timeline (`list_all_entries`). Search matches every typed word as a word prefix, with or without diacritics, and returns snippets and the match count per Book. `match_ranges` finds the matching words in one text with the index's own tokenizer, in a throwaway in-memory database, so the read view marks exactly what the search matched.
- **Keys:** a `Keyring` holds the master key and the Book keys unwrapped so far; Dart holds it only as an opaque handle. Every commit fires a change event that the app can watch.
- **Master key on Android:** the master key file `no_backup/master-key` (CBOR `[version, wrapped key]`, written atomically) holds the master key wrapped with AES-256-GCM by a non-exportable Android Keystore key (`kronoer-master-key-wrap-v1`, no user authentication or unlock condition). The core calls Keystore through JNI behind the `MasterKeyStore` trait; Kotlin's `KronoerApplication` hands it the JVM and the app's directories at process start. The database and Images live in `files/store/`. At open, the core tells apart "no master key file" from "cannot unwrap it": it makes a new master key only when neither the key file nor the database exists, and never writes or deletes anything when opening fails.
- **No Android backup:** `allowBackup` is off and the data extraction rules exclude everything from cloud backup and device transfer; the wrapped master key could not be unwrapped on another device anyway.

## App

- Feature folders under `app/lib/src/`: `home/`, `books/`, `entries/`, `timeline/`, `search/`, `settings/`, `welcome/`, shared `ui/` and `theme/`, and `storage/`.
- Navigation: go_router. Every screen has a path, so deep links build the same back stack. A `StatefulShellRoute` holds three tabs behind a bottom navigation (`home/home_shell.dart`): the Book list (`/`), the Timeline (`/timeline`), and Settings (`/settings`). Each tab has its own navigator, so it keeps its screen and scroll position; every other screen is on the root navigator, over the bar. The app always opens on the Book tab, and back from another tab goes to it. The Timeline pushes the screens it opens (an Entry, search), so back returns to it. The read view likewise pushes the editor and the Image viewer, which close back to it, and deleting an Entry closes its screens back to whichever screen opened it.
- State: Riverpod without code generation.
- Screens reach data only through the `BookRepository`, `EntryRepository`, and `SearchRepository` providers. `CoreRepository` implements all three over the core's store (`CoreStore` in the bridge), which `main.dart` opens before the first frame; every watch reads again after each change event. If the store does not open, the app shows only an error screen and creates nothing. `InMemoryStore` remains for tests and has no search. The debug sample data (`KRONOER_SAMPLE`) is seeded into a core store in a new temporary folder with a master key that is never kept. IDs are opaque strings of 32 hexadecimal digits, created by the core (`newId()`).
- Search screens (all Books, one Book) take their query from the path, search once typing pauses, and ignore an answer that arrives after a newer one was asked. Results across all Books are grouped in Book list order, a few per Book. The field never lets the keyboard learn what is typed.
- Deleting an Entry offers undo: the Entry is hidden at once (`pendingDeletionsProvider`) and deleted from the repository only when the "Urungkan" snackbar closes, because a deleted Entry cannot be stored again with its ID and Images. If the app stops first, the Entry stays.
- The editor saves as the user types (after a short pause, and when leaving or going to the background); an Entry with no text and no Images is discarded when the editor closes.
- Images: "Selipkan foto" takes photos from the Android photo picker (several at once, never more than the 20 an Entry holds) or the camera app, through `image_picker`, so the app asks for no storage or camera permission. Each photo is decoded by the platform's decoder (anything the device reads, HEIC included), turned upright by its EXIF orientation, and encoded again from its pixels alone, so no metadata survives (EXIF with GPS location, XMP, IPTC): the full image at most 2048 px on its longest side, JPEG quality 85, and the thumbnail at most 512 px, quality 80; neither is ever scaled up. Decoding runs on the engine's threads and encoding in a separate isolate. The file the picker or camera wrote is deleted once the photo is prepared. A save sends new Images with their bytes and keeps existing ones by ID, so editing the text does not rewrite Image blobs. Cards and the editor show thumbnails; the read view and the viewer show the full image. Decrypted bytes never touch the disk: `EntryImageProvider` reads them from the repository and Flutter's in-memory image cache keeps the decoded images, so scrolling back does not open a blob again. An Image that does not open shows a broken-image placeholder.
- Settings live in `shared_preferences` (`SharedPreferencesAsync`), not in the core's database: `theme_mode`, `language`, and `has_started`. `main.dart` reads them before the first frame, so the app and the storage error screen start in the chosen theme and language; a missing or unknown value is the default. A change is saved in the background as it is picked. `has_started` is saved when Welcome creates the first Book; an install without it that already has a Book counts as started and saves it, so deleting the last Book later shows the empty Book list, not Welcome. Like the store, settings are excluded from Android backup.
- Vector graphics (icons, brand, illustrations) are SVG sources in `app/vectors/`, compiled once by `tool/compile_vectors.dart` into the committed `.vec` files the app bundles from `app/assets/`. Flutter's asset transformers are not used: they start one compiler process per SVG on every asset build, which exhausted memory.

## Server

- One Go module in `server/`; the binary is `cmd/kronoerserver` with `serve` and `migrate`. Migrations never run on startup.
- Packages under `internal/` are by feature (`serverinfo/`, later `account/`, `sync/`, `sharing/`); shared technical code lives in `internal/platform/`; generated code in `internal/gen/` is committed.
- API: Connect-RPC from `proto/` (packages `kronoer.<area>.v1`), served over HTTP/1.1 and unencrypted HTTP/2 behind a TLS proxy. Health uses the standard gRPC health service.
- Schema: goose migrations in `db/migrations/`, embedded in the binary.
- Object storage is reached through the S3 API only (AWS SDK for Go v2); any S3-compatible service works.
- Settings come only from `KRONOER_` environment variables. Logs never include blob contents.
- The server checks each Entry's readable header with its own Go parser, tested against `spec/test-vectors/`, and never touches the encrypted parts.
- Local development: PostgreSQL and RustFS from `server/compose.yaml`; recipes in `server/justfile`.

## Cryptography

The format is defined in `spec/entry-format.md`, with test vectors in `spec/test-vectors/`. Everything is encoded as deterministic CBOR and encrypted with XChaCha20-Poly1305.

- **Master key:** random, kept wrapped by an Android Keystore key (iOS Keychain later). Never derived from a password. It never encrypts anything itself: HKDF-SHA256 derives one subkey per purpose (`kronoer/v1/book-key-wrap`, and `kronoer/v1/sqlcipher` for the local database).
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
