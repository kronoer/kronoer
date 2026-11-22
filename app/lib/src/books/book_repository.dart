import 'dart:typed_data';

import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/image_processing.dart';

/// How many Books can be pinned at once.
const maxPinnedBooks = 3;

/// Pinning would make more than [maxPinnedBooks] Pinned Books, so none was
/// pinned.
class TooManyPinnedBooks implements Exception {
  const TooManyPinnedBooks();
}

abstract interface class BookRepository {
  /// Every Book: the Pinned Books first, then the rest, each with the latest
  /// activity first.
  Stream<List<Book>> watchBooks();

  /// [watchBooks], with each Book's latest Entry and Entry count.
  Stream<List<BookSummary>> watchBookSummaries();

  Stream<Book?> watchBook(String id);

  Future<Book> createBook(String name);

  Future<void> renameBook(String id, String name);

  /// Sets a Book's Description; an empty one removes it.
  Future<void> setBookDescription(String id, String description);

  /// Gives a Book a new Cover, in place of the one it had.
  Future<void> setBookCover(String id, ProcessedImage cover);

  /// Removes a Book's Cover; a Book without one stays as it is.
  Future<void> removeBookCover(String id);

  /// The bytes of a Book's Cover, at full size or as its thumbnail.
  Future<Uint8List> bookCover(String id, {required bool thumbnail});

  /// Pins or unpins Books on this device. Throws [TooManyPinnedBooks],
  /// pinning none of them, if that would make more than [maxPinnedBooks].
  Future<void> setBooksPinned(Iterable<String> ids, {required bool pinned});

  Future<void> deleteBook(String id);
}
