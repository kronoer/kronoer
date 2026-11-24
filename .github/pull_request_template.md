<!--
Code pull requests from outside the project are not accepted yet; see CONTRIBUTING.md.
Title: a Conventional Commit, e.g. `feat(app): add entry date`.
-->

## What and why

<!-- What changes for the user or the code, and why. Link the issue if there is one. -->

## How it was checked

<!-- Tests run, and for UI: emulator or phone, light and dark, English and Bahasa Indonesia. Screenshots welcome, without private content. -->

## Checklist

- [ ] The title is a Conventional Commit; breaking changes have `!` and say what breaks
- [ ] Tests added or updated, and CI is green
- [ ] UI strings are in `app_en.arb` (with a description) and `app_id.arb`
- [ ] `docs/ARCHITECTURE.md` is updated if the architecture changed
- [ ] No secrets committed: signing keys, passwords, tokens, or `.env` files
- [ ] Test data is made up, never copied from real Entries or Archives (fixed test-vector keys are fine)
- [ ] Screenshots use sample data (`KRONOER_SAMPLE=true`), not real Books or Entries