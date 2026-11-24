import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/storage/storage.dart';

final bookSummariesProvider = StreamProvider<List<BookSummary>>(
  (ref) => ref.watch(bookRepositoryProvider).watchBookSummaries(),
);

/// The Locked Books, for the Book terkunci page. The Book list asks only
/// whether there are any, and the router which Books they are.
final lockedBookSummariesProvider = StreamProvider<List<BookSummary>>(
  (ref) => ref.watch(bookRepositoryProvider).watchLockedBookSummaries(),
);

/// How many Entries, words, and Images a Book holds, read again after every
/// change.
final bookInsightProvider = StreamProvider.autoDispose
    .family<BookInsight, String>(
      (ref, id) => ref.watch(bookRepositoryProvider).watchBookInsight(id),
    );

final bookProvider = StreamProvider.autoDispose.family<Book?, String>(
  (ref, id) => ref.watch(bookRepositoryProvider).watchBook(id),
);
