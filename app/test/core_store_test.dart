import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/rust/api/store.dart';

void main() {
  late Directory dir;
  late CoreStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kronoer_store_test');
    store = await CoreStore.open(dir: dir.path, keyring: Keyring.generate());
  });

  tearDown(() async {
    store.dispose();
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the database file open; the system cleans its temp folder.
    }
  });

  test('IDs come from the core', () {
    final id = newId();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(newId(), isNot(id));
  });

  test('Books and Entries round-trip with images', () async {
    final book = await store.createBook(name: 'Kebun');
    final saved = await store.saveEntry(
      draft: EntryDraftItem(
        bookId: book.id,
        date: '2026-11-17T08:00:00+07:00',
        text: 'Tomat mulai merah.',
        images: [
          ImageDraftItem(
            full: Uint8List.fromList([1, 2, 3]),
            thumbnail: Uint8List.fromList([4]),
          ),
        ],
      ),
    );

    final entry = await store.getEntry(id: saved.id);
    expect(entry.text, 'Tomat mulai merah.');
    expect(entry.date, '2026-11-17T08:00:00+07:00');
    expect(entry.bookId, book.id);
    expect(entry.imageIds, saved.imageIds);
    expect(
      await store.getImage(
        entryId: saved.id,
        imageId: saved.imageIds.single,
        thumbnail: false,
      ),
      [1, 2, 3],
    );
    expect(
      await store.getImage(
        entryId: saved.id,
        imageId: saved.imageIds.single,
        thumbnail: true,
      ),
      [4],
    );

    final edited = await store.saveEntry(
      draft: EntryDraftItem(
        id: saved.id,
        bookId: book.id,
        date: '2026-11-17T09:00:00+07:00',
        text: 'Tomat sudah merah.',
        images: [
          ImageDraftItem(
            id: saved.imageIds.single,
            full: Uint8List(0),
            thumbnail: Uint8List(0),
          ),
        ],
      ),
    );
    expect(edited.id, saved.id);
    expect(edited.imageIds, saved.imageIds);
    expect(edited.createdAt, saved.createdAt);

    final books = await store.listBooks();
    expect(books.single.name, 'Kebun');
    expect(books.single.lastEntryText, 'Tomat sudah merah.');
    final entries = await store.listEntries(
      bookId: book.id,
      order: EntryOrderItem.newestFirst,
      limit: 10,
    );
    expect(entries.single.text, 'Tomat sudah merah.');
  });

  test('searches with snippets and counts per Book', () async {
    final garden = await store.createBook(name: 'Kebun');
    final trips = await store.createBook(name: 'Perjalanan');
    for (final (bookId, date, text) in [
      (garden.id, '2026-11-01T08:00:00+07:00', 'Hujan sejak pagi.'),
      (garden.id, '2026-11-03T08:00:00+07:00', 'Pagi cerah.'),
      (trips.id, '2026-11-02T08:00:00+07:00', 'Café di Bandung, pagi sekali.'),
    ]) {
      await store.saveEntry(
        draft: EntryDraftItem(
          bookId: bookId,
          date: date,
          text: text,
          images: const [],
        ),
      );
    }

    final page = await store.search(query: 'pag', limit: 2, offset: 0);
    expect(page.total, 3);
    expect(page.hits.map((hit) => hit.entry.date), [
      '2026-11-03T08:00:00+07:00',
      '2026-11-02T08:00:00+07:00',
    ]);
    expect(page.hits.first.snippet, contains('\u{E000}Pagi\u{E001}'));
    expect(
      {for (final count in page.perBook) count.bookId: count.count},
      {garden.id: 2, trips.id: 1},
    );

    final inTrips = await store.search(
      query: 'cafe',
      bookId: trips.id,
      limit: 10,
      offset: 0,
    );
    expect(inTrips.total, 1);
  });

  test('every commit reaches the change stream', () async {
    final changes = <StoreChange>[];
    final subscription = store.watch().listen(changes.add);

    final book = await store.createBook(name: 'Kebun');
    final entry = await store.saveEntry(
      draft: EntryDraftItem(
        bookId: book.id,
        date: '2026-11-17T08:00:00+07:00',
        text: 'Pagi.',
        images: const [],
      ),
    );
    await store.deleteEntry(id: entry.id);
    await pumpEventQueue();
    // The bridge's stream finishes cancelling only once Rust closes it, so it is not awaited.
    unawaited(subscription.cancel());
    await store.renameBook(id: book.id, name: 'Kebun baru');
    await pumpEventQueue();

    expect(changes.map((change) => (change.bookId, change.entryId)), [
      (book.id, null),
      (book.id, entry.id),
      (book.id, entry.id),
    ]);
  });

  test('a missing Entry fails with NotFound', () async {
    await expectLater(
      store.getEntry(id: newId()),
      throwsA(
        isA<StoreFailure>().having(
          (failure) => failure.kind,
          'kind',
          StoreFailureKind.notFound,
        ),
      ),
    );
  });
}
