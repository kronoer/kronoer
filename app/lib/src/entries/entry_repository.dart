import 'package:kronoer/src/entries/entry.dart';

abstract interface class EntryRepository {
  Stream<List<Entry>> watchEntries(String bookId);

  Stream<Entry?> watchEntry(String id);

  Future<Entry> createEntry({
    required String bookId,
    required String text,
    DateTime? dateTime,
    List<String> imageIds = const [],
  });

  Future<void> updateEntry(Entry entry);

  Future<void> deleteEntry(String id);
}
