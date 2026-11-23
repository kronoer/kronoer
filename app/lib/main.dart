import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/launch.dart';
import 'package:kronoer/src/licenses.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/reminder/reminder_platform.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/rust/frb_generated.dart';
import 'package:kronoer/src/sample/sample_data.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/storage/storage_error_app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _useSample = kDebugMode && bool.fromEnvironment('KRONOER_SAMPLE');

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
          ...await sampleOverrides(),
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

/// The device behind the Writing reminder and App lock; tests leave them out.
final _devicePlatforms = [
  reminderPlatformProvider.overrideWithValue(const AndroidReminderPlatform()),
  appLockPlatformProvider.overrideWithValue(const AndroidAppLockPlatform()),
];
