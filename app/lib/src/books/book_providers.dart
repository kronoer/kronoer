import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/storage/storage.dart';

final bookSummariesProvider = StreamProvider<List<BookSummary>>(
  (ref) => ref.watch(bookRepositoryProvider).watchBookSummaries(),
);

/// The Locked Books, for the Book terkunci page. The Book list asks only
/// whether there are any, and the router which Books they are.
final lockedBookSummariesProvider = StreamProvider<List<BookSummary>>(
  (ref) => ref.watch(bookRepositoryProvider).watchLockedBookSummaries(),
);

/// The Books Entries can be moved or restored to: the Book list's, then,
/// only while the Book terkunci area is open, the Locked Books.
final destinationBooksProvider = Provider<List<BookSummary>>((ref) {
  final books = ref.watch(bookSummariesProvider).value ?? const [];
  if (!ref.watch(appLockProvider.select((lock) => lock.lockedBooksOpen))) {
    return books;
  }
  return [...books, ...?ref.watch(lockedBookSummariesProvider).value];
});

/// How many Entries, words, and Images a Book holds, read again after every
/// change.
final bookInsightProvider = StreamProvider.autoDispose
    .family<BookInsight, String>(
      (ref, id) => ref.watch(bookRepositoryProvider).watchBookInsight(id),
    );

final bookProvider = StreamProvider.autoDispose.family<Book?, String>(
  (ref, id) => ref.watch(bookRepositoryProvider).watchBook(id),
);
