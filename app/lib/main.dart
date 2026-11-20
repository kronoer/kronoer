import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/licenses.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/rust/frb_generated.dart';
import 'package:kronoer/src/sample/sample_data.dart';
import 'package:kronoer/src/storage/core_repository.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/storage/storage_error_app.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

const _useSample = kDebugMode && bool.fromEnvironment('KRONOER_SAMPLE');

Future<void> main() async {
  await RustLib.init();
  registerLicenses();

  if (_useSample) {
    runApp(
      ProviderScope(
        overrides: await sampleOverrides(),
        child: const KronoerApp(),
      ),
    );
    return;
  }

  final CoreStore store;
  final bool hasBooks;
  try {
    store = await openDeviceStore();
    hasBooks = (await store.listBooks()).isNotEmpty;
  } on StoreFailure catch (failure) {
    // Never fall back to a new, empty store: the old one may still open later.
    debugPrint('Store did not open: ${failure.kind.name}: ${failure.message}');
    runApp(const StorageErrorApp());
    return;
  }

  final repository = CoreRepository(store);
  runApp(
    ProviderScope(
      overrides: [
        bookRepositoryProvider.overrideWithValue(repository),
        entryRepositoryProvider.overrideWithValue(repository),
        searchRepositoryProvider.overrideWithValue(repository),
        hasStartedProvider.overrideWith(() => HasStartedNotifier(hasBooks)),
      ],
      child: const KronoerApp(),
    ),
  );
}
