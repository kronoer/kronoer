import 'package:kronoer/src/books/book.dart';

abstract interface class BookRepository {
  Stream<List<Book>> watchBooks();

  Stream<List<BookSummary>> watchBookSummaries();

  Stream<Book?> watchBook(String id);

  Future<Book> createBook(String name);

  Future<void> renameBook(String id, String name);

  /// Sets a Book's Description; an empty one removes it.
  Future<void> setBookDescription(String id, String description);

  Future<void> deleteBook(String id);
}
