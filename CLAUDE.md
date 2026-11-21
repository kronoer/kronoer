# Kronoer

Follow the [Working Agreement](https://app.notion.com/p/419eb5d71fdd8160893dfe0949417ba0) in Notion (workspace "Kronoer"). Key points:

- **English everywhere**: docs, code, identifiers, commits. Only UI strings are translated (i18n): English is the source language (`app_en.arb` is the template and holds every string's description), Indonesian a translation. Indonesian devices get Indonesian; English is the fallback for every other device language.
- **Docs live in Notion**, not here: ADR, Glossary, Epic, Story, Research. The exception is architecture: `docs/ARCHITECTURE.md` is its source of truth, updated in the same PR as the code it describes. Never add `docs/adr/`, `GLOSSARY.md`, roadmaps, or backlogs to the repo.
- **Use the Notion Glossary's terms** in code and writing. In particular: the unit of content is an **Entry**; the container is a **Book** (personal or shared). There are no entry categories (no diary/journal/memo types). "Memory"/"kenangan" is marketing-only.
- **ADR only if** hard to reverse, surprising without context, and a real trade-off.
- **Branches** `KRO-12-short-title`; commits mention the story code.

## Layout

- `app/` Flutter (Android first)
- `core/` Rust: all cryptography and the entry/Book format
- `spec/` format and protocol specs
- `server/`, `proto/` Go server and API (V1)
- `docs/` architecture only (`ARCHITECTURE.md`)

## Non-negotiables

- No password by default; app lock never feeds into encryption.
- The server must never receive a key that can open content.
- Local storage and the server use the same per-entry encrypted format.
