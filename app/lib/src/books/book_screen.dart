import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_fab.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_list.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The Entries of one Book as cards, newest Entry date first, under a
/// separator for each month.
class BookScreen extends ConsumerWidget {
  const BookScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId)).value;
    final entries = ref.watch(entriesProvider(bookId)).value;

    void openInfo() => context.go(Routes.bookInfo(bookId));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: book == null
            ? null
            : _BookTitleButton(name: book.name, onPressed: openInfo),
        actionsPadding: const EdgeInsets.only(right: Space.xs),
        actions: [
          if (book != null && (entries?.isNotEmpty ?? false))
            IconButton(
              tooltip: l10n.searchInBook(book.name),
              onPressed: () => context.go(Routes.bookSearch(bookId)),
              icon: const KIcon(KIcons.search),
            ),
          if (book != null)
            IconButton(
              tooltip: l10n.bookInfo,
              onPressed: openInfo,
              icon: const KIcon(KIcons.info),
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

/// The Book's name in the app bar, as a button that opens Book info. The
/// Book's mini Cover will sit before the name.
class _BookTitleButton extends StatelessWidget {
  const _BookTitleButton({required this.name, required this.onPressed});

  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        container: true,
        button: true,
        label: l10n.bookInfo,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Space.touch / 2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.touch),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.s,
                end: Space.m,
              ),
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                alignment: AlignmentDirectional.centerStart,
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
