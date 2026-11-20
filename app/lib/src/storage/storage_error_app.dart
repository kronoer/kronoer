import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:material_ui/material_ui.dart';

/// The whole app when the store could not be opened at launch. It offers no
/// way forward on purpose: nothing may be created, and nothing is deleted.
class StorageErrorApp extends StatelessWidget {
  const StorageErrorApp({this.settings = const SavedSettings(), super.key});

  /// The theme and language chosen in Settings, which still apply.
  final SavedSettings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kronoer',
      theme: buildTheme(lightColorScheme),
      darkTheme: buildTheme(darkColorScheme),
      themeMode: settings.themeMode,
      locale: settings.language.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _StorageErrorScreen(),
    );
  }
}

class _StorageErrorScreen extends StatelessWidget {
  const _StorageErrorScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: EmptyState(
          title: l10n.storageErrorTitle,
          message: l10n.storageErrorMessage,
        ),
      ),
    );
  }
}
