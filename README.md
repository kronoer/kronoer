# Kronoer

A private place to write things down. Entries live in **Books**: personal Books stay on your device with no login, shared Books are end-to-end encrypted on the server.

- **Write first, no login.** Login is only needed for sync and shared Books.
- **No password by default.** A PIN or biometrics only unlocks the app; it is never used for encryption.
- **The server cannot read.** Everything on the server is end-to-end encrypted.

Status: pre-MVP. The MVP is Android-only and fully offline.

## Repository

| Folder | Contents |
|---|---|
| `app/` | Flutter app (Android first) |
| `core/` | Rust core: cryptography and the entry/Book format |
| `spec/` | Format and protocol specifications |
| `server/` | Go server (V1) |
| `proto/` | API definitions (V1) |

## Documentation

Living documents (vision, architecture, decisions, glossary, epics, stories) are in Notion, starting from
[Vision & Product](https://app.notion.com/p/419eb5d71fdd813cb5e4d54521ef4b82).
How we work is in the [Working Agreement](https://app.notion.com/p/419eb5d71fdd8160893dfe0949417ba0).

This repo only holds what rarely changes: this summary, [SECURITY.md](SECURITY.md), and `spec/`.
