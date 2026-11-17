import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/licenses.dart';
import 'package:kronoer/src/rust/frb_generated.dart';
import 'package:kronoer/src/sample/sample_data.dart';
import 'package:material_ui/material_ui.dart';

const _useSample = kDebugMode && bool.fromEnvironment('KRONOER_SAMPLE');

Future<void> main() async {
  await RustLib.init();
  registerLicenses();
  runApp(
    ProviderScope(
      overrides: _useSample ? await sampleOverrides() : const [],
      child: const KronoerApp(),
    ),
  );
}
