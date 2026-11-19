import 'package:kronoer/src/books/book.dart';

abstract interface class BookRepository {
  Stream<List<Book>> watchBooks();

  Stream<List<BookSummary>> watchBookSummaries();

  Stream<Book?> watchBook(String id);

  Future<Book> createBook(String name);

  Future<void> renameBook(String id, String name);

  Future<void> deleteBook(String id);
}
