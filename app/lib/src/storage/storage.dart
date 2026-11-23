import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/search/search.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/trash/trash.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final inMemoryStoreProvider = Provider<InMemoryStore>((ref) {
  final store = InMemoryStore(clock: ref.watch(clockProvider));
  ref.onDispose(store.dispose);
  return store;
});

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => ref.watch(inMemoryStoreProvider),
);

final entryRepositoryProvider = Provider<EntryRepository>(
  (ref) => ref.watch(inMemoryStoreProvider),
);

final trashRepositoryProvider = Provider<TrashRepository>(
  (ref) => ref.watch(inMemoryStoreProvider),
);

/// Only the core's store searches; `InMemoryStore` does not.
final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => throw UnsupportedError('Search needs the core store'),
);
