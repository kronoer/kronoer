import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/reminder/reminder_platform.dart';
import 'package:kronoer/src/reminder/writing_reminder.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/trash/trash.dart';
import 'package:kronoer/src/trash/trash_providers.dart';
import 'package:kronoer/src/ui/device_settings_box.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/setting_row.dart';
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

/// A language's name in the app's current language, for under its own name;
/// null when the two are the same.
String? _translatedLanguageName(AppLocalizations l10n, LanguageChoice choice) {
  final translated = switch (choice) {
    LanguageChoice.device => null,
    LanguageChoice.indonesian => l10n.languageNameIndonesian,
    LanguageChoice.english => l10n.languageNameEnglish,
  };
  return translated == languageLabel(l10n, choice) ? null : translated;
}

/// Security, appearance, reminders, data, and about. Export & import stay
/// disabled until their epic; the Trash is under data.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);
    final trashCount = ref.watch(trashProvider).value?.length;
    final trashDays = ref.watch(trashDaysProvider).value ?? defaultTrashDays;

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
            const _AppLockRows(),
            _SectionHeader(l10n.settingsAppearance),
            SettingRow(
              icon: KIcons.swatchBook,
              title: l10n.theme,
              subtitle: themeLabel(l10n, themeMode),
              onTap: () => context.go(Routes.theme),
            ),
            SettingRow(
              icon: KIcons.language,
              title: l10n.language,
              subtitle: languageLabel(l10n, language),
              onTap: () => context.go(Routes.language),
            ),
            _SectionHeader(l10n.settingsReminders),
            const _WritingReminderRows(),
            _SectionHeader(l10n.settingsData),
            SettingRow(
              icon: KIcons.upload,
              title: l10n.export,
              subtitle: l10n.exportHint,
            ),
            SettingRow(
              icon: KIcons.download,
              title: l10n.import,
              subtitle: l10n.importHint,
            ),
            SettingRow(
              icon: KIcons.bin,
              title: l10n.trash,
              subtitle: trashCount == null
                  ? null
                  : l10n.trashSummary(trashCount, trashDays),
              onTap: () => context.go(Routes.trash),
            ),
            _SectionHeader(l10n.settingsAbout),
            SettingRow(
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

/// What "Kunci lagi" says under its row.
String lockAgainHint(AppLocalizations l10n, LockAgain lockAgain) =>
    switch (lockAgain) {
      LockAgain.immediately => l10n.lockAgainImmediatelyHint,
      _ => l10n.lockAgainHint(lockAgain.after.inMinutes),
    };

/// App lock's switch and "Kunci lagi", which is enabled only while App lock
/// is on. Without a screen lock on the device, the switch cannot turn on,
/// and a box says where to set one.
class _AppLockRows extends ConsumerWidget {
  const _AppLockRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lock = ref.watch(appLockProvider);
    final notifier = ref.read(appLockProvider.notifier);
    final canToggle = lock.on || lock.screenLockSet;

    void toggle() => unawaited(
      lock.on
          ? notifier.turnOff(title: l10n.turnOffAppLockPrompt)
          : notifier.turnOn(title: l10n.turnOnAppLockPrompt),
    );

    return Column(
      children: [
        SettingRow(
          icon: KIcons.lock,
          title: l10n.appLock,
          subtitle: l10n.appLockHint,
          trailing: Switch(
            value: lock.on,
            onChanged: canToggle ? (_) => toggle() : null,
          ),
          onTap: canToggle ? toggle : null,
        ),
        if (lock.blocksScreenshots)
          Padding(
            // Lined up with the row titles, as a second hint.
            padding: const EdgeInsetsDirectional.fromSTEB(
              64,
              0,
              Space.xl,
              Space.s,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.appLockScreenshots,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (!canToggle)
          DeviceSettingsBox(
            message: l10n.appLockNoScreenLock,
            onOpen: () {
              notifier.expectOwnTrip();
              unawaited(
                ref.read(appLockPlatformProvider).openSecuritySettings(),
              );
            },
          ),
        SettingRow(
          title: l10n.lockAgain,
          subtitle: lockAgainHint(l10n, lock.lockAgain),
          onTap: lock.on ? () => context.go(Routes.lockAgain) : null,
        ),
      ],
    );
  }
}

/// The Writing reminder's switch, its time, and "Skip if I already wrote".
/// The last two are enabled only while the reminder is on.
class _WritingReminderRows extends ConsumerWidget {
  const _WritingReminderRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reminder = ref.watch(writingReminderProvider);
    final notifier = ref.read(writingReminderProvider.notifier);
    final on = reminder.on;

    void toggle(bool value) =>
        unawaited(value ? notifier.turnOn() : notifier.turnOff());
    void toggleSkip(bool value) => unawaited(notifier.setSkipIfWritten(value));

    Future<void> pickTime() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: reminder.time,
        helpText: l10n.reminderTimeTitle,
      );
      if (picked != null) await notifier.setTime(picked);
    }

    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      reminder.time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return Column(
      children: [
        SettingRow(
          icon: KIcons.bell,
          title: l10n.writingReminder,
          subtitle: l10n.writingReminderHint,
          trailing: Switch(value: on, onChanged: toggle),
          onTap: () => toggle(!on),
        ),
        if (reminder.blocked)
          DeviceSettingsBox(
            message: l10n.notificationsBlocked,
            onOpen: () {
              ref.read(appLockProvider.notifier).expectOwnTrip();
              unawaited(
                ref.read(reminderPlatformProvider).openNotificationSettings(),
              );
            },
          ),
        SettingRow(
          title: l10n.reminderTime,
          subtitle: l10n.reminderTimeHint(time),
          onTap: on ? pickTime : null,
        ),
        SettingRow(
          title: l10n.skipIfWritten,
          subtitle: l10n.skipIfWrittenHint,
          trailing: Switch(
            value: reminder.skipIfWritten,
            onChanged: on ? toggleSkip : null,
          ),
          onTap: on ? () => toggleSkip(!reminder.skipIfWritten) : null,
        ),
      ],
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

/// A full page of radio rows: a choice applies on tap and the page stays
/// open, showing it; back returns to Settings.
class _ChoicePage<T> extends StatelessWidget {
  const _ChoicePage({
    required this.title,
    required this.value,
    required this.options,
    required this.onPick,
    this.note,
  });

  final String title;

  /// A line above the options, saying what the choice does.
  final String? note;
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
            if (note case final note?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xl,
                  Space.s,
                  Space.xl,
                  Space.s,
                ),
                child: Text(
                  note,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final (option, label, hint) in options)
              // Like RadioListTile, but the radio lines up with the label
              // rather than with the label and its hint, as in every
              // Settings row.
              MergeSemantics(
                child: ListTile(
                  onTap: () => onPick(option),
                  minTileHeight: 64,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.l,
                  ),
                  titleTextStyle: theme.textTheme.bodyLarge,
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TitleLine(
                        style: theme.textTheme.bodyLarge!,
                        child: Radio<T>(
                          value: option,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: Space.l),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label),
                            if (hint != null)
                              Text(
                                hint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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
    final deviceChoice = deviceLanguage().languageCode == 'id'
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
                : _translatedLanguageName(l10n, choice),
          ),
      ],
      onPick: ref.read(languageProvider.notifier).pick,
    );
  }
}

/// "Kunci lagi": how long Kronoer may be in the background before App lock
/// asks again.
class LockAgainScreen extends ConsumerWidget {
  const LockAgainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return _ChoicePage<LockAgain>(
      title: l10n.lockAgain,
      note: l10n.lockAgainNote,
      value: ref.watch(appLockProvider.select((lock) => lock.lockAgain)),
      options: [
        for (final option in LockAgain.values)
          option == LockAgain.immediately
              ? (
                  option,
                  l10n.lockAgainImmediately,
                  l10n.lockAgainImmediatelyHint,
                )
              : (option, l10n.lockAgainAfter(option.after.inMinutes), null),
      ],
      onPick: ref.read(appLockProvider.notifier).setLockAgain,
    );
  }
}
