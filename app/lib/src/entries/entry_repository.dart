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

abstract interface class EntryRepository {
  /// The Entries of one Book, newest Entry date and time first.
  Stream<List<Entry>> watchEntries(String bookId);

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

  /// The bytes of one of an Entry's Images: its thumbnail or the full image.
  Future<Uint8List> image(
    String entryId,
    String imageId, {
    required bool thumbnail,
  });
}
