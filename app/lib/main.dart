import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/export/export_platform.dart';
import 'package:kronoer/src/import/import_platform.dart';
import 'package:kronoer/src/launch.dart';
import 'package:kronoer/src/licenses.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/reminder/reminder_platform.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/rust/frb_generated.dart';
import 'package:kronoer/src/sample/sample_data.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/storage/storage_error_app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `true` for the sample Books, `empty` for an empty sample store at Welcome.
const _sample = kDebugMode ? String.fromEnvironment('KRONOER_SAMPLE') : '';
const _useSample = _sample == 'true' || _sample == 'empty';

/// With the sample Books: how many days ahead the app's clock runs, to see
/// what shows only after a while, such as the reminder to export.
const _clockDays = kDebugMode ? int.fromEnvironment('KRONOER_CLOCK_DAYS') : 0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  registerLicenses();

  // Read before the first frame, so the app starts in the chosen theme and
  // language.
  final preferences = SharedPreferencesAsync();
  final saved = await SavedSettings.load(preferences);

  if (_useSample) {
    runApp(
      ProviderScope(
        overrides: [
          ...saved.overrides(preferences),
          ...await sampleOverrides(empty: _sample == 'empty'),
          if (_clockDays != 0)
            clockProvider.overrideWithValue(
              () => DateTime.now().add(const Duration(days: _clockDays)),
            ),
          ..._devicePlatforms,
        ],
        child: const KronoerApp(),
      ),
    );
    return;
  }

  final List<Override> overrides;
  try {
    overrides = await launchOverrides(
      store: await openDeviceStore(),
      preferences: preferences,
      saved: saved,
    );
  } on StoreFailure catch (failure) {
    // Never fall back to a new, empty store: the old one may still open later.
    debugPrint('Store did not open: ${failure.kind.name}: ${failure.message}');
    runApp(StorageErrorApp(settings: saved));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [...overrides, ..._devicePlatforms],
      child: const KronoerApp(),
    ),
  );
}

/// The device behind the Writing reminder, App lock, Export, and Import;
/// tests leave them out.
final _devicePlatforms = [
  reminderPlatformProvider.overrideWithValue(const AndroidReminderPlatform()),
  appLockPlatformProvider.overrideWithValue(const AndroidAppLockPlatform()),
  exportPlatformProvider.overrideWithValue(const AndroidExportPlatform()),
  importPlatformProvider.overrideWithValue(const AndroidImportPlatform()),
];
