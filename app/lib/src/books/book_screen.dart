import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_fab.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_copying.dart';
import 'package:kronoer/src/entries/entry_list.dart';
import 'package:kronoer/src/entries/entry_list_menu.dart';
import 'package:kronoer/src/entries/entry_moving.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/open_ink_well.dart';
import 'package:kronoer/src/ui/selection.dart';
import 'package:material_ui/material_ui.dart';

/// The Entries of one Book as cards, newest Entry date first until another
/// order is chosen, under a separator for each month.
///
/// The order lasts while this screen is open, also under the screens it
/// opens, and goes back to newest first once it closes.
///
/// A long press on an Entry starts selection mode, where the text of Entries
/// can be copied, or Entries moved to another Book or deleted, together. Back, the top bar's or the
/// system's, ends it.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends ConsumerState<BookScreen>
    with SingleTickerProviderStateMixin {
  late final _selection = Selection(
    vsync: this,
    onChanged: () => setState(() {}),
  );

  /// The number the selection top bar shows, kept while it fades out after
  /// the last Entry is deselected.
  var _shownCount = 0;

  String get _bookId => widget.bookId;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  /// The selected Entries, in the order the list shows them.
  List<Entry> _selectedIn(List<Entry> entries) => [
    for (final entry in entries)
      if (_selection.contains(entry.id)) entry,
  ];

  /// Copies the text of [entries] and ends selection mode, unless it was too
  /// long to copy.
  Future<void> _copy(List<Entry> entries) async {
    final copied = await copyEntriesText(context, ref, entries);
    if (copied && mounted) _selection.clear();
  }

  Future<void> _move(List<String> ids) => moveEntriesWithUndo(
    context,
    ref,
    ids,
    fromBookId: _bookId,
    onMoved: () {
      if (mounted) _selection.clear();
    },
  );

  Future<void> _delete(List<String> ids) async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteEntriesTitle(ids.length)),
        content: Text(l10n.deleteEntriesMessage(ids.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructiveTextButton(scheme),
            child: Text(l10n.deleteEntriesConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final entries = ref.read(entryRepositoryProvider);
    _selection.clear();
    await entries.deleteEntries(ids);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = ref.watch(bookProvider(_bookId)).value;
    final order = ref.watch(bookEntryOrderProvider(_bookId));
    final entries = ref.watch(entriesProvider(_bookId)).value;
    final selecting = _selection.isOn;

    // A selected Entry that is gone, moved or deleted here or elsewhere, is
    // no longer selected.
    ref.listen(entriesProvider(_bookId), (_, next) {
      final entries = next.value;
      if (entries == null) return;
      _selection.retain({for (final entry in entries) entry.id});
    });

    final selectedEntries = _selectedIn(entries ?? const []);
    final selected = [for (final entry in selectedEntries) entry.id];
    if (selected.isNotEmpty) _shownCount = selected.length;

    void openInfo() => context.go(Routes.bookInfo(_bookId));

    final list = switch (entries) {
      null => const SizedBox.shrink(),
      [] => EmptyState(
        title: l10n.bookEmptyTitle,
        message: l10n.bookEmptyMessage,
      ),
      final entries => EntryList(
        entries,
        order: order,
        onOpen: (entry) => context.go(Routes.entry(entry.bookId, entry.id)),
        selection: _selection,
        onSelect: (entry) => _selection.toggle(entry.id),
        // Room at the bottom for the FAB.
        bottomPadding: 112,
      ),
    };

    final bar = theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final variant = theme.colorScheme.onSurfaceVariant;

    // The Book is over the tabs, so the system's back reaches it: while
    // selecting, it ends selection mode instead of leaving.
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selection.clear();
      },
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
                    active: !selecting,
                    child: Row(
                      children: [
                        // Where the app bar's own back button would be.
                        const SizedBox(width: Space.xs),
                        const BackButton(),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: book == null
                              ? const SizedBox.shrink()
                              : _BookTitleButton(
                                  book: book,
                                  onPressed: openInfo,
                                ),
                        ),
                        if (book != null)
                          EntryListMenu(
                            hasEntries: entries?.isNotEmpty ?? false,
                            order: order,
                            onOrder: ref
                                .read(bookEntryOrderProvider(_bookId).notifier)
                                .set,
                            onSearch: () =>
                                context.go(Routes.bookSearch(_bookId)),
                            onInfo: openInfo,
                          ),
                        const SizedBox(width: Space.xs),
                      ],
                    ),
                  ),
                  if (t > 0)
                    SelectionLayer(
                      shown: t,
                      active: selecting,
                      child: Row(
                        children: [
                          const SizedBox(width: Space.xs),
                          BackButton(onPressed: _selection.clear),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Semantics(
                              label: l10n.entriesSelected(_shownCount),
                              excludeSemantics: true,
                              child: Text('$_shownCount'),
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.copyEntries,
                            color: variant,
                            // Entries of Images only have no text to copy.
                            onPressed: selectedEntries.any(hasText)
                                ? () => _copy(selectedEntries)
                                : null,
                            icon: const KIcon(KIcons.copy),
                          ),
                          IconButton(
                            tooltip: l10n.moveEntries,
                            color: variant,
                            onPressed: () => _move(selected),
                            icon: const KIcon(KIcons.bookArrowRight),
                          ),
                          IconButton(
                            tooltip: l10n.deleteEntries,
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
            ),
            body: list,
            floatingActionButton: SelectionLayer(
              shown: 1 - t,
              active: !selecting,
              child: BookFab(
                child: FloatingActionButton(
                  heroTag: null,
                  tooltip: l10n.writeEntry,
                  onPressed: () => context.go(Routes.newEntry(_bookId)),
                  child: const KIcon(KIcons.pen),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The Book's mini Cover, if it has one, and its name in the app bar, as one
/// button that opens Book info. It fills the bar up to the actions.
class _BookTitleButton extends StatelessWidget {
  const _BookTitleButton({required this.book, required this.onPressed});

  final Book book;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The whole bar between back and the actions, square: the pressed effect
    // fills it edge to edge, top to bottom.
    return SizedBox(
      width: double.infinity,
      height: AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight,
      child: Semantics(
        container: true,
        button: true,
        label: l10n.bookInfo,
        child: OpenInkWell(
          onTap: onPressed,
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.s,
                end: Space.m,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.m,
                  children: [
                    if (book.coverId != null)
                      CoverThumbnail(book, width: 24, radius: Radii.xs),
                    Flexible(
                      child: Text(
                        book.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
