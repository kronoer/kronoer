import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_deletion.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/storage/storage.dart';

export 'package:kronoer/src/entries/entry_repository.dart' show EntryOrder;

/// The order a screen lists its Entries in, newest first until changed.
///
/// It is not stored: it lasts as long as the screen that watches it. A Book's
/// order is gone once the Book screen closes; the Timeline's, once the app
/// does.
class EntryOrderNotifier extends Notifier<EntryOrder> {
  @override
  EntryOrder build() => EntryOrder.newestFirst;

  void set(EntryOrder order) => state = order;
}

/// The order of one Book's Entries on its screen.
final bookEntryOrderProvider = NotifierProvider.autoDispose
    .family<EntryOrderNotifier, EntryOrder, String>(
      (_) => EntryOrderNotifier(),
    );

/// The order of the Timeline.
final timelineOrderProvider =
    NotifierProvider.autoDispose<EntryOrderNotifier, EntryOrder>(
      EntryOrderNotifier.new,
    );

final _storedEntriesProvider = StreamProvider.autoDispose
    .family<List<Entry>, String>(
      (ref, bookId) => ref
          .watch(entryRepositoryProvider)
          .watchEntries(
            bookId,
            order: ref.watch(bookEntryOrderProvider(bookId)),
          ),
    );

/// The Entries of one Book in the order its screen shows, without those
/// waiting to be deleted.
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
  (ref) => ref
      .watch(entryRepositoryProvider)
      .watchAllEntries(order: ref.watch(timelineOrderProvider)),
);

/// The Entries of every Book in the order the Timeline shows, without those
/// waiting to be deleted.
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
