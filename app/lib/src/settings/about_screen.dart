import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/preview.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/rust/api/version.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/wordmark.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// The launcher icon, or the Preview's in Kronoer Preview.
class AppIcon extends ConsumerWidget {
  const AppIcon({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ExcludeSemantics(
    child: VectorGraphic(
      loader: AssetBytesLoader(
        ref.watch(isPreviewProvider)
            ? 'assets/brand/app_icon_preview.vec'
            : 'assets/brand/app_icon.vec',
      ),
      width: size,
      height: size,
    ),
  );
}

/// The version, the privacy note, and the way to the open source licenses.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final info = ref.watch(packageInfoProvider).value;
    final isPreview = ref.watch(isPreviewProvider);
    final paragraph = theme.textTheme.bodyMedium?.copyWith(color: muted);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: Text(l10n.aboutKronoer)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, Space.l, 32, Space.xl),
        children: [
          const Center(child: AppIcon()),
          const SizedBox(height: Space.s),
          const Center(child: Wordmark(height: 36)),
          const SizedBox(height: Space.s),
          Text(
            switch (info) {
              null => '',
              // A Preview's build number is per ABI, so only its version.
              _ when isPreview => '$previewName ${info.version}',
              _ => l10n.version(info.version, info.buildNumber),
            },
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
            textAlign: TextAlign.center,
          ),
          Text(
            'core ${coreVersion()}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Row(
                spacing: Space.m,
                children: [
                  KIcon(KIcons.lock, color: theme.colorScheme.primary),
                  Expanded(
                    child: Text(
                      l10n.privacyNote,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.l),
          Text(l10n.aboutText, style: paragraph, textAlign: TextAlign.center),
          const SizedBox(height: Space.m),
          Text(
            l10n.openSourceText,
            style: paragraph,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s),
          Center(
            child: TextButton(
              onPressed: () => context.go(Routes.licenses),
              child: Text(l10n.licenses),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every bundled license: the fonts' OFL texts, the Keyline notice, and the
/// packages'.
class LicensesScreen extends ConsumerWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(packageInfoProvider).value;

    return LicensePage(
      applicationName: ref.watch(isPreviewProvider) ? previewName : 'Kronoer',
      applicationVersion: info?.version,
      applicationIcon: const Padding(
        padding: EdgeInsets.all(Space.s),
        child: AppIcon(size: 48),
      ),
    );
  }
}
