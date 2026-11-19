import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/rust/api/version.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/wordmark.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.m,
          children: [
            const Wordmark(),
            Text(l10n.tagline, style: text.bodyMedium),
            Text('core ${coreVersion()}', style: text.bodySmall),
            FilledButton(
              onPressed: () =>
                  ref.read(hasStartedProvider.notifier).markStarted(),
              child: Text(l10n.welcomeStart),
            ),
          ],
        ),
      ),
    );
  }
}
