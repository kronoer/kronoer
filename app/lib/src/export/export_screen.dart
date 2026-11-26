import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/export/archive_page.dart';
import 'package:kronoer/src/export/export.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/lock/book_lock.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// "Export data": warns that the Archive will not be encrypted, then writes
/// every Book into one at the place the user picks, with its progress and
/// "Cancel". A failed Export says why on the same page, with "Try again".
///
/// With a Locked Book, the device's own lock is asked for before the
/// picker: the Archive holds the Locked Books' Entries too.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, this.back = Routes.settings});

  /// Where the page leaves to: Settings, or the Book list for its reminder.
  final String back;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final locked = await ref.read(lockedBookSummariesProvider.future);
    if (!mounted) return;
    if (locked.isNotEmpty) {
      if (!ref.read(appLockProvider).screenLockSet) {
        await showNoScreenLockDialog(context, ref);
        return;
      }
      final unlock = await ref
          .read(appLockProvider.notifier)
          .confirm(title: l10n.exportPrompt);
      if (!mounted) return;
      switch (unlock) {
        case Unlock.unlocked:
          break;
        case Unlock.noScreenLock:
          await showNoScreenLockDialog(context, ref);
          return;
        case Unlock.cancelled || Unlock.failed:
          return;
      }
    }

    final outcome = await ref.read(exportProvider.notifier).run();
    switch (outcome) {
      case ExportSaved(:final name):
        router.go(widget.back);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.archiveSaved(name))));
      case ExportCancelled():
        router.go(widget.back);
      case ExportNotStarted() || ExportNotSaved():
        break;
    }
  }

  void _close() {
    ref.read(exportProvider.notifier).dismissFailure();
    context.go(widget.back);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(exportProvider);
    final running = state is ExportRunning;

    return PopScope(
      // "Cancel" is the way out of a running Export.
      canPop: !running,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(exportProvider.notifier).dismissFailure();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: running
              ? null
              : IconButton(
                  tooltip: l10n.close,
                  icon: const KIcon(KIcons.x),
                  onPressed: _close,
                ),
        ),
        body: SafeArea(
          top: false,
          child: switch (state) {
            ExportReady() => ArchivePage(
              icon: KIcons.download,
              title: l10n.exportTitle,
              text: l10n.exportWarning,
              button: FilledButton(
                style: archiveButtonStyle(context),
                onPressed: _pick,
                child: Text(l10n.exportPick),
              ),
            ),
            ExportRunning(:final done, :final total) => ArchivePage(
              icon: KIcons.download,
              title: l10n.exporting,
              content: _Progress(done: done, total: total),
              note: l10n.exportKeepOpen,
              button: OutlinedButton(
                style: archiveButtonStyle(context),
                onPressed: ref.read(exportProvider.notifier).cancel,
                child: Text(l10n.cancel),
              ),
            ),
            ExportFailed(:final failure) => ArchivePage(
              icon: KIcons.triangleAlert,
              error: true,
              title: l10n.exportFailed,
              text: switch (failure) {
                ExportFailure.storageFull => l10n.exportStorageFull,
                ExportFailure.writeFailed => l10n.exportWriteFailed,
                ExportFailure.storeFailed => l10n.exportStoreFailed,
              },
              button: FilledButton(
                style: archiveButtonStyle(context),
                onPressed: ref.read(exportProvider.notifier).dismissFailure,
                child: Text(l10n.tryAgain),
              ),
            ),
          },
        ),
      ),
    );
  }
}

/// The bar, how many items of how many, and the percent. Until the Export
/// knows its total, the bar only moves.
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fraction = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    return ArchiveProgress(
      fraction: fraction,
      count: fraction != null ? l10n.exportProgress(done, total) : '',
      percent: l10n.exportPercent(((fraction ?? 0) * 100).floor()),
      semanticsLabel: l10n.exporting,
    );
  }
}
