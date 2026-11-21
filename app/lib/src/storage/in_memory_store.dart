import 'dart:async';
import 'dart:typed_data';

import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/rust/api/store.dart';

class InMemoryStore implements BookRepository, EntryRepository {
  InMemoryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _books = <String, Book>{};
  final _entries = <String, Entry>{};
  final _images = <String, ProcessedImage>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  void dispose() => _changes.close();

  Stream<T> _watch<T>(T Function() read) => Stream.multi((listener) {
    listener.add(read());
    final subscription = _changes.stream.listen((_) => listener.add(read()));
    // Not returning the cancel future: it belongs to the root zone, so
    // `.first` would finish outside fake async and hang widget tests.
    listener.onCancel = () => unawaited(subscription.cancel());
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

  BookSummary _summaryOf(Book book) {
    final last = _lastEntryOf(book.id);
    return BookSummary(
      book: book,
      lastEntryText: last?.text,
      lastEntryImageCount: last?.imageIds.length ?? 0,
    );
  }

  @override
  Future<Book> createBook(String name) async {
    final book = Book(id: newId(), name: name, lastActivityAt: _clock());
    _books[book.id] = book;
    _changes.add(null);
    return book;
  }

  /// Stores [images] and returns their new IDs.
  List<String> _storeImages(Iterable<NewImage> images) => [
    for (final image in images) _storeImage(image.image),
  ];

  String _storeImage(ProcessedImage image) {
    final id = newId();
    _images[id] = image;
    return id;
  }

  /// [imageIds] are Images with no bytes, for tests that only need them
  /// listed; they show as Images that cannot be opened.
  @override
  Future<Entry> createEntry({
    required String bookId,
    required String text,
    DateTime? dateTime,
    List<NewImage> images = const [],
    List<String> imageIds = const [],
  }) async {
    _bookOrThrow(bookId);
    final now = _clock();
    final entry = Entry(
      id: newId(),
      bookId: bookId,
      text: text,
      dateTime: dateTime ?? now,
      imageIds: List.unmodifiable([...imageIds, ..._storeImages(images)]),
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
    for (final entry in [..._entries.values]) {
      if (entry.bookId == id) _removeEntry(entry.id);
    }
    _changes.add(null);
  }

  Entry? _removeEntry(String id) {
    final removed = _entries.remove(id);
    removed?.imageIds.forEach(_images.remove);
    return removed;
  }

  @override
  Future<void> deleteEntry(String id) async {
    final removed = _removeEntry(id);
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
  Future<void> setBookDescription(String id, String description) async {
    _books[id] = _bookOrThrow(id).copyWith(description: description);
    _changes.add(null);
  }

  @override
  Future<Entry> updateEntry(Entry entry, {List<ImageDraft>? images}) async {
    final stored = _entryOrThrow(entry.id);
    final drafts = images ?? entry.imageIds.map(KeptImage.new).toList();
    for (final draft in drafts) {
      if (draft is KeptImage && !stored.imageIds.contains(draft.id)) {
        throw StateError('Entry ${entry.id} has no Image ${draft.id}');
      }
    }
    final imageIds = [
      for (final draft in drafts)
        switch (draft) {
          KeptImage(:final id) => id,
          NewImage(:final image) => _storeImage(image),
        },
    ];
    stored.imageIds
        .where((id) => !imageIds.contains(id))
        .forEach(_images.remove);

    final updated = stored.copyWith(
      text: entry.text,
      dateTime: entry.dateTime,
      imageIds: List.unmodifiable(imageIds),
      updatedAt: _clock(),
    );
    _entries[entry.id] = updated;
    _touch(stored.bookId);
    return updated;
  }

  @override
  Future<Uint8List> image(
    String entryId,
    String imageId, {
    required bool thumbnail,
  }) async {
    if (_entries[entryId]?.imageIds.contains(imageId) != true) {
      throw StateError('Entry $entryId has no Image $imageId');
    }
    final image =
        _images[imageId] ?? (throw StateError('Image $imageId has no bytes'));
    return thumbnail ? image.thumbnail : image.full;
  }

  @override
  Stream<Book?> watchBook(String id) => _watch(() => _books[id]);

  @override
  Stream<List<Book>> watchBooks() => _watch(_booksByActivity);

  @override
  Stream<List<BookSummary>> watchBookSummaries() =>
      _watch(() => [for (final book in _booksByActivity()) _summaryOf(book)]);

  @override
  Stream<List<Entry>> watchEntries(String bookId) => _watch(
    () =>
        _entries.values.where((e) => e.bookId == bookId).toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime)),
  );

  @override
  Stream<List<Entry>> watchAllEntries() => _watch(
    () =>
        _entries.values.toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime)),
  );

  @override
  Stream<Entry?> watchEntry(String id) => _watch(() => _entries[id]);
}
