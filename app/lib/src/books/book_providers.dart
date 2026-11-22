import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/storage/storage.dart';

final bookSummariesProvider = StreamProvider<List<BookSummary>>(
  (ref) => ref.watch(bookRepositoryProvider).watchBookSummaries(),
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
