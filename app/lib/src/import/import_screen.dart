import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/export/archive_page.dart';
import 'package:kronoer/src/import/import.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// "Impor dari arsip": the picker for an archive, then its check and what is
/// added, with Batal, then what came of it. A refused archive says why on
/// the same page, with Pilih file lain.
///
/// Opened from Settings, or from Welcome before the user has started; [back]
/// is where it leaves to when nothing was added. From Welcome, Batal leaves
/// too.
class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key, this.back = Routes.settings});

  final String back;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(importProvider);
    final notifier = ref.read(importProvider.notifier);
    final running = state is ImportRunning;

    void leave(String route) {
      notifier.dismiss();
      context.go(route);
    }

    if (back == Routes.welcome) {
      ref.listen(importProvider, (previous, next) {
        if (previous is ImportRunning && next is ImportReady) context.go(back);
      });
    }

    // After an Import that added something, the way out shows the Books.
    final closeTo = switch (state) {
      ImportFinished(:final summary) when !summary.hadAll => Routes.books,
      _ => back,
    };

    return PopScope(
      // Batal is the way out of a running Import.
      canPop: !running,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) notifier.dismiss();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: running
              ? null
              : IconButton(
                  tooltip: l10n.close,
                  icon: const KIcon(KIcons.x),
                  onPressed: () => leave(closeTo),
                ),
        ),
        body: SafeArea(
          top: false,
          child: switch (state) {
            ImportReady() => ArchivePage(
              icon: KIcons.upload,
              title: l10n.importTitle,
              text: l10n.importText,
              button: FilledButton(
                style: archiveButtonStyle(context),
                onPressed: notifier.run,
                child: Text(l10n.importPick),
              ),
            ),
            ImportRunning(:final name, :final progress) => ArchivePage(
              icon: KIcons.upload,
              title: l10n.importing,
              text: name,
              content: _Running(progress),
              note: l10n.importKeepOpen,
              button: OutlinedButton(
                style: archiveButtonStyle(context),
                onPressed: notifier.cancel,
                child: Text(l10n.cancel),
              ),
            ),
            ImportFailed(:final failure) => ArchivePage(
              icon: KIcons.triangleAlert,
              error: true,
              title: l10n.importFailed,
              text: switch (failure) {
                ImportFailure.damaged => l10n.importDamaged,
                ImportFailure.newer => l10n.importNewer,
                ImportFailure.image => l10n.importImage,
                ImportFailure.storeFailed => l10n.importStoreFailed,
              },
              note: l10n.importNothingAdded,
              button: FilledButton(
                style: archiveButtonStyle(context),
                onPressed: () {
                  notifier.dismiss();
                  notifier.run();
                },
                child: Text(l10n.importPickAnother),
              ),
            ),
            ImportFinished(:final summary) when summary.hadAll => ArchivePage(
              icon: KIcons.check,
              title: l10n.importAllThere,
              text: l10n.importAllThereText(
                _amount(l10n, summary.bookCount, summary.entryCount),
              ),
              button: FilledButton(
                style: archiveButtonStyle(context),
                onPressed: () => leave(back),
                child: Text(l10n.done),
              ),
            ),
            ImportFinished(:final summary) => ArchivePage(
              icon: KIcons.check,
              title: l10n.importDone,
              text: _summaryText(l10n, summary),
              content: _Rows(summary),
              button: FilledButton(
                style: archiveButtonStyle(context),
                onPressed: () => leave(Routes.books),
                child: Text(l10n.importSeeResult),
              ),
            ),
          },
        ),
      ),
    );
  }
}

/// "2 Book dan 31 Entry", or only the Books or only the Entries when the
/// other is none.
String _amount(AppLocalizations l10n, int books, int entries) {
  if (books == 0) return l10n.importEntries(entries);
  if (entries == 0) return l10n.importBooks(books);
  return l10n.importAnd(l10n.importBooks(books), l10n.importEntries(entries));
}

String _summaryText(AppLocalizations l10n, ImportSummaryItem summary) {
  final added = summary.addedBookCount + summary.addedEntryCount > 0;
  return [
    if (added)
      l10n.importAdded(
        _amount(l10n, summary.addedBookCount, summary.addedEntryCount),
      ),
    if (summary.existingEntryCount > 0)
      l10n.importSkipped(summary.existingEntryCount),
    l10n.importNothingOverwritten,
  ].join(' ');
}

