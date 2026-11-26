import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/activity_time.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_fab.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/export/export_reminder.dart';
import 'package:kronoer/src/lock/app_lock_suggestion.dart';
import 'package:kronoer/src/update/update_check.dart';
import 'package:kronoer/src/lock/book_lock.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/search/search_bar_hero.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/trash/trash.dart';
import 'package:kronoer/src/trash/trash_actions.dart';
import 'package:kronoer/src/trash/trash_providers.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/open_ink_well.dart';
import 'package:kronoer/src/ui/selection.dart';
import 'package:kronoer/src/ui/wordmark.dart';
import 'package:material_ui/material_ui.dart';

/// One Book in the Book list: its Cover thumbnail (or a tile), its name, when
/// it was last written in, a preview of its latest Entry, and a pin if it is
/// pinned.
///
/// A tap opens the Book, a long press starts selection mode. While
/// [selecting], a tap selects or deselects it instead, and a [selected] row
/// is tinted, with a check over its Cover.
class BookRow extends StatelessWidget {
  const BookRow({
    required this.summary,
    required this.now,
    this.selecting = false,
    this.selected = false,
    this.badge = false,
    this.onSelect,
    super.key,
  });

  final BookSummary summary;
  final DateTime now;
  final bool selecting;
  final bool selected;

  /// Whether the Cover carries a [SelectionBadge]: while selection mode is
  /// on, or still fading out. It shows only on a [selected] row.
  final bool badge;

  /// Selects or deselects the Book: on a long press, or on a tap while
  /// [selecting].
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = summary.book;
    final tint = selectedTint(theme);

    final description = _description(context, summary);

