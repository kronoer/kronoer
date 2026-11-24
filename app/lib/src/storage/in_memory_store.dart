import 'dart:async';
import 'dart:typed_data';

import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/trash/trash.dart';

class InMemoryStore
    implements BookRepository, EntryRepository, TrashRepository {
  InMemoryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _books = <String, Book>{};
  final _entries = <String, Entry>{};
  final _images = <String, ProcessedImage>{};

  /// Each Book's Cover, by Book ID.
  final _covers = <String, ProcessedImage>{};

  /// How many days the Trash keeps what is deleted.
  var _trashDays = defaultTrashDays;

  /// When each Book in the Trash was deleted, by Book ID.
  final _bookTrash = <String, DateTime>{};

  /// When each Entry in the Trash on its own was deleted, by Entry ID. The
  /// Entries that went with their Book have none.
  final _entryTrash = <String, DateTime>{};
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

  /// Whether [entry] is not in the Trash on its own. It may be there with
  /// its Book.
  bool _notTrashedAlone(Entry entry) => !_entryTrash.containsKey(entry.id);

  /// Whether [entry] is not in the Trash, on its own or with its Book.
  bool _notInTrash(Entry entry) =>
      _notTrashedAlone(entry) && !_bookTrash.containsKey(entry.bookId);

  /// The Entries of a Book, without those in the Trash on their own.
  Iterable<Entry> _entriesOf(String bookId) =>
      _entries.values.where((e) => e.bookId == bookId && _notTrashedAlone(e));

  /// The Books not in the Trash and not locked: Pinned Books first, then the
  /// rest, each with the latest activity first.
  List<Book> _booksInOrder() =>
      _books.values
          .where((b) => !b.locked && !_bookTrash.containsKey(b.id))
          .toList()
        ..sort(
          (a, b) => a.pinned != b.pinned
              ? (a.pinned ? -1 : 1)
              : b.lastActivityAt.compareTo(a.lastActivityAt),
        );

  Entry? _lastEntryOf(String bookId) => _entriesOf(bookId).fold<Entry?>(
    null,
    (last, e) => last == null || e.updatedAt.isAfter(last.updatedAt) ? e : last,
  );

  BookSummary _summaryOf(Book book) {
    final last = _lastEntryOf(book.id);
    return BookSummary(
      book: book,
      lastEntryText: last?.text,
      lastEntryImageCount: last?.imageIds.length ?? 0,
      entryCount: _entriesOf(book.id).length,
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
  Future<void> setBooksPinned(
    Iterable<String> ids, {
    required bool pinned,
  }) async {
    final books = [for (final id in ids) _bookOrThrow(id)];
    if (pinned) {
      final after = {
        for (final book in _books.values)
          if (book.pinned) book.id,
        ...ids,
      };
      if (after.length > maxPinnedBooks) throw const TooManyPinnedBooks();
    }
    for (final book in books) {
      _books[book.id] = book.copyWith(pinned: pinned);
    }
    _changes.add(null);
  }

  @override
  Future<void> setBookInTimeline(String id, {required bool inTimeline}) async {
    _books[id] = _bookOrThrow(id).copyWith(inTimeline: inTimeline);
    _changes.add(null);
  }

  @override
  Future<void> setBooksLocked(
    Iterable<String> ids, {
    required bool locked,
  }) async {
    final books = [for (final id in ids) _bookOrThrow(id)];
    for (final book in books) {
      if (book.locked == locked) continue;
      _books[book.id] = book.copyWith(
        locked: locked,
        pinned: locked ? false : book.pinned,
      );
    }
    _changes.add(null);
  }

  @override
  Stream<List<TrashItem>> watchTrash() => _watch(() {
    final items = <TrashItem>[
      for (final MapEntry(key: id, value: deletedAt) in _bookTrash.entries)
        TrashedBook(
          book: _bookOrThrow(id),
          entryCount: _entriesOf(id).length,
          deletedAt: deletedAt,
          purgeAt: deletedAt.add(Duration(days: _trashDays)),
        ),
      for (final MapEntry(key: id, value: deletedAt) in _entryTrash.entries)
        if (_entryOrThrow(id) case final entry)
          TrashedEntry(
            entry: entry,
            bookName: _bookOrThrow(entry.bookId).name,
            bookInTrash: _bookTrash.containsKey(entry.bookId),
            deletedAt: deletedAt,
            purgeAt: deletedAt.add(Duration(days: _trashDays)),
          ),
    ];
    return items..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  });

  @override
  Future<void> trashBook(String id) async {
    final book = _books[id];
    if (book == null || _bookTrash.containsKey(id)) return;
    _bookTrash[id] = _clock();
    _books[id] = book.copyWith(pinned: false, inTimeline: true);
    _changes.add(null);
  }

  @override
  Future<void> trashEntries(Iterable<String> ids) async {
    final now = _clock();
    final books = <String>{};
    for (final id in ids) {
      final entry = _entries[id];
      if (entry == null || !_notInTrash(entry)) continue;
      _entryTrash[id] = now;
      books.add(entry.bookId);
    }
    if (books.isEmpty) return;
    books.forEach(_recomputeActivity);
    _changes.add(null);
  }

  @override
  Future<void> restore({
    Iterable<String> bookIds = const [],
    Iterable<String> entryIds = const [],
    String? othersTo,
  }) async {
    if (othersTo != null) {
      _bookOrThrow(othersTo);
      if (_bookTrash.containsKey(othersTo)) {
        throw StateError('Book $othersTo is in the Trash');
      }
    }
    bookIds.forEach(_bookTrash.remove);
    final books = <String>{};
    for (final id in entryIds) {
      if (_entryTrash.remove(id) == null) continue;
      var entry = _entryOrThrow(id);
      if (_bookTrash.containsKey(entry.bookId)) {
        if (othersTo == null) {
          _bookTrash.remove(entry.bookId);
        } else {
          entry = entry.copyWith(bookId: othersTo);
          _entries[id] = entry;
        }
      }
      books.add(entry.bookId);
    }
    books.forEach(_recomputeActivity);
    _changes.add(null);
  }

  @override
  Future<void> deleteForever({
    Iterable<String> bookIds = const [],
    Iterable<String> entryIds = const [],
  }) async {
    for (final id in bookIds) {
      _books.remove(id);
      _covers.remove(id);
      _bookTrash.remove(id);
      for (final entry in [..._entries.values]) {
        if (entry.bookId == id) _removeEntry(entry.id);
      }
    }
    final books = {
      for (final id in entryIds)
        if (_removeEntry(id) case final removed?) removed.bookId,
    };
    books.forEach(_recomputeActivity);
    _changes.add(null);
  }

  @override
  Future<void> emptyTrash() => deleteForever(
    bookIds: [..._bookTrash.keys],
    entryIds: [..._entryTrash.keys],
  );

  @override
  Stream<int> watchTrashDays() => _watch(() => _trashDays);

  @override
  Future<void> setTrashDays(int days) async {
    if (!trashDayChoices.contains(days)) {
      throw ArgumentError.value(days, 'days', 'not a choice');
    }
    _trashDays = days;
    final before = _clock().subtract(Duration(days: days));
    bool past(MapEntry<String, DateTime> item) => !item.value.isAfter(before);
    await deleteForever(
      bookIds: [for (final item in _bookTrash.entries.where(past)) item.key],
      entryIds: [for (final item in _entryTrash.entries.where(past)) item.key],
    );
  }

  Entry? _removeEntry(String id) {
    final removed = _entries.remove(id);
    _entryTrash.remove(id);
    removed?.imageIds.forEach(_images.remove);
    return removed;
  }

  /// Sets a Book's last activity to that of the Entry changed most recently,
  /// of those not in the Trash on their own; a Book with none keeps its own.
  void _recomputeActivity(String bookId) {
    final last = _lastEntryOf(bookId);
    if (last != null) {
      _books[bookId] = _bookOrThrow(bookId)
          .copyWith(lastActivityAt: last.updatedAt);
    }
  }

  @override
  Future<void> moveEntries(
    Iterable<String> ids, {
    required String toBookId,
  }) async {
    final to = _bookOrThrow(toBookId);
    final moving = [
      for (final id in ids)
        if (_entryOrThrow(id) case final entry when entry.bookId != toBookId)
          entry,
    ];
    if (moving.isEmpty) return;
    var lastActivity = to.lastActivityAt;
    for (final entry in moving) {
      _entries[entry.id] = entry.copyWith(bookId: toBookId);
      if (entry.updatedAt.isAfter(lastActivity)) {
        lastActivity = entry.updatedAt;
      }
    }
    _books[toBookId] = to.copyWith(lastActivityAt: lastActivity);
    final from = {for (final entry in moving) entry.bookId};
    from.forEach(_recomputeActivity);
    _changes.add(null);
  }

  @override
  Future<void> setEntriesStarred(
    Iterable<String> ids, {
    required bool starred,
  }) async {
    final entries = [for (final id in ids) _entryOrThrow(id)];
    final changing = entries.where((e) => e.starred != starred).toList();
    if (changing.isEmpty) return;
    for (final entry in changing) {
      _entries[entry.id] = entry.copyWith(starred: starred);
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
  Future<void> setBookCover(String id, ProcessedImage cover) async {
    final coverId = newId();
    _books[id] = _bookOrThrow(id).copyWith(coverId: () => coverId);
    _covers[id] = cover;
    _changes.add(null);
  }

  @override
  Future<void> removeBookCover(String id) async {
    _books[id] = _bookOrThrow(id).copyWith(coverId: () => null);
    if (_covers.remove(id) != null) _changes.add(null);
  }

  @override
  Future<Uint8List> bookCover(String id, {required bool thumbnail}) async {
    final cover = _covers[id] ?? (throw StateError('Book $id has no Cover'));
    return thumbnail ? cover.thumbnail : cover.full;
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
  Stream<BookInsight> watchBookInsight(String id) => _watch(() {
    final entries = _entriesOf(id);
    return BookInsight(
      entryCount: entries.length,
      wordCount: entries.fold(0, (sum, e) => sum + countWords(text: e.text)),
      imageCount: entries.fold(0, (sum, e) => sum + e.imageIds.length),
    );
  });

  @override
  Stream<List<Book>> watchBooks() => _watch(_booksInOrder);

  @override
  Stream<List<BookSummary>> watchBookSummaries() =>
      _watch(() => [for (final book in _booksInOrder()) _summaryOf(book)]);

  @override
  Stream<List<BookSummary>> watchLockedBookSummaries() => _watch(
    () => [
      for (final book
          in _books.values
              .where((b) => b.locked && !_bookTrash.containsKey(b.id))
              .toList()
            ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt)))
        _summaryOf(book),
    ],
  );

  @override
  Stream<List<Entry>> watchEntries(
    String bookId, {
    EntryOrder order = EntryOrder.newestFirst,
  }) => _watch(() => _entriesOf(bookId).toList()..sort(order.compare));

  @override
  Stream<List<Entry>> watchAllEntries({
    EntryOrder order = EntryOrder.newestFirst,
  }) => _watch(
    () =>
        _entries.values
            .where(
              (e) => _notInTrash(e) && (_books[e.bookId]?.inTimeline ?? true),
            )
            .toList()
          ..sort(order.compare),
  );

  /// The local days of the Entries in the Timeline.
  Iterable<DateTime> _timelineDays() => _entries.values
      .where((e) => _notInTrash(e) && (_books[e.bookId]?.inTimeline ?? true))
      .map((e) {
        final local = e.dateTime.toLocal();
        return DateTime(local.year, local.month, local.day);
      });

  @override
  Stream<DateTime?> watchOldestTimelineDay() => _watch(
    () => _timelineDays().fold<DateTime?>(
      null,
      (oldest, day) => oldest == null || day.isBefore(oldest) ? day : oldest,
    ),
  );

  @override
  Stream<Set<DateTime>> watchTimelineDays(DateTime from, DateTime to) => _watch(
    () => {
      for (final day in _timelineDays())
        if (!day.isBefore(from) && !day.isAfter(to)) day,
    },
  );

  @override
  Stream<List<Entry>> watchStarredEntries(String bookId) => _watch(
    () =>
        _entriesOf(bookId).where((e) => e.starred).toList()
          ..sort(EntryOrder.newestFirst.compare),
  );

  @override
  Stream<Entry?> watchEntry(String id) => _watch(() => _entries[id]);
}
