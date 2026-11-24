import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
    await store.trashEntries(ids: [entry.id]);
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

  test('an Export writes a ZIP Archive and reports its progress', () async {
    final book = await store.createBook(name: 'Kebun');
    await store.saveEntry(
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
    expect(await store.exportableEntryCount(), 1);

    final job = ExportJob();
    addTearDown(job.dispose);
    final path = '${dir.path}${Platform.pathSeparator}kronoer.zip';
    final summary = await store.exportArchiveToFile(
      path: path,
      exportedAt: DateTime.utc(2026, 11, 24).millisecondsSinceEpoch,
      job: job,
    );

    expect(
      (summary.bookCount, summary.entryCount, summary.imageCount),
      (1, 1, 1),
    );
    expect((job.done(), job.total()), (2, 2));
    final bytes = await File(path).readAsBytes();
    expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04], reason: 'a ZIP');
  });

  test('export activity: the first Entry, and how many since', () async {
    var activity = await store.exportActivity();
    expect((activity.firstCreatedAt, activity.createdSince), (null, 0));

    final book = await store.createBook(name: 'Kebun');
    final entry = await store.saveEntry(
      draft: EntryDraftItem(
        bookId: book.id,
        date: '2026-11-17T08:00:00+07:00',
        text: 'Tomat mulai merah.',
        images: const [],
      ),
    );

    activity = await store.exportActivity();
    expect(
      (activity.firstCreatedAt, activity.createdSince),
      (entry.createdAt, 1),
    );
    activity = await store.exportActivity(since: entry.createdAt);
    expect(
      (activity.firstCreatedAt, activity.createdSince),
      (entry.createdAt, 0),
    );
  });

  test('a cancelled Export fails with Cancelled', () async {
    final book = await store.createBook(name: 'Kebun');
    await store.saveEntry(
      draft: EntryDraftItem(
        bookId: book.id,
        date: '2026-11-17T08:00:00+07:00',
        text: 'Tomat mulai merah.',
        images: const [],
      ),
    );
    final job = ExportJob()..cancel();
    addTearDown(job.dispose);

    await expectLater(
      store.exportArchiveToFile(
        path: '${dir.path}${Platform.pathSeparator}kronoer.zip',
        exportedAt: 0,
        job: job,
      ),
      throwsA(
        isA<StoreFailure>().having(
          (failure) => failure.kind,
          'kind',
          StoreFailureKind.cancelled,
        ),
      ),
    );
  });

  test(
    'an Archive from another store imports, and a second time adds nothing',
    () async {
      final book = await store.createBook(name: 'Kebun');
      final photo = img.encodeJpg(img.Image(width: 40, height: 30));
      await store.saveEntry(
        draft: EntryDraftItem(
          bookId: book.id,
          date: '2026-11-17T08:00:00+07:00',
          text: 'Tomat mulai merah.',
          images: [
            ImageDraftItem(full: photo, thumbnail: Uint8List.fromList([4])),
          ],
        ),
      );
      final exportJob = ExportJob();
      addTearDown(exportJob.dispose);
      final path = '${dir.path}${Platform.pathSeparator}kronoer.zip';
      await store.exportArchiveToFile(
        path: path,
        exportedAt: 0,
        job: exportJob,
      );

      final otherDir = await Directory.systemTemp.createTemp('kronoer_import');
      final other = await CoreStore.open(
        dir: otherDir.path,
        keyring: Keyring.generate(),
      );
      addTearDown(other.dispose);
      final job = ImportJob();
      addTearDown(job.dispose);
      final summary = await other.importArchiveFromFile(path: path, job: job);

      expect(
        (summary.bookCount, summary.entryCount, summary.imageCount),
        (1, 1, 1),
      );
      final imported = summary.books.single;
      expect(
        (imported.id, imported.name, imported.added),
        (book.id, 'Kebun', true),
      );
      expect(imported.addedEntryCount, 1);
      final progress = job.progress();
      expect(progress.checked, isTrue);
      expect((progress.newEntryCount, progress.done), (1, 1));
      expect((await other.listBooks()).single.entryCount, 1);

      final again = ImportJob();
      addTearDown(again.dispose);
      final second = await other.importArchiveFromFile(path: path, job: again);
      expect(second.books.single.addedEntryCount, 0);
      expect(second.books.single.existingEntryCount, 1);
    },
  );

  test('a file that is not an Archive fails with ArchiveDamaged', () async {
    final path = '${dir.path}${Platform.pathSeparator}notes.zip';
    await File(path).writeAsString('not a zip');
    final job = ImportJob();
    addTearDown(job.dispose);

    await expectLater(
      store.importArchiveFromFile(path: path, job: job),
      throwsA(
        isA<StoreFailure>().having(
          (failure) => failure.kind,
          'kind',
          StoreFailureKind.archiveDamaged,
        ),
      ),
    );
    expect(await store.listBooks(), isEmpty);
  });
}
