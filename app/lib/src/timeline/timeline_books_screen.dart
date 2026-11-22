import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// "Book di Linimasa": every Book in Book list order, each with a checkbox
/// for whether the Timeline shows its Entries. A change is saved at once;
/// unchecking every Book is allowed.
class TimelineBooksScreen extends ConsumerWidget {
  const TimelineBooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final books = ref.watch(bookSummariesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.booksInTimeline)),
      body: ListView.separated(
        padding: const EdgeInsets.only(top: Space.xs, bottom: Space.xl),
        itemCount: books.length,
        // Inset to where the names start.
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 70),
        itemBuilder: (context, i) {
          final book = books[i].book;
          return CheckboxListTile(
            value: book.inTimeline,
            onChanged: (value) => ref
                .read(bookRepositoryProvider)
                .setBookInTimeline(book.id, inTimeline: value ?? true),
            minTileHeight: 64,
            contentPadding: const EdgeInsets.only(
              left: Space.xl,
              right: Space.m,
            ),
            horizontalTitleGap: Space.l,
            secondary: CoverThumbnail(book, width: 30, radius: 5),
            title: Text(
              book.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          );
        },
      ),
    );
  }
}
