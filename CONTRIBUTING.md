# Contributing

Kronoer is built in the open, and contributions from anyone are welcome.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Issues

Bug reports and ideas are welcome as [GitHub issues](https://github.com/kronoer/kronoer/issues)

Never report a security problem in a public issue. Follow [SECURITY.md](SECURITY.md) instead.

## Pull requests

Pull requests are welcome from anyone.

- For anything bigger than a small fix, open an issue first so we can agree on the approach before you write the code.
- Keep a pull request to one change, and fill in the template.
- A change people using Kronoer will notice adds a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md), in the same pull request. Write it for them, in plain words, under Added, Changed, Fixed, Removed, or Security.
- Your contribution is licensed under the license of the folder it goes into, as listed in [LICENSING.md](LICENSING.md): AGPL-3.0-only for most of the repository, MIT OR Apache-2.0 for `core/` and `spec/`. Only submit code you have the right to contribute.

## Branches

Branch names start with the type of change, then a short title in kebab case: `type/short-title`, for example `feat/entry-date` or `fix/export-progress`. The types are the same as for commit messages.

## Commit messages

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`, for example `feat(app): add entry date`.

- **Type:** `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, or `chore`.
- **Scope** (optional): the folder the change is in, such as `app`, `core`, `spec`, `server`, `proto`, or `docs`.
- **Breaking change:** a `!` after the type or scope, for example `refactor(core)!: …`, and a `BREAKING CHANGE:` footer saying what breaks and what to do about it.
- The summary is in English, in the imperative, without a full stop at the end.
