import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/trash/trash.dart';
import 'package:material_ui/material_ui.dart';

/// Where "Restore to" sends Entries: to [book], or, when it is null, back
/// to their own Books, which come out of the Trash too.
class RestoreTarget {
  const RestoreTarget(this.book);

  final Book? book;
}

/// "Restore to": for Entries whose Book is in the Trash too. First the
/// option to restore that Book as well, with its Entries, then the user's
/// other Books. Tapping one closes the page with it; back closes it with
/// none.
class RestoreToScreen extends ConsumerWidget {
  const RestoreToScreen({required this.entries, super.key});

  /// Each with its Book in the Trash.
  final List<TrashedEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final variant = theme.colorScheme.onSurfaceVariant;
    final bookIds = {for (final entry in entries) entry.entry.bookId};
    final own = bookIds.length == 1
        ? ref.watch(bookProvider(bookIds.single)).value
        : null;
    final books = ref.watch(destinationBooksProvider);

    final hint = bookIds.length == 1
        ? l10n.restoreToHint(entries.length, entries.first.bookName)
        : l10n.restoreToHintBooks(entries.length);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.restoreTo)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.xs,
              Space.xl,
              Space.m,
            ),
            child: Text(
              hint,
              style: theme.textTheme.bodyMedium?.copyWith(color: variant),
            ),
          ),
          ListTile(
            minTileHeight: 72,
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            horizontalTitleGap: Space.l,
            leading: own == null
                ? null
                : CoverThumbnail(own, width: 30, radius: 5),
            title: Text(
              own?.name ?? l10n.restoreWithBooksTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(
              bookIds.length == 1
                  ? l10n.restoreWithBook
                  : l10n.restoreWithBooks,
            ),
            onTap: () => Navigator.pop(context, const RestoreTarget(null)),
          ),
          if (books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.l,
                Space.xl,
                Space.xs,
              ),
              child: Text(
                l10n.otherBooks,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          for (final (i, summary) in books.indexed) ...[
            // Inset to where the names start.
            if (i > 0) const Divider(height: 1, indent: 70),
            ListTile(
              minTileHeight: 64,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
              horizontalTitleGap: Space.l,
              leading: CoverThumbnail(summary.book, width: 30, radius: 5),
              title: Text(
                summary.book.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              onTap: () => Navigator.pop(context, RestoreTarget(summary.book)),
            ),
          ],
        ],
      ),
    );
  }
}
