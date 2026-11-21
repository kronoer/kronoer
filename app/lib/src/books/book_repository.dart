import 'dart:typed_data';

import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/image_processing.dart';

abstract interface class BookRepository {
  Stream<List<Book>> watchBooks();

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

  Future<void> deleteBook(String id);
}
