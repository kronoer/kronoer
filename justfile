# Recipes for the Kronoer repository. Run `just` to list them.
# The server has its own, run from here as `just server <recipe>` (see server/justfile).

set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

mod server

_default:
    @just --list

# Run the app on an emulator or device; extra arguments go to `flutter run`
[working-directory('app')]
run *args:
    fvm flutter run {{ args }}

# Run Kronoer Preview
[working-directory('app')]
run-preview *args:
    fvm flutter run --flavor preview {{ args }}

# Run the app on sample Books and Entries, in a throwaway store (debug builds only)
[working-directory('app')]
run-sample:
    fvm flutter run --dart-define=KRONOER_SAMPLE=true

# Open the component gallery instead of the app (debug builds only)
[working-directory('app')]
run-gallery:
    fvm flutter run --dart-define=KRONOER_GALLERY=true

# Switch the connected device to dark mode
dark:
    adb shell cmd uimode night yes

# Switch the connected device to light mode
light:
    adb shell cmd uimode night no

# Regenerate the Dart bindings after changing app/rust/src/api/
[working-directory('app')]
gen:
    flutter_rust_bridge_codegen generate

# Compile the SVGs in app/vectors/ into the .vec files the app bundles
[working-directory('app')]
vectors:
    fvm dart run tool/compile_vectors.dart

# Download the Keyline Icons listed in app/tool/keyline_icons.dart and compile them
[working-directory('app')]
icons:
    fvm dart run tool/keyline_icons.dart
    fvm dart run tool/compile_vectors.dart

# Format Rust and Dart
[working-directory('app')]
fmt:
    cargo fmt --all
    fvm dart format lib test

# Run every test
test: test-rust test-app

# Run the Rust tests
test-rust:
    cargo test --workspace

# Run the Flutter tests, on the Rust core built for this machine
[working-directory('app')]
test-app:
    cargo build -p kronoer_bridge
    fvm flutter test

# Run what CI checks for Rust and the app: formatting, lints, and tests
check: check-rust check-app

# Check Rust: formatting, clippy, and tests
check-rust:
    cargo fmt --all --check
    cargo clippy --workspace --all-targets -- -D warnings
    cargo test --workspace

# Check the app: formatting, analysis, and tests
[working-directory('app')]
check-app:
    cargo build -p kronoer_bridge
    fvm dart format --output=none --set-exit-if-changed lib test
    fvm flutter analyze
    fvm flutter test

# Builds without --flavor are the stable app (default-flavor in pubspec.yaml).

# Build a debug APK into app/build/app/outputs/flutter-apk/
[working-directory('app')]
apk-debug:
    fvm flutter build apk --debug

# Local release builds are signed with the debug key; only the Preview
# release workflow signs with the Preview key.

# Build a release APK for 64-bit ARM phones into app/build/app/outputs/flutter-apk/
[working-directory('app')]
apk-release:
    fvm flutter build apk --release --target-platform android-arm64

# Install the release APK on the connected device, keeping its data
[working-directory('app')]
install-release:
    adb install -r build/app/outputs/flutter-apk/app-stable-release.apk

# Build the Kronoer Preview APKs, one per ABI, into app/build/app/outputs/flutter-apk/
[working-directory('app')]
apk-preview:
    fvm flutter build apk --release --flavor preview --split-per-abi --target-platform android-arm64,android-arm
