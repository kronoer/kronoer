import 'dart:typed_data';

import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/image_processing.dart';

/// One Image of an Entry being saved.
sealed class ImageDraft {
  const ImageDraft();
}

/// An Image the Entry already has. Its blobs are kept as they are.
final class KeptImage extends ImageDraft {
  const KeptImage(this.id);

  final String id;
}

/// A new Image, ready to store.
final class NewImage extends ImageDraft {
  const NewImage(this.image);

  final ProcessedImage image;
}

/// The order a list of Entries comes in, by Entry date and time. Entries
/// with the same date and time come in the order they were written.
enum EntryOrder {
  newestFirst,
  oldestFirst;

  /// Whether [a] comes before [b] in this order: negative if it does.
  int compare(Entry a, Entry b) {
    final oldest = switch (a.dateTime.compareTo(b.dateTime)) {
      0 => switch (a.createdAt.compareTo(b.createdAt)) {
        0 => a.id.compareTo(b.id),
        final byCreation => byCreation,
      },
      final byDate => byDate,
    };
    return this == oldestFirst ? oldest : -oldest;
  }
}

abstract interface class EntryRepository {
  /// The Entries of one Book in [order].
  Stream<List<Entry>> watchEntries(
    String bookId, {
    EntryOrder order = EntryOrder.newestFirst,
  });

  /// The Entries of every Book in [order]: the Timeline.
  Stream<List<Entry>> watchAllEntries({
    EntryOrder order = EntryOrder.newestFirst,
  });

  Stream<Entry?> watchEntry(String id);

  /// Creates an Entry with [images] in this order, and returns it as stored.
  Future<Entry> createEntry({
    required String bookId,
    required String text,
    DateTime? dateTime,
    List<NewImage> images = const [],
  });

  /// Saves [entry]'s text and date, and returns it as stored.
  ///
  /// With [images], the Entry holds those Images in that order: kept ones by
  /// ID, new ones from their bytes, and any other it had is deleted. Without,
  /// it keeps the Images [Entry.imageIds] names.
  Future<Entry> updateEntry(Entry entry, {List<ImageDraft>? images});

  Future<void> deleteEntry(String id);

  /// Deletes Entries with their Images, all of them or none.
  Future<void> deleteEntries(Iterable<String> ids);

  /// Moves Entries to the Book [toBookId], all of them or none. Each keeps its
  /// ID, text, date, Images, and times; one already there stays as it is.
  Future<void> moveEntries(Iterable<String> ids, {required String toBookId});

  /// The bytes of one of an Entry's Images: its thumbnail or the full image.
  Future<Uint8List> image(
    String entryId,
    String imageId, {
    required bool thumbnail,
  });
}