    // A plain row, no card: the Cover gives each Book its shape. Rows touch
    // and span the screen, so the pressed one lights up edge to edge.
    return Semantics(
      selected: selecting ? selected : null,
      child: OpenInkWell(
        onTap: selecting ? onSelect : () => context.go(Routes.book(book.id)),
        opens: !selecting,
        onLongPress: onSelect,
        child: AnimatedContainer(
          duration: selectionDuration,
          curve: selectionCurve,
          color: selected ? tint : tint.withValues(alpha: 0),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.l + Space.xs,
            vertical: Space.m,
          ),
          child: _content(context, l10n, theme, book, description),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    Book book,
    List<InlineSpan>? description,
  ) {
    final variant = theme.colorScheme.onSurfaceVariant;
    return Row(
      spacing: Space.l,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CoverThumbnail(book, width: 48, radius: Radii.s),
            if (badge)
              PositionedDirectional(
                end: -7,
                bottom: -7,
                child: SelectionBadge(selected: selected),
              ),
          ],
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: Space.m,
                children: [
                  Expanded(
                    child: Text(book.name, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    formatActivityTime(
                      book.lastActivityAt,
                      now: now,
                      locale: Localizations.localeOf(context).toString(),
                      yesterday: l10n.yesterday,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: variant),
                  ),
                ],
              ),
              if (description != null || book.pinned)
                Row(
                  spacing: Space.m,
                  children: [
                    Expanded(
                      child: description == null
                          ? const SizedBox.shrink()
                          : Text.rich(
                              TextSpan(children: description),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                    if (book.pinned)
                      KIcon(
                        KIcons.pin,
                        filled: true,
                        size: 16,
                        color: variant,
                        semanticLabel: l10n.pinnedBook,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The line under the Book's name: the latest Entry's text, how many Images
  /// it has, or that the Book has no Entries yet. `null` when there is nothing
  /// to say.
  static List<InlineSpan>? _description(
    BuildContext context,
    BookSummary summary,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final entryStyle = theme.extension<EntryTextStyles>()!.entryPreviewSmall;
    final label = theme.textTheme.bodyMedium!;
    // Same line height as the Entry text, so every card is as tall.
    final labelStyle = label.copyWith(
      color: color,
      height: entryStyle.fontSize! * entryStyle.height! / label.fontSize!,
    );

    InlineSpan icon(KIcons icon) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: KIcon(icon, filled: true, size: 16, color: color),
      ),
    );

    final runs = switch (summary.lastEntryText) {
      final text? => previewRuns(text),
      null => null,
    };
    final images = summary.lastEntryImageCount;
    InlineSpan preview(List<StyledRun> runs) => TextSpan(
      style: entryStyle,
      children: [
        TextStyleLook.of(context).span(runs, fontSize: entryStyle.fontSize),
      ],
    );

    return switch (runs) {
      null => [
        icon(KIcons.pen),
        TextSpan(text: l10n.bookCardNoEntries, style: labelStyle),
      ],
      _ when images > 0 => [
        icon(KIcons.image),
        TextSpan(text: l10n.bookCardImages(images), style: labelStyle),
        if (runs.isNotEmpty) ...[
          TextSpan(text: ' · ', style: labelStyle),
          preview(runs),
        ],
      ],
      [] => null,
      _ => [preview(runs)],
    };
  }
}

/// Looks like a search field; tapping it opens the search across all Books.
class _SearchField extends StatelessWidget implements PreferredSizeWidget {
  const _SearchField();

  @override
  Size get preferredSize => const Size.fromHeight(52 + Space.s);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
      // Moves up into the search screen's app bar when tapped.
      child: SearchBarHero(
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go(Routes.search()),
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: l10n.searchAllBooks,
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    spacing: Space.m,
                    children: [
                      KIcon(KIcons.search, size: 22, color: color),
                      Text(
                        l10n.searchAllBooks,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Locked Books", first in the Book list once it is pulled down past its
/// top: opens the Locked Books after the device's lock.
class _LockedBooksLink extends ConsumerWidget {
  const _LockedBooksLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final variant = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => openLockedBooks(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.l + Space.xs,
            Space.s,
            Space.l + Space.xs,
            Space.m,
          ),
          child: Row(
            spacing: Space.l,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Radii.s),
                ),
                alignment: Alignment.center,
                child: KIcon(KIcons.lock, size: 22, color: variant),
              ),
              Expanded(
                child: Text(
                  l10n.lockedBooks,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              KIcon(KIcons.chevronRight, size: 20, color: variant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [child] by [shown], from 0 (gone) to 1 (fully there): it folds
/// away from the bottom and fades.
class _Folding extends StatelessWidget implements PreferredSizeWidget {
  const _Folding({required this.shown, required this.child});

  final double shown;
  final PreferredSizeWidget child;

  @override
  Size get preferredSize => Size.fromHeight(child.preferredSize.height * shown);

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Align(
      alignment: Alignment.topCenter,
      heightFactor: shown,
      child: Opacity(opacity: shown, child: child),
    ),
  );
}

/// The Book list. A long press on a Book starts selection mode, where Books
/// can be pinned, unpinned, locked, or deleted together. Locked Books are
/// not in it: pulling it down past its top shows the Locked Books link
/// instead, while there is at least one.
class BookListScreen extends ConsumerStatefulWidget {
  const BookListScreen({super.key});

  @override
  ConsumerState<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends ConsumerState<BookListScreen>
    with SingleTickerProviderStateMixin {
  late final _selection = Selection(
    vsync: this,
    onChanged: () => setState(() {}),
  );

  /// What the selection top bar shows, kept while it fades out after the
  /// last Book is deselected.
  var _shownCount = 0;
  var _shownAllPinned = false;

  /// Whether the Locked Books link is out: pulled down past the top, and
  /// not yet back from the area it opens.
  var _linkShown = false;

  /// How far the list has been pulled past its top in this drag.
  var _pulled = 0.0;

  /// How far past its top the list is pulled to show the link.
  static const _pullToShowLink = 64.0;

  bool get _selecting => _selection.isOn;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || _linkShown) return false;
    switch (notification) {
      case ScrollStartNotification():
        _pulled = 0;
      case OverscrollNotification(:final overscroll, dragDetails: != null)
          when overscroll < 0:
        _pulled -= overscroll;
      // Where the list bounces instead, it scrolls past its top.
      case ScrollUpdateNotification(:final metrics, dragDetails: != null)
          when metrics.pixels < 0:
        _pulled = -metrics.pixels;
      default:
        return false;
    }
    if (_pulled >= _pullToShowLink) setState(() => _linkShown = true);
    return false;
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  void _endSelection() => _selection.clear();

  List<BookSummary> _selectedOf(List<BookSummary> summaries) => [
    for (final summary in summaries)
      if (_selection.contains(summary.book.id)) summary,
  ];

  Future<void> _pin(List<BookSummary> selected) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final pinned = !selected.every((summary) => summary.book.pinned);
    try {
      await ref.read(bookRepositoryProvider).setBooksPinned([
        for (final summary in selected) summary.book.id,
      ], pinned: pinned);
    } on TooManyPinnedBooks {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.tooManyPinnedBooks(maxPinnedBooks))),
        );
      return;
    }
    if (mounted) _endSelection();
  }

  /// Locks [selected] after the device's lock: they leave the Book list, and
  /// selection mode ends.
  Future<void> _lock(List<BookSummary> selected) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await setBooksLockedWithPrompt(context, ref, [
          for (final summary in selected) summary.book.id,
        ], locked: true) ||
        !mounted) {
      return;
    }
    _endSelection();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.booksLocked(selected.length)),
          persist: false,
        ),
      );
  }

  /// Asks, then moves [selected] to the Trash with their Entries.
  Future<void> _delete(List<BookSummary> selected) async {
    final books = [for (final summary in selected) summary.book];
    final entries = selected.fold(
      0,
      (sum, summary) => sum + summary.entryCount,
    );
    final days = ref.read(trashDaysProvider).value ?? defaultTrashDays;
    if (!await confirmTrashBooks(
          context,
          books,
          entryCount: entries,
          days: days,
        ) ||
        !mounted) {
      return;
    }
    _endSelection();
    await trashBooksWithUndo(context, ref, books);
  }

  @override
  Widget build(BuildContext context) {
    // Named by the delete dialog, so ready when it opens.
    ref.watch(trashDaysProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summaries = ref.watch(bookSummariesProvider).value;
    final now = ref.watch(clockProvider)();
    final hasEntries =
        summaries?.any((summary) => summary.lastEntryText != null) ?? false;
    // One banner at a time: the reminder to export first, then a new
    // Preview, and the App lock card waits for both.
    final exportReminder = ref.watch(exportReminderProvider);
    final update = ref.watch(updateOfferProvider);
    final Widget? banner = exportReminder != null
        ? ExportReminderBanner(exportReminder)
        : update != null
        ? UpdateBanner(update)
        : showsAppLockSuggestion(
            summaries ?? const [],
            ref.watch(appLockProvider),
          )
        ? const AppLockSuggestion()
        : null;
    final hasLocked =
        ref.watch(lockedBookSummariesProvider).value?.isNotEmpty ?? false;

    // Back from the Locked Books area, it locked again: so does the link.
    ref.listen(appLockProvider.select((lock) => lock.lockedBooksOpen), (
      _,
      open,
    ) {
      if (!open && _linkShown) setState(() => _linkShown = false);
    });

    // A selected Book that is gone, deleted here or elsewhere, is no longer
    // selected.
    ref.listen(bookSummariesProvider, (_, next) {
      final books = next.value;
      if (books == null) return;
      _selection.retain({for (final summary in books) summary.book.id});
    });

    final selected = _selectedOf(summaries ?? const []);
    if (selected.isNotEmpty) {
      _shownCount = selected.length;
      _shownAllPinned = selected.every((summary) => summary.book.pinned);
    }

    // First in the list while there are Locked Books: the link, folded away
    // until the list is pulled down past its top.
    final link = AnimatedSize(
      duration: Durations.medium2,
      curve: Easing.emphasizedDecelerate,
      alignment: Alignment.topCenter,
      child: _linkShown && !_selecting
          ? const _LockedBooksLink()
          : const SizedBox(width: double.infinity),
    );
    final empty = EmptyState(
      title: l10n.bookListEmptyTitle,
      message: l10n.bookListEmptyMessage,
    );

    final list = switch (summaries) {
      null => const SizedBox.shrink(),
      [] when !hasLocked => empty,
      // Every Book is locked: the usual empty state, which can still be
      // pulled down.
      [] => LayoutBuilder(
        builder: (_, constraints) => ListView(
          primary: true,
          children: [
            link,
            SizedBox(height: constraints.maxHeight, child: empty),
          ],
        ),
      ),
      final books => ScrollToTopOnReselect(
        child: ListView.builder(
          primary: true,
          padding: const EdgeInsets.only(top: Space.xs, bottom: 112),
          itemBuilder: (_, i) {
            if (hasLocked) {
              if (i == 0) return link;
              i--;
            }
            if (banner != null) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.xs,
                    Space.l,
                    Space.m,
                  ),
                  child: banner,
                );
              }
              i--;
            }
            final id = books[i].book.id;
            return BookRow(
              summary: books[i],
              now: now,
              selecting: _selecting,
              badge: _selection.badges,
              selected: _selection.contains(id),
              onSelect: () => _selection.toggle(id),
            );
          },
          itemCount:
              books.length + (banner != null ? 1 : 0) + (hasLocked ? 1 : 0),
        ),
      ),
    };

    final bar = theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final variant = theme.colorScheme.onSurfaceVariant;

    // Back ends selection mode, and the system's back must reach the app.
    return HandleBackOnTab(
      onBack: _selecting ? _endSelection : null,
      child: AnimatedBuilder(
        animation: _selection.mode,
        child: list,
        builder: (context, list) {
          final t = _selection.mode.value;
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Color.lerp(bar, selectionBarColor(theme), t),
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  SelectionLayer(
                    shown: 1 - t,
                    active: !_selecting,
                    child: const Padding(
                      padding: EdgeInsetsDirectional.only(start: 20),
                      child: Wordmark(),
                    ),
                  ),
                  if (t > 0)
                    SelectionLayer(
                      shown: t,
                      active: _selecting,
                      child: Row(
                        children: [
                          const SizedBox(width: Space.xs),
                          BackButton(onPressed: _endSelection),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Semantics(
                              label: l10n.booksSelected(_shownCount),
                              excludeSemantics: true,
                              child: Text('$_shownCount'),
                            ),
                          ),
                          IconButton(
                            tooltip: _shownAllPinned
                                ? l10n.unpinBooks
                                : l10n.pinBooks,
                            color: variant,
                            onPressed: () => _pin(selected),
                            icon: KIcon(
                              _shownAllPinned ? KIcons.pinOff : KIcons.pin,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.lockBooks,
                            color: variant,
                            onPressed: () => _lock(selected),
                            icon: const KIcon(KIcons.lock),
                          ),
                          IconButton(
                            tooltip: l10n.deleteBooks,
                            color: variant,
                            onPressed: () => _delete(selected),
                            icon: const KIcon(KIcons.bin),
                          ),
                          const SizedBox(width: Space.xs),
                        ],
                      ),
                    ),
                ],
              ),
              // Fixed under the app bar: it does not scroll with the Books.
              // It folds away while selecting.
              bottom: hasEntries && t < 1
                  ? _Folding(
                      shown: 1 - t,
                      child: SelectionLayer(
                        shown: 1,
                        active: !_selecting,
                        child: const _SearchField(),
                      ),
                    )
                  : null,
            ),
            body: hasLocked
                ? NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: list!,
                  )
                : list,
            floatingActionButton: SelectionLayer(
              shown: 1 - t,
              active: !_selecting,
              child: BookFab(
                child: FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: () => context.go(Routes.newBook),
                  icon: const KIcon(KIcons.plus),
                  label: Text(l10n.newBook),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
