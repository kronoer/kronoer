import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_deletion.dart';
import 'package:kronoer/src/storage/storage.dart';

final _storedEntriesProvider = StreamProvider.autoDispose
    .family<List<Entry>, String>(
      (ref, bookId) => ref.watch(entryRepositoryProvider).watchEntries(bookId),
    );

/// The Entries of one Book, without those waiting to be deleted.
final entriesProvider = Provider.autoDispose
    .family<AsyncValue<List<Entry>>, String>((ref, bookId) {
      final pending = ref.watch(pendingDeletionsProvider);
      return ref
          .watch(_storedEntriesProvider(bookId))
          .whenData(
            (entries) => [
              for (final entry in entries)
                if (!pending.contains(entry.id)) entry,
            ],
          );
    });

final _storedAllEntriesProvider = StreamProvider.autoDispose<List<Entry>>(
  (ref) => ref.watch(entryRepositoryProvider).watchAllEntries(),
);

/// The Entries of every Book, without those waiting to be deleted: the
/// Timeline.
final allEntriesProvider = Provider.autoDispose<AsyncValue<List<Entry>>>((ref) {
  final pending = ref.watch(pendingDeletionsProvider);
  return ref
      .watch(_storedAllEntriesProvider)
      .whenData(
        (entries) => [
          for (final entry in entries)
            if (!pending.contains(entry.id)) entry,
        ],
      );
});

final entryProvider = StreamProvider.autoDispose.family<Entry?, String>(
  (ref, id) => ref.watch(entryRepositoryProvider).watchEntry(id),
);
