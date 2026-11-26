import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/trash/restore_to_screen.dart';
import 'package:kronoer/src/trash/trash.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:material_ui/material_ui.dart';

/// Moves the Entries [ids] to the Trash, with no confirmation, and says so
/// in a snackbar with "Undo", which restores them.
///
/// Read [context] before the screen that asked closes: [onTrashed] runs once
/// they are in the Trash, to end selection mode or close the Entry.
Future<void> trashEntriesWithUndo(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  VoidCallback? onTrashed,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Read before waiting: the screen asking may be gone by the time to undo.
  final trash = ref.read(trashRepositoryProvider);

  await trash.trashEntries(ids);
  onTrashed?.call();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.entriesTrashed(ids.length)),
        persist: false,
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => unawaited(trash.restore(entryIds: ids)),
        ),
      ),
    );
}

/// Asks whether to delete [books], saying they wait in the Trash for [days]
/// days with their Entries: true once confirmed. [entryCount] is how many
/// Entries they hold together.
Future<bool> confirmTrashBooks(
  BuildContext context,
  List<Book> books, {
  required int entryCount,
  required int days,
}) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final (title, message) = switch (books) {
    [final only] => (
      l10n.deleteBookTitle,
      l10n.deleteBookMessage(only.name, entryCount, days),
    ),
    _ => (
      l10n.deleteBooksTitle(books.length),
      l10n.deleteBooksMessage(books.length, entryCount, days),
    ),
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
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
  return confirmed ?? false;
}

/// Moves [books] to the Trash and says so in a snackbar with "Undo".
///
/// The Trash keeps no pin or Timeline choice, and restoring one later does
/// not bring them back; "Undo", right after, does.
Future<void> trashBooksWithUndo(
  BuildContext context,
  WidgetRef ref,
  List<Book> books,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final trash = ref.read(trashRepositoryProvider);
  final repository = ref.read(bookRepositoryProvider);

  for (final book in books) {
    await trash.trashBook(book.id);
  }
  Future<void> undo() async {
    await trash.restore(bookIds: [for (final book in books) book.id]);
    for (final book in books) {
      if (!book.inTimeline) {
        await repository.setBookInTimeline(book.id, inTimeline: false);
      }
    }
    final pinned = [
      for (final book in books)
        if (book.pinned) book.id,
    ];
    if (pinned.isEmpty) return;
    try {
      await repository.setBooksPinned(pinned, pinned: true);
    } on TooManyPinnedBooks {
      // Another Book took the pin meanwhile; this one comes back unpinned.
    }
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.booksTrashed(books.length)),
        persist: false,
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => unawaited(undo()),
        ),
      ),
    );
}

/// Restores [items] from the Trash and says in a snackbar where they went:
/// true once they are back, false if the user went back instead.
///
/// Entries whose Book is in the Trash too, and not among [items], first open
/// "Restore to", to restore their Book as well or to pick another Book.
Future<bool> restoreFromTrash(
  BuildContext context,
  WidgetRef ref,
  List<TrashItem> items,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final trash = ref.read(trashRepositoryProvider);
  final books = [
    for (final item in items)
      if (item is TrashedBook) item,
  ];
  final entries = [
    for (final item in items)
      if (item is TrashedEntry) item,
  ];
  final restoredBooks = {for (final book in books) book.id};
  final stranded = [
    for (final entry in entries)
      if (entry.bookInTrash && !restoredBooks.contains(entry.entry.bookId))
        entry,
  ];

  Book? to;
  if (stranded.isNotEmpty) {
    final picked = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<RestoreTarget>(
        builder: (_) => RestoreToScreen(entries: stranded),
      ),
    );
    if (picked == null) return false;
    to = picked.book;
  }

  await trash.restore(
    bookIds: restoredBooks,
    entryIds: [for (final entry in entries) entry.id],
    othersTo: to?.id,
  );

  // Where each Entry went: its own Book, or the one picked.
  final places = {
    for (final entry in entries)
      stranded.contains(entry) && to != null ? to.name : entry.bookName,
  };
  final message = switch ((books, places.toList())) {
    ([], [final place]) => l10n.entriesRestored(entries.length, place),
    ([final only], []) => l10n.bookRestored(only.book.name),
    _ => l10n.itemsRestored(items.length),
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), persist: false));
  return true;
}

/// Asks whether to delete [items] for good, saying it cannot be undone: true
/// once confirmed. [bookEntryCount] is how many Entries a single Book takes
/// with it.
Future<bool> confirmDeleteForever(
  BuildContext context,
  List<TrashItem> items, {
  int bookEntryCount = 0,
}) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final message = switch (items) {
    [TrashedEntry()] => l10n.deleteForeverEntry,
    [TrashedBook(:final book)] => l10n.deleteForeverBook(
      book.name,
      bookEntryCount,
    ),
    _ => l10n.deleteForeverItems(items.length),
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteForeverTitle),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructiveTextButton(scheme),
          child: Text(l10n.deleteForeverConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Asks whether to empty the Trash, which holds [count] items: true once
/// confirmed.
Future<bool> confirmEmptyTrash(BuildContext context, int count) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.emptyTrashTitle),
      content: Text(l10n.emptyTrashMessage(count)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructiveTextButton(scheme),
          child: Text(l10n.emptyTrashConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
