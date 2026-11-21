import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

String themeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
  ThemeMode.system => l10n.themeSystem,
  ThemeMode.light => l10n.themeLight,
  ThemeMode.dark => l10n.themeDark,
};

/// Each language under its own name, so anyone can find theirs.
String languageLabel(AppLocalizations l10n, LanguageChoice choice) =>
    switch (choice) {
      LanguageChoice.device => l10n.languageDevice,
      LanguageChoice.indonesian => 'Bahasa Indonesia',
      LanguageChoice.english => 'English',
    };

/// Security, appearance, data, and about. Security and data stay disabled
/// until App lock and Export & import.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);

    return Scaffold(
      // A tab: no back button, so the title starts where the Book list's
      // wordmark does.
      appBar: AppBar(titleSpacing: 20, title: Text(l10n.settings)),
      body: ScrollToTopOnReselect(
        child: ListView(
          primary: true,
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            _SectionHeader(l10n.settingsSecurity, first: true),
            _Row(
              icon: KIcons.lock,
              title: l10n.appLock,
              subtitle: l10n.appLockHint,
              trailing: const Switch(value: false, onChanged: null),
            ),
            _Row(title: l10n.lockAgain, subtitle: l10n.lockAgainHint),
            _SectionHeader(l10n.settingsAppearance),
            _Row(
              icon: KIcons.swatchBook,
              title: l10n.theme,
              subtitle: themeLabel(l10n, themeMode),
              onTap: () => context.go(Routes.theme),
            ),
            _Row(
              icon: KIcons.language,
              title: l10n.language,
              subtitle: languageLabel(l10n, language),
              onTap: () => context.go(Routes.language),
            ),
            _SectionHeader(l10n.settingsData),
            _Row(
              icon: KIcons.upload,
              title: l10n.export,
              subtitle: l10n.exportHint,
            ),
            _Row(
              icon: KIcons.download,
              title: l10n.import,
              subtitle: l10n.importHint,
            ),
            _SectionHeader(l10n.settingsAbout),
            _Row(
              icon: KIcons.info,
              title: l10n.aboutKronoer,
              subtitle: l10n.aboutHint,
              onTap: () => context.go(Routes.about),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        first ? Space.s : Space.l,
        Space.xl,
        Space.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// One setting. Without [onTap] it is shown disabled.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final KIcons? icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      enabled: onTap != null,
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
      horizontalTitleGap: Space.l,
      leading: SizedBox.square(
        dimension: 24,
        child: icon == null ? null : KIcon(icon!),
      ),
      iconColor: theme.colorScheme.onSurfaceVariant,
      title: Text(title),
      titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      subtitle: Text(subtitle),
      subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      trailing: trailing,
    );
  }
}

/// A full page of radio rows: a choice applies on tap and the page stays
/// open, showing it; back returns to Settings.
class _ChoicePage<T> extends StatelessWidget {
  const _ChoicePage({
    required this.title,
    required this.value,
    required this.options,
    required this.onPick,
  });

  final String title;
  final T value;

  /// Each option with its label and an optional hint under it.
  final List<(T, String, String?)> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: Text(title)),
      body: RadioGroup<T>(
        groupValue: value,
        onChanged: (picked) {
          if (picked != null) onPick(picked);
        },
        child: ListView(
          padding: const EdgeInsets.only(top: Space.s),
          children: [
            for (final (option, label, hint) in options)
              RadioListTile<T>(
                value: option,
                minTileHeight: 64,
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                title: Text(label, style: theme.textTheme.bodyLarge),
                subtitle: hint == null
                    ? null
                    : Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return _ChoicePage<ThemeMode>(
      title: l10n.theme,
      value: ref.watch(themeModeProvider),
      options: [
        for (final mode in [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
          (mode, themeLabel(l10n, mode), null),
      ],
      onPick: ref.read(themeModeProvider.notifier).pick,
    );
  }
}

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Like the app's own resolution: the first device language Kronoer
    // speaks, else English.
    final deviceLanguage = WidgetsBinding.instance.platformDispatcher.locales
        .map((locale) => locale.languageCode)
        .firstWhere((code) => code == 'id' || code == 'en', orElse: () => 'en');
    final deviceChoice = deviceLanguage == 'id'
        ? LanguageChoice.indonesian
        : LanguageChoice.english;

    return _ChoicePage<LanguageChoice>(
      title: l10n.language,
      value: ref.watch(languageProvider),
      options: [
        for (final choice in LanguageChoice.values)
          (
            choice,
            languageLabel(l10n, choice),
            choice == LanguageChoice.device
                ? languageLabel(l10n, deviceChoice)
                : null,
          ),
      ],
      onPick: ref.read(languageProvider.notifier).pick,
    );
  }
}
