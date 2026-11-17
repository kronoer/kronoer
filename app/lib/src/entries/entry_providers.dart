import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/storage/storage.dart';

final entriesProvider = StreamProvider.autoDispose.family<List<Entry>, String>(
  (ref, bookId) => ref.watch(entryRepositoryProvider).watchEntries(bookId),
);

final entryProvider = StreamProvider.autoDispose.family<Entry?, String>(
  (ref, id) => ref.watch(entryRepositoryProvider).watchEntry(id),
);
