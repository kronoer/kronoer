import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's language: the device's, or one picked in Settings.
enum LanguageChoice {
  device(null),
  indonesian(Locale('id')),
  english(Locale('en'));

  const LanguageChoice(this.locale);

  /// Null follows the device.
  final Locale? locale;
}

/// The device's language as the app resolves it: the first device language
/// Kronoer speaks, else English.
Locale deviceLanguage() {
  final code = WidgetsBinding.instance.platformDispatcher.locales
      .map((locale) => locale.languageCode)
      .firstWhere((code) => code == 'id' || code == 'en', orElse: () => 'en');
  return Locale(code);
}

/// The theme picked in Settings, saved on the device.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(savedSettingsProvider).themeMode;

  void pick(ThemeMode mode) {
    state = mode;
    savePreference(ref, (preferences) => saveThemeMode(preferences, mode));
  }
}

/// The language picked in Settings, saved on the device.
class LanguageNotifier extends Notifier<LanguageChoice> {
  @override
  LanguageChoice build() => ref.read(savedSettingsProvider).language;

  void pick(LanguageChoice choice) {
    state = choice;
    savePreference(ref, (preferences) => saveLanguage(preferences, choice));
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

final languageProvider = NotifierProvider<LanguageNotifier, LanguageChoice>(
  LanguageNotifier.new,
);

/// The app's version and build number, from the platform.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
