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

| Data                    | Where                                                                        | Login |
| ----------------------- | ---------------------------------------------------------------------------- | ----- |
| Personal Book (default) | Device: SQLite metadata + per-entry encrypted content, encrypted image files | No    |
| Personal Book with sync | Device + server, same encrypted blobs                                        | Yes   |
| Shared Book             | Server is the source of truth; devices keep a cache                          | Yes   |

- Local and server use **the same per-entry encrypted format**, so sync uploads blobs as they are.
- No Google Drive backup. Users without sync are protected by export & import.
- Export is an unencrypted archive (text, dates, images, Book names) with a clear warning.

## Cryptography

- **Master key:** random, stored in Android Keystore (iOS Keychain later). Never derived from a password.
- **Entry key:** random per entry; encrypts the text and images, then is sealed with the master key (personal) or the Book key (shared).
- **Book key:** symmetric key of a shared Book, versioned. Wrapped for each member with HPKE (X25519, HKDF-SHA256, AES-256-GCM).
- **Entry signature:** Ed25519 by the author over all entry fields. Every edit is re-signed.
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
