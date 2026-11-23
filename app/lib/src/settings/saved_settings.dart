import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kronoer/src/reminder/writing_reminder.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where each setting is saved.
abstract final class _Keys {
  static const themeMode = 'theme_mode';
  static const language = 'language';
  static const hasStarted = 'has_started';
  static const reminderOn = 'writing_reminder';

  /// Minutes after midnight.
  static const reminderTime = 'writing_reminder_time';
  static const reminderSkip = 'writing_reminder_skip';

  /// Milliseconds since the epoch.
  static const lastEntryCreated = 'last_entry_created';
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
    this.writingReminder = const WritingReminder(),
    this.lastEntryCreated,
  });

  final ThemeMode themeMode;
  final LanguageChoice language;

  /// Whether the user has started; null when it was never saved, as on
  /// installs from before it was.
  final bool? hasStarted;

  final WritingReminder writingReminder;

  /// When this device last created an Entry, for the Writing reminder's
  /// "Skip if I already wrote".
  final DateTime? lastEntryCreated;

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
    final minutes = await read(() => preferences.getInt(_Keys.reminderTime));
    final created = await read(
      () => preferences.getInt(_Keys.lastEntryCreated),
    );
    return SavedSettings(
      themeMode: ThemeMode.values.asNameMap()[themeMode] ?? ThemeMode.system,
      language:
          LanguageChoice.values.asNameMap()[language] ?? LanguageChoice.device,
      hasStarted: await read(() => preferences.getBool(_Keys.hasStarted)),
      writingReminder: WritingReminder(
        on: await read(() => preferences.getBool(_Keys.reminderOn)) ?? false,
        time: minutes != null && minutes >= 0 && minutes < 24 * 60
            ? TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60)
            : defaultReminderTime,
        skipIfWritten:
            await read(() => preferences.getBool(_Keys.reminderSkip)) ?? false,
      ),
      lastEntryCreated: created == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(created),
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

Future<void> saveWritingReminder(
  SharedPreferencesAsync preferences,
  WritingReminder reminder,
) async {
  await preferences.setBool(_Keys.reminderOn, reminder.on);
  await preferences.setInt(
    _Keys.reminderTime,
    reminder.time.hour * 60 + reminder.time.minute,
  );
  await preferences.setBool(_Keys.reminderSkip, reminder.skipIfWritten);
}

Future<void> saveLastEntryCreated(
  SharedPreferencesAsync preferences,
  DateTime at,
) => preferences.setInt(_Keys.lastEntryCreated, at.millisecondsSinceEpoch);

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
