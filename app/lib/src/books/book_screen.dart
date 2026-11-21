import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_fab.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_list.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/buttons.dart';
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(book?.name ?? ''),
        actionsPadding: const EdgeInsets.only(right: Space.xs),
        actions: [
          if (book != null && (entries?.isNotEmpty ?? false))
            IconButton(
              tooltip: l10n.searchInBook(book.name),
              onPressed: () => context.go(Routes.bookSearch(bookId)),
              icon: const KIcon(KIcons.search),
            ),
          if (book != null) _BookMenu(book),
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

class _BookMenu extends ConsumerWidget {
  const _BookMenu(this.book);

  final Book book;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final count = ref.read(entriesProvider(book.id)).value?.length ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBookTitle),
        content: Text(l10n.deleteBookMessage(book.name, count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructiveTextButton(scheme),
            child: Text(l10n.deleteBookConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Leave first, so this screen never shows a Book that is gone. Read the
    // repository before that: this widget's ref goes with the screen.
    final books = ref.read(bookRepositoryProvider);
    context.go(Routes.books);
    await books.deleteBook(book.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const KIcon(KIcons.pen),
          onPressed: () => context.go(Routes.renameBook(book.id)),
          child: Text(l10n.renameBook),
        ),
        MenuItemButton(
          style: destructiveMenuItem(scheme),
          leadingIcon: const KIcon(KIcons.bin),
          onPressed: () => _delete(context, ref),
          child: Text(l10n.deleteBook),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: l10n.bookMenu,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const KIcon(KIcons.moreVertical),
      ),
    );
  }
}
