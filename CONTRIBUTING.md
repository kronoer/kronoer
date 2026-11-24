# Contributing

Kronoer is built in the open, but it does not accept code contributions yet.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Issues

Bug reports and ideas are welcome as [GitHub issues](https://github.com/kronoer/kronoer/issues)

Never report a security problem in a public issue. Follow [SECURITY.md](SECURITY.md) instead.

## Pull requests

Pull requests with code are closed without review for now.

The app is licensed under AGPL-3.0. To keep the option of distributing it under other terms, for example in app stores, the maintainers need to hold the rights to all of its code. Outside code will be accepted once a contributor agreement is in place; this file will say so when that happens.

## Branches

Branch names start with the type of change, then a short title in kebab case: `type/short-title`, for example `feat/entry-date` or `fix/export-progress`. The types are the same as for commit messages.

## Commit messages

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`, for example `feat(app): add entry date`.

- **Type:** `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, or `chore`.
- **Scope** (optional): the folder the change is in, such as `app`, `core`, `spec`, `server`, `proto`, or `docs`.
- **Breaking change:** a `!` after the type or scope, for example `refactor(core)!: …`, and a `BREAKING CHANGE:` footer saying what breaks and what to do about it.
- The summary is in English, in the imperative, without a full stop at the end.
