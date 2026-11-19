<div align="center">
  <img src=".github/assets/logo.png" width="144" height="144" alt="Kronoer" />
  <h1>Kronoer</h1>

  <p><strong>A private place to write things down.</strong></p>
</div>

Entries live in **Books**: personal Books stay on your device with no login, shared Books are end-to-end encrypted on the server.

- **Write first, no login.** Login is only needed for sync and shared Books.
- **No password by default.** A PIN or biometrics only unlocks the app; it is never used for encryption.
- **The server cannot read.** Everything on the server is end-to-end encrypted.

Status: pre-MVP. The MVP is Android-only and fully offline.

## Repository

| Folder    | Contents                                          |
| --------- | ------------------------------------------------- |
| `app/`    | Flutter app (Android first)                       |
| `core/`   | Rust core: cryptography and the entry/Book format |
| `spec/`   | Format and protocol specifications                |
| `server/` | Go server (V1)                                    |
| `proto/`  | API definitions (V1)                              |

## Documentation

> [!NOTE]
> Our living documentation (vision, decisions, glossary, epics, stories) is written in a private Notion workspace and cannot be published yet. The Notion links below only open for the maintainers.

The Notion docs start from [Vision & Product](https://app.notion.com/p/419eb5d71fdd813cb5e4d54521ef4b82).
How we work is in the [Working Agreement](https://app.notion.com/p/419eb5d71fdd8160893dfe0949417ba0).

This repo only holds what rarely changes: this summary, [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [SECURITY.md](SECURITY.md), and `spec/`.

## Development

Prerequisites:

- [FVM](https://fvm.app/): Flutter is pinned in `.fvmrc`
- [rustup](https://rustup.rs/): Rust is pinned in `rust-toolchain.toml`
- Android SDK with NDK `28.2.13676358`
- `cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked`

On Windows, also:

- [Strawberry Perl](https://strawberryperl.com/) on `PATH`, for host builds (`cargo test`) that compile the vendored OpenSSL
- [MSYS2](https://www.msys2.org/) in `C:\msys64` with Perl and make (`pacman -S perl make`), for Android builds. OpenSSL's build for Android needs a Unix-style Perl, so the Android build takes Perl and make from there by itself. If MSYS2 is elsewhere, set `MSYS2_ROOT`

Run the app on an emulator or device:

```sh
cd app && fvm flutter run
```

To check the base components against the design, open the component gallery instead of the app (debug builds only):

```sh
cd app && fvm flutter run --dart-define=KRONOER_GALLERY=true
```

Books and Entries are kept in memory for now, so the app starts empty on every launch. To start with sample Books and Entries instead (debug builds only):

```sh
cd app && fvm flutter run --dart-define=KRONOER_SAMPLE=true
```

For dark mode, switch the device to dark (`adb shell cmd uimode night yes`).

After changing `app/rust/src/api/`, regenerate the bindings:

```sh
cd app && flutter_rust_bridge_codegen generate
```

Tests:

```sh
cargo test --workspace
cargo build -p kronoer_bridge && cd app && fvm flutter test
```

## Contributing

Issues are welcome; code pull requests are not accepted yet. See [CONTRIBUTING.md](CONTRIBUTING.md).
Report security problems privately as described in [SECURITY.md](SECURITY.md).

## License

Each folder has its own license:

| Folder                      | License             |
| --------------------------- | ------------------- |
| `core/`, `spec/`            | `MIT OR Apache-2.0` |
| `app/`, `proto/`, `server/` | `AGPL-3.0-only`     |

Third-party code and fonts keep their own licenses, for example `app/rust_builder/cargokit/` and `app/assets/fonts/`.

The Kronoer name and logo are not covered by these licenses. Forks must use a different name and logo.