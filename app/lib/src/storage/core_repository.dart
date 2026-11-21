import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/search/search.dart';
import 'package:kronoer/src/storage/entry_date.dart';

/// Books and Entries in the core's encrypted store. Every watch reads again
/// after each commit the store reports.
class CoreRepository
    implements BookRepository, EntryRepository, SearchRepository {
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
    () async => [
      for (final item in await _store.listBooks())
        BookSummary(
          book: _book(item),
          lastEntryText: item.lastEntryText,
          lastEntryImageCount: item.lastEntryImageCount,
        ),
    ],
  );

  @override
  Stream<Book?> watchBook(String id) =>
      _watch(() => _orNull(() async => _book(await _store.getBook(id: id))));

  @override
  Future<Book> createBook(String name) async =>
      _book(await _store.createBook(name: name));

  @override
  Future<void> renameBook(String id, String name) =>
      _store.renameBook(id: id, name: name);

  @override
  Future<void> deleteBook(String id) => _store.deleteBook(id: id);

  @override
  Stream<List<Entry>> watchEntries(String bookId) => _watch(
    () => _everyPage(
      (after) => _store.listEntries(
        bookId: bookId,
        afterDate: after?.date,
        afterId: after?.id,
        limit: _pageSize,
      ),
    ),
  );

  @override
  Stream<List<Entry>> watchAllEntries() => _watch(
    () => _everyPage(
      (after) => _store.listAllEntries(
        afterDate: after?.date,
        afterId: after?.id,
        limit: _pageSize,
      ),
    ),
  );

  /// Every Entry [readPage] lists, one page after the other: each page
  /// starts after the last Entry of the one before.
  Future<List<Entry>> _everyPage(
    Future<List<EntryItem>> Function(EntryItem? after) readPage,
  ) async {
    final entries = <Entry>[];
    EntryItem? last;
    while (true) {
      final page = await readPage(last);
      entries.addAll(page.map(_entry));
      if (page.length < _pageSize) return entries;
      last = page.last;
    }
  }

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
  Future<void> deleteEntry(String id) => _store.deleteEntry(id: id);

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
    lastActivityAt: DateTime.fromMillisecondsSinceEpoch(item.lastActivityAt),
  );

  static Entry _entry(EntryItem item) => Entry(
    id: item.id,
    bookId: item.bookId,
    text: item.text,
    dateTime: parseEntryDate(item.date),
    imageIds: List.unmodifiable(item.imageIds),
    createdAt: DateTime.fromMillisecondsSinceEpoch(item.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(item.updatedAt),
  );
}
