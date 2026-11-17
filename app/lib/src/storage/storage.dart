import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';

final inMemoryStoreProvider = Provider<InMemoryStore>((ref) {
  final store = InMemoryStore();
  ref.onDispose(store.dispose);
  return store;
});

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => ref.watch(inMemoryStoreProvider),
);

final entryRepositoryProvider = Provider<EntryRepository>(
  (ref) => ref.watch(inMemoryStoreProvider),
);
