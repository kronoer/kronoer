import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_list.dart';
import 'package:kronoer/src/entries/entry_list_menu.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:material_ui/material_ui.dart';

/// Linimasa: every Entry from every Book, newest Entry date first until
/// another order is chosen, with the Book's name on each card. Writing
/// happens inside a Book, so there is no FAB.
///
/// The order is not stored: it lasts until the app closes. Books the user
/// keeps out of the Timeline, from Book info or "Book di Linimasa", are left
/// out.
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final order = ref.watch(timelineOrderProvider);
    final entries = ref.watch(allEntriesProvider).value;
    final books = ref.watch(bookSummariesProvider).value ?? const [];
    final names = {
      for (final summary in books) summary.book.id: summary.book.name,
    };
    // There are Entries, but every Book is kept out of the Timeline.
    final allKeptOut =
        books.any((summary) => summary.entryCount > 0) &&
        books.every((summary) => !summary.book.inTimeline);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text(l10n.timeline),
        actionsPadding: const EdgeInsets.only(right: Space.s),
        actions: [
          EntryListMenu(
            hasEntries: entries?.isNotEmpty ?? false,
            order: order,
            onOrder: ref.read(timelineOrderProvider.notifier).set,
            // Pushed, so back comes here and not to the Book tab.
            onSearch: () => context.push(Routes.search()),
            onTimelineBooks: books.isEmpty
                ? null
                : () => context.push(Routes.timelineBooks),
          ),
        ],
      ),
      body: switch (entries) {
        null => const SizedBox.shrink(),
        [] when allKeptOut => EmptyState(title: l10n.timelineNoBooksShown),
        [] => EmptyState(
          title: l10n.timelineEmptyTitle,
          message: l10n.timelineEmptyMessage,
        ),
        final entries => ScrollToTopOnReselect(
          child: EntryList(
            entries,
            order: order,
            controller: PrimaryScrollController.of(context),
            bookName: (bookId) => names[bookId],
            // Pushed, so back returns here at the same place.
            onOpen: (entry) =>
                context.push(Routes.entry(entry.bookId, entry.id)),
          ),
        ),
      },
    );
  }
}
