import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Theme and language as picked in Settings. Kept in memory for now.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void pick(ThemeMode mode) => state = mode;
}

class LanguageNotifier extends Notifier<LanguageChoice> {
  @override
  LanguageChoice build() => LanguageChoice.device;

  void pick(LanguageChoice choice) => state = choice;
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
