import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:kronoer/src/rust/frb_generated.dart';

/// The bridge library built for the host by `cargo build -p kronoer_bridge`.
String _hostLibraryPath() {
  final name = Platform.isWindows
      ? 'kronoer_bridge.dll'
      : Platform.isMacOS
      ? 'libkronoer_bridge.dylib'
      : 'libkronoer_bridge.so';
  return '../target/debug/$name';
}

/// Loads the Rust core once for every test file: IDs and storage come from it.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await RustLib.init(externalLibrary: ExternalLibrary.open(_hostLibraryPath()));
  await testMain();
}
