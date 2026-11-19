import 'dart:async';

import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/storage/ids.dart';

class InMemoryStore implements BookRepository, EntryRepository {
  InMemoryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _books = <String, Book>{};
  final _entries = <String, Entry>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  void dispose() => _changes.close();

  Stream<T> _watch<T>(T Function() read) => Stream.multi((listener) {
    listener.add(read());
    final subscription = _changes.stream.listen((_) => listener.add(read()));
    listener.onCancel = subscription.cancel;
  });

  Book _bookOrThrow(String id) =>
      _books[id] ?? (throw StateError('No Book $id'));

  Entry _entryOrThrow(String id) =>
      _entries[id] ?? (throw StateError('No Entry $id'));

  void _touch(String bookId) {
    _books[bookId] = _bookOrThrow(bookId).copyWith(lastActivityAt: _clock());
    _changes.add(null);
  }

  List<Book> _booksByActivity() =>
      _books.values.toList()
        ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));

  Entry? _lastEntryOf(String bookId) => _entries.values
      .where((e) => e.bookId == bookId)
      .fold<Entry?>(
        null,
        (last, e) =>
            last == null || e.updatedAt.isAfter(last.updatedAt) ? e : last,
      );

  @override
  Future<Book> createBook(String name) async {
    final book = Book(id: newId(), name: name, lastActivityAt: _clock());
    _books[book.id] = book;
    _changes.add(null);
    return book;
  }

  @override
  Future<Entry> createEntry({
    required String bookId,
    required String text,
    DateTime? dateTime,
    List<String> imageIds = const [],
  }) async {
    _bookOrThrow(bookId);
    final now = _clock();
    final entry = Entry(
      id: newId(),
      bookId: bookId,
      text: text,
      dateTime: dateTime ?? now,
      imageIds: List.unmodifiable(imageIds),
      createdAt: now,
      updatedAt: now,
    );

    _entries[entry.id] = entry;
    _touch(bookId);
    return entry;
  }

  @override
  Future<void> deleteBook(String id) async {
    _books.remove(id);
    _entries.removeWhere((_, entry) => entry.bookId == id);
    _changes.add(null);
  }

  @override
  Future<void> deleteEntry(String id) async {
    final removed = _entries.remove(id);
    if (removed == null) return;

    final last = _lastEntryOf(removed.bookId);
    if (last != null) {
      _books[removed.bookId] = _bookOrThrow(removed.bookId)
          .copyWith(lastActivityAt: last.updatedAt);
    }

    _changes.add(null);
  }

  @override
  Future<void> renameBook(String id, String name) async {
    _books[id] = _bookOrThrow(id).copyWith(name: name);
    _changes.add(null);
  }

  @override
  Future<void> updateEntry(Entry entry) async {
    final stored = _entryOrThrow(entry.id);
    _entries[entry.id] = stored.copyWith(
      text: entry.text,
      dateTime: entry.dateTime,
      imageIds: List.unmodifiable(entry.imageIds),
      updatedAt: _clock(),
    );

    _touch(stored.bookId);
  }

  @override
  Stream<Book?> watchBook(String id) => _watch(() => _books[id]);

  @override
  Stream<List<Book>> watchBooks() => _watch(_booksByActivity);

  @override
  Stream<List<BookSummary>> watchBookSummaries() => _watch(
    () => [
      for (final book in _booksByActivity())
        BookSummary(book: book, lastEntryText: _lastEntryOf(book.id)?.text),
    ],
  );

  @override
  Stream<List<Entry>> watchEntries(String bookId) => _watch(
    () =>
        _entries.values.where((e) => e.bookId == bookId).toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime)),
  );

  @override
  Stream<Entry?> watchEntry(String id) => _watch(() => _entries[id]);
}
