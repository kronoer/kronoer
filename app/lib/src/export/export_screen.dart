import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/export/export.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/lock/book_lock.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// "Ekspor Data": warns that the Archive will not be encrypted, then writes
/// every Book into one at the place the user picks, with its progress and
/// Batal. A failed Export says why on the same page, with Coba lagi.
///
/// With a Locked Book, the device's own lock is asked for before the
/// picker: the Archive holds the Locked Books' Entries too.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

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
        router.go(Routes.settings);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.archiveSaved(name))));
      case ExportCancelled():
        router.go(Routes.settings);
      case ExportNotStarted() || ExportNotSaved():
        break;
    }
  }

  void _close() {
    ref.read(exportProvider.notifier).dismissFailure();
    context.go(Routes.settings);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(exportProvider);
    final running = state is ExportRunning;

    return PopScope(
      // Batal is the way out of a running Export.
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
            ExportReady() => _ExportPage(
              icon: KIcons.download,
              title: l10n.exportTitle,
              text: l10n.exportWarning,
              button: FilledButton(
                style: _buttonStyle(context),
                onPressed: _pick,
                child: Text(l10n.exportPick),
              ),
            ),
            ExportRunning(:final done, :final total) => _ExportPage(
              icon: KIcons.download,
              title: l10n.exporting,
              progress: _Progress(done: done, total: total),
              note: l10n.exportKeepOpen,
              button: OutlinedButton(
                style: _buttonStyle(context),
                onPressed: ref.read(exportProvider.notifier).cancel,
                child: Text(l10n.cancel),
              ),
            ),
            ExportFailed(:final failure) => _ExportPage(
              icon: KIcons.triangleAlert,
              error: true,
              title: l10n.exportFailed,
              text: switch (failure) {
                ExportFailure.storageFull => l10n.exportStorageFull,
                ExportFailure.writeFailed => l10n.exportWriteFailed,
                ExportFailure.storeFailed => l10n.exportStoreFailed,
              },
              button: FilledButton(
                style: _buttonStyle(context),
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

ButtonStyle _buttonStyle(BuildContext context) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56)),
  textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleMedium),
);

/// The Export's pages: an icon in a circle, a title, what to know, and one
/// button at the bottom.
class _ExportPage extends StatelessWidget {
  const _ExportPage({
    required this.icon,
    required this.title,
    required this.button,
    this.text,
    this.progress,
    this.note,
    this.error = false,
  });

  final KIcons icon;
  final String title;
  final String? text;
  final Widget? progress;
  final String? note;
  final Widget button;

  /// Whether the icon is in the error colors.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.xxl + Space.l,
              Space.xl,
              Space.l,
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: error
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                  ),
                  child: Center(
                    child: KIcon(
                      icon,
                      size: 36,
                      color: error
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: Space.xl),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (text case final text?) ...[
                  const SizedBox(height: Space.l),
                  Text(text, style: muted, textAlign: TextAlign.center),
                ],
                if (progress case final progress?) ...[
                  const SizedBox(height: Space.xl),
                  progress,
                ],
                if (note case final note?) ...[
                  const SizedBox(height: Space.xl),
                  Text(
                    note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.l,
            Space.l,
            Space.l,
            Space.xl,
          ),
          child: button,
        ),
      ],
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
    final theme = Theme.of(context);
    final known = total > 0;
    final fraction = known ? (done / total).clamp(0.0, 1.0) : null;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: fraction,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          semanticsLabel: l10n.exporting,
        ),
        const SizedBox(height: Space.s),
        Row(
          children: [
            Expanded(
              child: Text(
                known ? l10n.exportProgress(done, total) : '',
                style: small,
              ),
            ),
            // The bar reads out its percent already.
            if (fraction != null)
              ExcludeSemantics(
                child: Text(
                  l10n.exportPercent((fraction * 100).floor()),
                  style: small,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
