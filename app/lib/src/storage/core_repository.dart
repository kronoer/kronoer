import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/search/search.dart';
import 'package:kronoer/src/storage/entry_date.dart';
import 'package:kronoer/src/trash/trash.dart';

/// Books and Entries in the core's encrypted store. Every watch reads again
/// after each commit the store reports.
class CoreRepository
    implements
        BookRepository,
        EntryRepository,
        SearchRepository,
        TrashRepository {
  /// [pageSize] is how many Entries one read asks the core for.
  CoreRepository(
    this._store, {
    DateTime Function()? clock,
    @visibleForTesting this._pageSize = 500,
  }) : _clock = clock ?? DateTime.now {
    _subscription = _store.watch().listen((_) => _changes.add(null));
  }

  final int _pageSize;
  final CoreStore _store;
  final DateTime Function() _clock;
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<StoreChange> _subscription;

  void dispose() {
    // The bridge's stream only finishes cancelling once Rust closes it.
    unawaited(_subscription.cancel());
    unawaited(_changes.close());
  }

  /// The result of [read] now and after every commit. Reads run one after
  /// another, so an older result never replaces a newer one.
  Stream<T> _watch<T>(Future<T> Function() read) => Stream.multi((listener) {
    var pending = Future<void>.value();
    void schedule() {
      pending = pending.then((_) async {
        try {
          final value = await read();
          if (!listener.isClosed) listener.add(value);
        } catch (error, stackTrace) {
          if (!listener.isClosed) listener.addError(error, stackTrace);
        }
      });
    }

    schedule();
    final subscription = _changes.stream.listen((_) => schedule());
    listener.onCancel = subscription.cancel;
  });

  @override
  Stream<List<Book>> watchBooks() => _watch(
    () async => [for (final item in await _store.listBooks()) _book(item)],
  );

  @override
  Stream<List<BookSummary>> watchBookSummaries() => _watch(
    () async => [for (final item in await _store.listBooks()) _summary(item)],
  );

  @override
  Stream<List<BookSummary>> watchLockedBookSummaries() => _watch(
    () async => [
      for (final item in await _store.listLockedBooks()) _summary(item),
    ],
  );

  BookSummary _summary(BookItem item) => BookSummary(
    book: _book(item),
    lastEntryText: item.lastEntryText,
    lastEntryImageCount: item.lastEntryImageCount,
    entryCount: item.entryCount,
  );

  @override
  Stream<Book?> watchBook(String id) =>
      _watch(() => _orNull(() async => _book(await _store.getBook(id: id))));

  @override
  Stream<BookInsight> watchBookInsight(String id) => _watch(() async {
    final insight = await _orNull(() => _store.bookInsight(id: id));
    return insight == null
        ? const BookInsight()
        : BookInsight(
            entryCount: insight.entryCount,
            wordCount: insight.wordCount,
            imageCount: insight.imageCount,
          );
  });

  @override
  Future<Book> createBook(String name) async =>
      _book(await _store.createBook(name: name));

  @override
  Future<void> renameBook(String id, String name) =>
      _store.renameBook(id: id, name: name);

  @override
  Future<void> setBookDescription(String id, String description) =>
      _store.setBookDescription(id: id, description: description);

  @override
  Future<void> setBookCover(String id, ProcessedImage cover) =>
      _store.setBookCover(id: id, full: cover.full, thumbnail: cover.thumbnail);

  @override
  Future<void> removeBookCover(String id) => _store.removeBookCover(id: id);

  @override
  Future<Uint8List> bookCover(String id, {required bool thumbnail}) =>
      _store.getBookCover(id: id, thumbnail: thumbnail);

  @override
  Future<void> setBooksPinned(
    Iterable<String> ids, {
    required bool pinned,
  }) async {
    try {
      await _store.setBooksPinned(ids: ids.toList(), pinned: pinned);
    } on StoreFailure catch (failure) {
      if (failure.kind == StoreFailureKind.tooManyPinned) {
        throw const TooManyPinnedBooks();
      }
      rethrow;
    }
  }

  @override
  Future<void> setBookInTimeline(String id, {required bool inTimeline}) =>
      _store.setBookInTimeline(id: id, inTimeline: inTimeline);

  @override
  Future<void> setBooksLocked(Iterable<String> ids, {required bool locked}) =>
      _store.setBooksLocked(ids: ids.toList(), locked: locked);

  @override
  Stream<List<TrashItem>> watchTrash() => _watch(
    () async => [for (final item in await _store.listTrash()) _trashItem(item)],
  );

  @override
  Future<void> trashBook(String id) => _store.trashBook(id: id);

  @override
  Future<void> trashEntries(Iterable<String> ids) =>
      _store.trashEntries(ids: ids.toList());

  @override
  Future<void> restore({
    Iterable<String> bookIds = const [],
    Iterable<String> entryIds = const [],
    String? othersTo,
  }) => _store.restore(
    bookIds: bookIds.toList(),
    entryIds: entryIds.toList(),
    othersTo: othersTo,
  );

  @override
  Future<void> deleteForever({
    Iterable<String> bookIds = const [],
    Iterable<String> entryIds = const [],
  }) => _store.deleteForever(
    bookIds: bookIds.toList(),
    entryIds: entryIds.toList(),
  );

  @override
  Future<void> emptyTrash() => _store.emptyTrash();

  @override
  Stream<int> watchTrashDays() => _watch(_store.trashDays);

  @override
  Future<void> setTrashDays(int days) async {
    await _store.setTrashDays(days: days);
    // The core tells only of what it deleted; the days left change anyway.
    _changes.add(null);
  }

  static TrashItem _trashItem(TrashedItem item) {
    final deletedAt = DateTime.fromMillisecondsSinceEpoch(item.deletedAt);
    final purgeAt = DateTime.fromMillisecondsSinceEpoch(item.purgeAt);
    if (item.book case final book?) {
      return TrashedBook(
        book: _book(book),
        entryCount: book.entryCount,
        deletedAt: deletedAt,
        purgeAt: purgeAt,
      );
    }
    return TrashedEntry(
      entry: _entry(item.entry!),
      bookName: item.bookName,
      bookInTrash: item.bookInTrash,
      bookLocked: item.bookLocked,
      deletedAt: deletedAt,
      purgeAt: purgeAt,
    );
  }

  @override
  Stream<List<Entry>> watchEntries(
    String bookId, {
    EntryOrder order = EntryOrder.newestFirst,
  }) => _watch(
    () => _everyPage(
      (after) => _store.listEntries(
        bookId: bookId,
        order: _order(order),
        after: after,
        limit: _pageSize,
      ),
    ),
  );

  @override
  Stream<List<Entry>> watchAllEntries({
    EntryOrder order = EntryOrder.newestFirst,
  }) => _watch(
    () => _everyPage(
      (after) => _store.listAllEntries(
        order: _order(order),
        after: after,
        limit: _pageSize,
      ),
    ),
  );

  @override
  Stream<List<Entry>> watchStarredEntries(String bookId) => _watch(
    () => _everyPage(
      (after) => _store.listStarredEntries(
        bookId: bookId,
        after: after,
        limit: _pageSize,
      ),
    ),
  );

  /// This device's UTC offset now, in minutes east.
  int get _utcOffsetMinutes => _clock().timeZoneOffset.inMinutes;

  @override
  Stream<ExportActivity> watchExportActivity({DateTime? since}) =>
      _watch(() async {
        final activity = await _store.exportActivity(
          since: since?.millisecondsSinceEpoch,
        );
        final first = activity.firstCreatedAt;
        return ExportActivity(
          firstCreated: first == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(first),
          createdSince: activity.createdSince,
        );
      });

  @override
  Stream<DateTime?> watchOldestTimelineDay() => _watch(() async {
    final day = await _store.oldestTimelineDay(
      utcOffsetMinutes: _utcOffsetMinutes,
    );
    return day == null ? null : parseDay(day);
  });

  @override
  Stream<Set<DateTime>> watchTimelineDays(DateTime from, DateTime to) => _watch(
    () async => {
      for (final day in await _store.timelineDays(
        from: formatDay(from),
        to: formatDay(to),
        utcOffsetMinutes: _utcOffsetMinutes,
      ))
        parseDay(day),
    },
  );

  /// Every Entry [readPage] lists, one page after the other: each page
  /// starts after the last Entry of the one before.
  Future<List<Entry>> _everyPage(
    Future<List<EntryItem>> Function(EntryCursorItem? after) readPage,
  ) async {
    final entries = <Entry>[];
    EntryCursorItem? after;
    while (true) {
      final page = await readPage(after);
      entries.addAll(page.map(_entry));
      if (page.length < _pageSize) return entries;
      final last = page.last;
      after = EntryCursorItem(
        date: last.date,
        createdAt: last.createdAt,
        id: last.id,
      );
    }
  }

  static EntryOrderItem _order(EntryOrder order) => switch (order) {
    EntryOrder.newestFirst => EntryOrderItem.newestFirst,
    EntryOrder.oldestFirst => EntryOrderItem.oldestFirst,
  };

  @override
  Stream<Entry?> watchEntry(String id) =>
      _watch(() => _orNull(() async => _entry(await _store.getEntry(id: id))));

  @override
  Future<Entry> createEntry({
    required String bookId,
    required String text,
    DateTime? dateTime,
    List<NewImage> images = const [],
  }) async {
    final item = await _store.saveEntry(
      draft: EntryDraftItem(
        bookId: bookId,
        date: formatEntryDate(dateTime ?? _clock()),
        text: text,
        images: images.map(_imageDraft).toList(),
      ),
    );
    return _entry(item);
  }

  @override
  Future<Entry> updateEntry(Entry entry, {List<ImageDraft>? images}) async {
    final item = await _store.saveEntry(
      draft: EntryDraftItem(
        id: entry.id,
        bookId: entry.bookId,
        date: formatEntryDate(entry.dateTime),
        text: entry.text,
        images: [
          for (final ImageDraft image
              in images ?? entry.imageIds.map(KeptImage.new))
            _imageDraft(image),
        ],
      ),
    );
    return _entry(item);
  }

  @override
  Future<void> moveEntries(Iterable<String> ids, {required String toBookId}) =>
      _store.moveEntries(ids: ids.toList(), bookId: toBookId);

  @override
  Future<void> setEntriesStarred(
    Iterable<String> ids, {
    required bool starred,
  }) => _store.setEntriesStarred(ids: ids.toList(), starred: starred);

  @override
  Future<Uint8List> image(
    String entryId,
    String imageId, {
    required bool thumbnail,
  }) =>
      _store.getImage(entryId: entryId, imageId: imageId, thumbnail: thumbnail);

  static final _noBytes = Uint8List(0);

  /// Kept Images go by ID alone: their blobs are not written again.
  static ImageDraftItem _imageDraft(ImageDraft image) => switch (image) {
    KeptImage(:final id) => ImageDraftItem(
      id: id,
      full: _noBytes,
      thumbnail: _noBytes,
    ),
    NewImage(:final image) => ImageDraftItem(
      full: image.full,
      thumbnail: image.thumbnail,
    ),
  };

  @override
  Future<SearchResults> search(
    String query, {
    String? bookId,
    required int limit,
    int offset = 0,
  }) async {
    final page = await _store.search(
      query: query,
      bookId: bookId,
      limit: limit,
      offset: offset,
    );
    return SearchResults(
      hits: [
        for (final hit in page.hits)
          SearchHit(entry: _entry(hit.entry), snippet: hit.snippet),
      ],
      total: page.total,
      perBook: {for (final count in page.perBook) count.bookId: count.count},
    );
  }

  static Future<T?> _orNull<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on StoreFailure catch (failure) {
      if (failure.kind == StoreFailureKind.notFound) return null;
      rethrow;
    }
  }

  static Book _book(BookItem item) => Book(
    id: item.id,
    name: item.name,
    description: item.description,
    coverId: item.coverId,
    lastActivityAt: DateTime.fromMillisecondsSinceEpoch(item.lastActivityAt),
    pinned: item.pinned,
    inTimeline: item.inTimeline,
    locked: item.locked,
  );

  static Entry _entry(EntryItem item) => Entry(
    id: item.id,
    bookId: item.bookId,
    text: item.text,
    dateTime: parseEntryDate(item.date),
    imageIds: List.unmodifiable(item.imageIds),
    createdAt: DateTime.fromMillisecondsSinceEpoch(item.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(item.updatedAt),
    starred: item.starred,
  );
}
