# Security

## Model

- Every entry is encrypted on the device with its own key before it is stored or sent anywhere.
- A user's **master key** is random and kept in the Android Keystore. It is never derived from a password. The optional app lock (PIN or biometrics) only guards opening the app.
- A **shared Book** has a versioned **Book key**, wrapped for each member with HPKE. Entries are signed by their author with Ed25519.
- When a member leaves or is removed, the Book key is rotated and only remaining members get the new version.
- The server stores encrypted entries, wrapped keys, and metadata. It never holds a key that can open content.

## Known limits

- **Already-shared entries cannot be revoked.** The official app wipes a removed member's cache, but a modified app can keep what it already downloaded.
- **Metadata is visible to the server:** who writes in which Book, when, and how much.
- **Safety codes are optional.** A member who never compares safety codes could be given a fake key by a malicious server. The app warns when a member's code changes.
- **Export archives are not encrypted.** Anyone with the file can read it.
- **Lost keys mean lost synced data.** If Block Store, every linked device, and the optional recovery key are all gone, synced data cannot be recovered.
- On the device, some metadata (such as entry dates) is readable to anyone who gets past the device lock.

## Reporting a vulnerability

Do not open a public issue. Report it privately, either:

- by email to [moezrd@gmail.com](mailto:moezrd@gmail.com), or
- through GitHub: **Security → Report a vulnerability** on this repository.

Include what is affected, how to reproduce it, and what an attacker could gain. Please give us a chance to fix it before you disclose it publicly.
