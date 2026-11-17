import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/storage/storage.dart';

final booksProvider = StreamProvider<List<Book>>(
  (ref) => ref.watch(bookRepositoryProvider).watchBooks(),
);

final bookProvider = StreamProvider.autoDispose.family<Book?, String>(
  (ref, id) => ref.watch(bookRepositoryProvider).watchBook(id),
);
