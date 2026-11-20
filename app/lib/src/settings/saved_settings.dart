import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kronoer/src/settings/settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where each setting is saved.
abstract final class _Keys {
  static const themeMode = 'theme_mode';
  static const language = 'language';
  static const hasStarted = 'has_started';
}

/// The settings saved on the device, read once before the first frame so the
/// app starts in the chosen theme and language.
///
/// They live in `shared_preferences`, not in the core's database: they are
/// not secret, and the storage error screen, shown when the database does not
/// open, follows them too.
@immutable
class SavedSettings {
  const SavedSettings({
    this.themeMode = ThemeMode.system,
    this.language = LanguageChoice.device,
    this.hasStarted,
  });

  final ThemeMode themeMode;
  final LanguageChoice language;

  /// Whether the user has started; null when it was never saved, as on
  /// installs from before it was.
  final bool? hasStarted;

  /// Reads every setting. A missing, unknown, or unreadable value is the
  /// default.
  static Future<SavedSettings> load(SharedPreferencesAsync preferences) async {
    Future<T?> read<T>(Future<T?> Function() get) async {
      try {
        return await get();
      } on Object catch (error) {
        debugPrint('A saved setting could not be read: $error');
        return null;
      }
    }

    final themeMode = await read(() => preferences.getString(_Keys.themeMode));
    final language = await read(() => preferences.getString(_Keys.language));
    return SavedSettings(
      themeMode: ThemeMode.values.asNameMap()[themeMode] ?? ThemeMode.system,
      language:
          LanguageChoice.values.asNameMap()[language] ?? LanguageChoice.device,
      hasStarted: await read(() => preferences.getBool(_Keys.hasStarted)),
    );
  }

  /// The providers that start from these settings and save changes to
  /// [preferences].
  List<Override> overrides(SharedPreferencesAsync preferences) => [
    preferencesProvider.overrideWithValue(preferences),
    savedSettingsProvider.overrideWithValue(this),
  ];
}

/// Where settings are saved; null saves nothing, as in tests and the gallery.
final preferencesProvider = Provider<SharedPreferencesAsync?>((ref) => null);

/// The settings as saved when the app started.
final savedSettingsProvider = Provider<SavedSettings>(
  (ref) => const SavedSettings(),
);

/// Saves in the background. A failed save only means the choice is not
/// remembered next time, so it is logged, not shown.
void savePreference(
  Ref ref,
  Future<void> Function(SharedPreferencesAsync preferences) write,
) {
  final preferences = ref.read(preferencesProvider);
  if (preferences == null) return;
  unawaited(
    write(preferences).catchError((Object error) {
      debugPrint('A setting could not be saved: $error');
    }),
  );
}

Future<void> saveThemeMode(
  SharedPreferencesAsync preferences,
  ThemeMode mode,
) => preferences.setString(_Keys.themeMode, mode.name);

Future<void> saveLanguage(
  SharedPreferencesAsync preferences,
  LanguageChoice choice,
) => preferences.setString(_Keys.language, choice.name);

Future<void> saveHasStarted(SharedPreferencesAsync preferences) =>
    preferences.setBool(_Keys.hasStarted, true);

/// Whether the user has started, at launch: as saved, or on an install from
/// before it was saved, whether any Book exists, which is then saved.
Future<bool> hasStartedAtLaunch(
  SharedPreferencesAsync preferences,
  SavedSettings saved, {
  required bool hasBooks,
}) async {
  if (saved.hasStarted case final started?) return started;
  if (!hasBooks) return false;
  try {
    await saveHasStarted(preferences);
  } on Object catch (error) {
    debugPrint('A setting could not be saved: $error');
  }
  return true;
}
