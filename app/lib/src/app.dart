import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/system_bars.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The app root: theme, languages and system bars. Which screen shows is up
/// to [routerProvider].
class KronoerApp extends ConsumerWidget {
  const KronoerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Kronoer',
      theme: buildTheme(lightColorScheme),
      darkTheme: buildTheme(darkColorScheme),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBarsFor(Theme.of(context).colorScheme),
        child: child!,
      ),
    );
  }
}
