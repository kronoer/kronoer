import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// "Locked Books": the Locked Books, opened from the Book list's link after
/// the device's lock, ordered like the Book list. Inside, a Locked Book
/// opens and works as any other Book.
///
/// There is no New Book here: a new Book is made on the Book list, then
/// locked. The area locks again when the user goes back to the Book list.
class LockedBooksScreen extends ConsumerWidget {
  const LockedBooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaries = ref.watch(lockedBookSummariesProvider).value;
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.lockedBooks)),
      body: switch (summaries) {
        null => const SizedBox.shrink(),
        [] => EmptyState(
          icon: KIcons.bookLock,
          title: l10n.lockedBooksEmptyTitle,
          message: l10n.lockedBooksEmptyMessage,
        ),
        final books => ListView.builder(
          padding: const EdgeInsets.only(top: Space.xs, bottom: Space.xl),
          itemCount: books.length,
          itemBuilder: (_, i) => BookRow(summary: books[i], now: now),
        ),
      },
    );
  }
}
