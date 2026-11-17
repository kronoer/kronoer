import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kronoer/src/theme/system_bars.dart';
import 'package:kronoer/src/ui/gallery.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/licenses.dart';
import 'package:kronoer/src/rust/api/version.dart';
import 'package:kronoer/src/rust/frb_generated.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:vector_graphics/vector_graphics.dart';

const _showGallery = kDebugMode && bool.fromEnvironment('KRONOER_GALLERY');

Future<void> main() async {
  await RustLib.init();
  registerLicenses();
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
      home: _showGallery ? const Gallery() : PlaceholderScreen(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 4,
              children: [
                KIcon(KIcons.calendar),
                KIcon(KIcons.image),
                KIcon(KIcons.lock),
              ],
            ),
            VectorGraphic(
              loader: AssetBytesLoader(
                isDark
                    ? 'assets/brand/wordmark_dark.svg'
                    : 'assets/brand/wordmark.svg',
              ),
              height: 34,
              semanticsLabel: 'Kronoer',
            ),
            Text(AppLocalizations.of(context).tagline, style: text.bodyMedium),
            Text('core ${coreVersion()}'),
          ],
        ),
      ),
    );
  }
}
