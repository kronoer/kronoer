import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/export/export.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/banner.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// How long without an Export before the Book list reminds the user.
const exportReminderAfter = Duration(days: 30);

/// How long "Later" hides the reminder.
const exportReminderLaterFor = Duration(days: 7);

/// Why the Book list reminds the user to export.
@immutable
class ExportReminder {
  const ExportReminder({
    required this.exported,
    required this.days,
    required this.newEntryCount,
  });

  /// Whether there has been an Export on this device.
  final bool exported;

  /// How many days since the last Export or, without one, since the first
  /// Entry.
  final int days;

  /// How many Entries were created since the last Export.
  final int newEntryCount;

  @override
  bool operator ==(Object other) =>
      other is ExportReminder &&
      other.exported == exported &&
      other.days == days &&
      other.newEntryCount == newEntryCount;

  @override
  int get hashCode => Object.hash(exported, days, newEntryCount);
}

/// The reminder due at [now], or null: when there has been no Export for
/// [exportReminderAfter] and Entries were created since, counting from the
/// first Entry without any Export, and "Later" ([later]) did not hide it in
/// the last [exportReminderLaterFor].
ExportReminder? exportReminderAt(
  DateTime now, {
  required DateTime? lastExport,
  required ExportActivity activity,
  DateTime? later,
}) {
  if (later != null && now.isBefore(later.add(exportReminderLaterFor))) {
    return null;
  }
  final from = lastExport ?? activity.firstCreated;
  if (from == null || activity.createdSince == 0) return null;
  final waited = now.difference(from);
  if (waited < exportReminderAfter) return null;
  return ExportReminder(
    exported: lastExport != null,
    days: waited.inDays,
    newEntryCount: activity.createdSince,
  );
}

/// The Entries an Export would write, since the last Export.
final exportActivityProvider = StreamProvider<ExportActivity>(
  (ref) => ref
      .watch(entryRepositoryProvider)
      .watchExportActivity(since: ref.watch(lastExportProvider)),
);

/// When "Later" last hid the reminder to export; saved on this device only.
class ExportReminderLaterNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => ref.read(savedSettingsProvider).exportReminderLater;

  /// "Later": hides the reminder for [exportReminderLaterFor].
  void later() {
    final now = ref.read(clockProvider)();
    state = now;
    savePreference(
      ref,
      (preferences) => saveExportReminderLater(preferences, now),
    );
  }
}

final exportReminderLaterProvider =
    NotifierProvider<ExportReminderLaterNotifier, DateTime?>(
      ExportReminderLaterNotifier.new,
    );

/// The reminder the Book list shows now, or null.
final exportReminderProvider = Provider<ExportReminder?>((ref) {
  final activity = ref.watch(exportActivityProvider).value;
  if (activity == null) return null;
  return exportReminderAt(
    ref.watch(clockProvider)(),
    lastExport: ref.watch(lastExportProvider),
    activity: activity,
    later: ref.watch(exportReminderLaterProvider),
  );
});

/// The Book list's reminder to export: "Export" opens the export page, "Later"
/// hides it for [exportReminderLaterFor].
class ExportReminderBanner extends ConsumerWidget {
  const ExportReminderBanner(this.reminder, {super.key});

  final ExportReminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return KBanner(
      icon: KIcons.download,
      title: reminder.exported
          ? l10n.exportReminderTitle(reminder.days)
          : l10n.exportReminderNeverTitle,
      message: reminder.exported
          ? l10n.exportReminderText(reminder.newEntryCount)
          : l10n.exportReminderNeverText(reminder.days),
      dismissLabel: l10n.exportReminderLater,
      onDismiss: ref.read(exportReminderLaterProvider.notifier).later,
      actionLabel: l10n.exportReminderExport,
      onAction: () => context.go(Routes.bookListExport),
    );
  }
}
