import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_fab.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_list.dart';
import 'package:kronoer/src/entries/entry_list_menu.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/open_ink_well.dart';
import 'package:material_ui/material_ui.dart';

/// The Entries of one Book as cards, newest Entry date first until another
/// order is chosen, under a separator for each month.
///
/// The order lasts while this screen is open, also under the screens it
/// opens, and goes back to newest first once it closes.
class BookScreen extends ConsumerWidget {
  const BookScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId)).value;
    final order = ref.watch(bookEntryOrderProvider(bookId));
    final entries = ref.watch(entriesProvider(bookId)).value;

    void openInfo() => context.go(Routes.bookInfo(bookId));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: book == null
            ? null
            : _BookTitleButton(book: book, onPressed: openInfo),
        actionsPadding: const EdgeInsets.only(right: Space.xs),
        actions: [
          if (book != null)
            EntryListMenu(
              hasEntries: entries?.isNotEmpty ?? false,
              order: order,
              onOrder: ref.read(bookEntryOrderProvider(bookId).notifier).set,
              onSearch: () => context.go(Routes.bookSearch(bookId)),
              onInfo: openInfo,
            ),
        ],
      ),
      body: switch (entries) {
        null => const SizedBox.shrink(),
        [] => EmptyState(
          title: l10n.bookEmptyTitle,
          message: l10n.bookEmptyMessage,
        ),
        final entries => EntryList(
          entries,
          order: order,
          onOpen: (entry) => context.go(Routes.entry(entry.bookId, entry.id)),
          // Room at the bottom for the FAB.
          bottomPadding: 112,
        ),
      },
      floatingActionButton: BookFab(
        child: FloatingActionButton(
          heroTag: null,
          tooltip: l10n.writeEntry,
          onPressed: () => context.go(Routes.newEntry(bookId)),
          child: const KIcon(KIcons.pen),
        ),
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
