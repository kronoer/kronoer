import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Moves the Entries [ids], all from the Book [fromBookId], to a Book the
/// user picks on the "Pindahkan ke" page. Nothing happens if they go back
/// instead.
///
/// Once a Book is picked, the Entries move at once, with no confirmation;
/// [onMoved] runs (to end selection mode or close the read view), and a
/// snackbar says where they went, with Urungkan to move them back.
Future<void> moveEntriesWithUndo(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  required String fromBookId,
  required VoidCallback onMoved,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Read before waiting: the screen asking may be gone by the time to undo.
  final entries = ref.read(entryRepositoryProvider);

  final to = await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<Book>(
      builder: (_) => MoveTargetScreen(fromBookId: fromBookId),
    ),
  );
  if (to == null) return;

  await entries.moveEntries(ids, toBookId: to.id);
  onMoved();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.entriesMoved(ids.length, to.name)),
        persist: false,
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () =>
              unawaited(entries.moveEntries(ids, toBookId: fromBookId)),
        ),
      ),
    );
}

/// "Pindahkan ke": every Book in Book list order, with the Locked Books after
/// them only inside the Book terkunci area, to pick the one to move
/// Entries to. The Book they are in now shows disabled, as "Book ini".
/// Tapping a Book closes the page with it; back closes it with none.
class MoveTargetScreen extends ConsumerWidget {
  const MoveTargetScreen({required this.fromBookId, super.key});

  final String fromBookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final books = ref.watch(destinationBooksProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.moveTo)),
      body: ListView.separated(
        padding: const EdgeInsets.only(top: Space.xs, bottom: Space.xl),
        itemCount: books.length,
        // Inset to where the names start.
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 70),
        itemBuilder: (context, i) {
          final book = books[i].book;
          final here = book.id == fromBookId;
          // The Book they are in fades whole: Cover, name, and label.
          return Opacity(
            opacity: here ? 0.38 : 1,
            child: ListTile(
              enabled: !here,
              minTileHeight: 64,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
              horizontalTitleGap: Space.l,
              leading: CoverThumbnail(book, width: 30, radius: 5),
              title: Text(
                book.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              trailing: here
                  ? Text(
                      l10n.thisBook,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              onTap: () => Navigator.pop(context, book),
            ),
          );
        },
      ),
    );
  }
}