/// The two steps of a running Import, and the bar of the second.
class _Running extends StatelessWidget {
  const _Running(this.progress);

  final ImportProgressItem progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final checked = progress.checked;
    final total = progress.newEntryCount;
    final fraction = checked && total > 0
        ? (progress.done / total).clamp(0.0, 1.0)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Step(
          label: checked ? l10n.importChecked : l10n.importChecking,
          detail: checked
              ? l10n.importContents(
                  l10n.importBooks(progress.bookCount),
                  l10n.importEntries(progress.entryCount),
                  l10n.importPhotos(progress.imageCount),
                )
              : null,
          state: checked ? _StepState.done : _StepState.active,
        ),
        const SizedBox(height: Space.xs),
        _Step(
          label: l10n.importAdding,
          detail: checked
              ? l10n.importNew(
                  _amount(l10n, progress.newBookCount, progress.newEntryCount),
                )
              : null,
          state: checked ? _StepState.active : _StepState.waiting,
        ),
        const SizedBox(height: Space.l),
        ArchiveProgress(
          fraction: fraction,
          count: fraction != null
              ? l10n.importProgress(progress.done, total)
              : '',
          percent: l10n.exportPercent(((fraction ?? 0) * 100).floor()),
          semanticsLabel: l10n.importing,
        ),
      ],
    );
  }
}

enum _StepState { waiting, active, done }

/// One step: a check once it is done, a spinner while it runs, an empty
/// circle before it starts.
class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state, this.detail});

  final String label;
  final String? detail;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final waiting = state == _StepState.waiting;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: switch (state) {
              _StepState.done => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
                child: Center(
                  child: KIcon(KIcons.check, size: 16, color: scheme.onPrimary),
                ),
              ),
              _StepState.active => CircularProgressIndicator(
                strokeWidth: 3,
                backgroundColor: scheme.primaryContainer,
              ),
              _StepState.waiting => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outlineVariant, width: 2),
                ),
              ),
            },
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: waiting ? scheme.onSurfaceVariant : null,
                  ),
                ),
                if (detail case final detail?)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What an Import did, one row per Book: first those it added to, then all
/// Locked Books in one row without their names, then the Books in the Trash
/// whose new Entries wait, then the rest.
class _Rows extends StatelessWidget {
  const _Rows(this.summary);

  final ImportSummaryItem summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final waiting = [
      for (final book in summary.books)
        if (book.inTrash && book.trashedEntryCount > 0) book,
    ];
    final others = [
      for (final book in summary.books)
        if (!waiting.contains(book)) book,
    ];
    final locked = [
      for (final book in others)
        if (book.locked) book,
    ];
    final unlocked = [
      for (final book in others)
        if (!book.locked) book,
    ];
    bool addedTo(ImportedBookItem book) =>
        book.added || book.addedEntryCount > 0;
    final lockedAdded = locked.fold(0, (sum, b) => sum + b.addedEntryCount);

    _Row row(ImportedBookItem book) => _Row(
      name: book.name,
      note: book.added
          ? l10n.importNewBook
          : l10n.importExisting(book.existingEntryCount),
      end: l10n.importAddedCount(book.addedEntryCount),
      highlight: book.addedEntryCount > 0,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final book in unlocked)
            if (addedTo(book)) row(book),
          if (locked.isNotEmpty)
            _Row(
              icon: KIcons.lock,
              name: l10n.importLockedBooks,
              note: l10n.importNamesHidden,
              end: l10n.importAddedCount(lockedAdded),
              highlight: lockedAdded > 0,
            ),
          for (final book in waiting)
            _Row(
              icon: KIcons.bin,
              name: book.locked ? l10n.importLockedBooks : book.name,
              note: l10n.importInTrash,
              end: l10n.importTrashSkipped(book.trashedEntryCount),
            ),
          for (final book in unlocked)
            if (!addedTo(book)) row(book),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.note,
    required this.end,
    this.icon,
    this.highlight = false,
  });

  final KIcons? icon;
  final String name;
  final String note;
  final String end;

  /// Whether [end] is in the primary color: something was added.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strong = theme.textTheme.titleMedium;

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: MergeSemantics(
        child: Row(
          children: [
            if (icon case final icon?) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: KIcon(icon, size: 20, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: Space.m),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: strong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.m),
            Text(
              end,
              style: strong?.copyWith(
                color: highlight ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
