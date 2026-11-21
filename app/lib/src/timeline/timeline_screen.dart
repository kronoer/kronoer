import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_list.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// Linimasa: every Entry from every Book, newest Entry date first, with the
/// Book's name on each card. Writing happens inside a Book, so there is no
/// FAB.
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(allEntriesProvider).value;
    final names = {
      for (final summary in ref.watch(bookSummariesProvider).value ?? const [])
        summary.book.id: summary.book.name,
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text(l10n.timeline),
        actionsPadding: const EdgeInsets.only(right: Space.s),
        actions: [
          if (entries?.isNotEmpty ?? false)
            IconButton(
              tooltip: l10n.searchAllBooks,
              // Pushed, so back comes here and not to the Book tab.
              onPressed: () => context.push(Routes.search()),
              icon: const KIcon(KIcons.search),
            ),
        ],
      ),
      body: switch (entries) {
        null => const SizedBox.shrink(),
        [] => EmptyState(
          title: l10n.timelineEmptyTitle,
          message: l10n.timelineEmptyMessage,
        ),
        final entries => ScrollToTopOnReselect(
          child: EntryList(
            entries,
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
