import 'package:flutter/services.dart';
import 'package:kronoer/src/theme/system_bars.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/licenses.dart';
import 'package:kronoer/src/rust/api/version.dart';
import 'package:kronoer/src/rust/frb_generated.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';

Future<void> main() async {
  await RustLib.init();
  registerFontLicenses();
  runApp(const KronoerApp());
}

class KronoerApp extends StatelessWidget {
  const KronoerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kronoer',
      theme: buildTheme(lightColorScheme),
      darkTheme: buildTheme(darkColorScheme),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlaceholderScreen(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBarsFor(Theme.of(context).colorScheme),
        child: child!,
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Kronoer', style: text.titleLarge),
            Text(AppLocalizations.of(context).tagline, style: text.bodyMedium),
            Text('core ${coreVersion()}'),
          ],
        ),
      ),
    );
  }
}
