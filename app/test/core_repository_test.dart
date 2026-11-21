import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/storage/core_repository.dart';
import 'package:kronoer/src/storage/entry_date.dart';

void main() {
  late Directory dir;
  late CoreStore store;
  late CoreRepository repository;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kronoer_repository_test');
    store = await CoreStore.open(dir: dir.path, keyring: Keyring.generate());
    repository = CoreRepository(store, pageSize: 2);
  });

  tearDown(() async {
    repository.dispose();
    store.dispose();
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the database file open; the system cleans its temp folder.
    }
  });

  /// The first value [stream] gives that passes [test].
  Future<T> firstWhere<T>(Stream<T> stream, bool Function(T) test) =>
      stream.firstWhere(test).timeout(const Duration(seconds: 5));

  test('watching Books follows every change', () async {
    final names = repository.watchBooks().map(
      (books) => [for (final book in books) book.name],
    );
    final seen = <List<String>>[];
    final subscription = names.listen(seen.add);
    addTearDown(subscription.cancel);

    /// Waits until this one subscription has shown [expected].
    Future<void> shows(List<String> expected) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (seen.isEmpty || !listEquals(seen.last, expected)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Saw $seen, never $expected');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    await shows([]);
    final book = await repository.createBook('Kebun');
    await shows(['Kebun']);
    await repository.renameBook(book.id, 'Kebun belakang');
    await shows(['Kebun belakang']);
    await repository.deleteBook(book.id);
    await shows([]);
  });

  test('a Book has a Description', () async {
    final book = await repository.createBook('Kebun');
    expect(book.description, '');

    await repository.setBookDescription(book.id, 'Sayur.\nBunga.');
    expect(
      (await repository.watchBook(book.id).first)!.description,
      'Sayur.\nBunga.',
    );
    await repository.setBookDescription(book.id, '');
    expect((await repository.watchBook(book.id).first)!.description, '');
  });

  test('a Book Cover is set, replaced, read back, and removed', () async {
    final book = await repository.createBook('Kebun');
    expect(book.coverId, isNull);
    ProcessedImage cover(int byte) => ProcessedImage(
      full: Uint8List.fromList([byte, byte]),
      thumbnail: Uint8List.fromList([byte]),
    );

    await repository.setBookCover(book.id, cover(1));
    final first = (await repository.watchBook(book.id).first)!.coverId;
    expect(first, isNotNull);
    expect(await repository.bookCover(book.id, thumbnail: false), [1, 1]);
    expect(await repository.bookCover(book.id, thumbnail: true), [1]);

    await repository.setBookCover(book.id, cover(2));
    final summary = (await repository.watchBookSummaries().first).single;
    expect(summary.book.coverId, allOf(isNotNull, isNot(first)));
    expect(await repository.bookCover(book.id, thumbnail: true), [2]);

    await repository.removeBookCover(book.id);
    expect((await repository.watchBook(book.id).first)!.coverId, isNull);
    expect(
      repository.bookCover(book.id, thumbnail: true),
      throwsA(isA<StoreFailure>()),
    );
  });

  test('a Book summary shows its latest Entry', () async {
    final book = await repository.createBook('Kebun');
    await repository.createEntry(
      bookId: book.id,
      text: 'Tomat mulai merah.',
      dateTime: DateTime(2026, 11, 17, 8),
    );

    final summaries = await repository.watchBookSummaries().first;
    expect(summaries.single.book.id, book.id);
    expect(summaries.single.lastEntryText, 'Tomat mulai merah.');
  });

  test('a missing or deleted Book or Entry watches as null', () async {
    expect(await repository.watchBook(newId()).first, isNull);
    expect(await repository.watchEntry(newId()).first, isNull);

    final book = await repository.createBook('Kebun');
    final entry = await repository.createEntry(bookId: book.id, text: 'Hai');
    final watched = repository.watchEntry(entry.id);
    expect((await watched.first)?.text, 'Hai');

    await repository.deleteEntry(entry.id);
    expect(await firstWhere(watched, (entry) => entry == null), isNull);
  });

  test('Entries come newest first across pages', () async {
    final book = await repository.createBook('Kebun');
    for (var day = 1; day <= 5; day++) {
      await repository.createEntry(
        bookId: book.id,
        text: 'Hari $day',
        dateTime: DateTime(2026, 11, day, 7, 30),
      );
    }

    final entries = await repository.watchEntries(book.id).first;
    expect(entries.map((entry) => entry.text), [
      'Hari 5',
      'Hari 4',
      'Hari 3',
      'Hari 2',
      'Hari 1',
    ]);
    expect(entries.first.dateTime, DateTime(2026, 11, 5, 7, 30));
  });

  test(
    'the Timeline has every Book\'s Entries, newest first across pages',
    () async {
      final kebun = await repository.createBook('Kebun');
      final jalan = await repository.createBook('Jalan');
      for (final (book, day) in [
        (kebun, 3),
        (jalan, 5),
        (kebun, 1),
        (jalan, 2),
        (kebun, 4),
      ]) {
        await repository.createEntry(
          bookId: book.id,
          text: 'Hari $day',
          dateTime: DateTime(2026, 11, day, 7, 30),
        );
      }

      final entries = await repository.watchAllEntries().first;
      expect(
        [for (final entry in entries) (entry.text, entry.bookId)],
        [
          ('Hari 5', jalan.id),
          ('Hari 4', kebun.id),
          ('Hari 3', kebun.id),
          ('Hari 2', jalan.id),
          ('Hari 1', kebun.id),
        ],
      );
    },
  );

  test('Entries come oldest first across pages when asked', () async {
    final kebun = await repository.createBook('Kebun');
    final jalan = await repository.createBook('Jalan');
    for (final (book, day) in [
      (kebun, 3),
      (jalan, 5),
      (kebun, 1),
      (kebun, 4),
    ]) {
      await repository.createEntry(
        bookId: book.id,
        text: 'Hari $day',
        dateTime: DateTime(2026, 11, day, 7, 30),
      );
    }

    final inBook = await repository
        .watchEntries(kebun.id, order: EntryOrder.oldestFirst)
        .first;
    expect(inBook.map((entry) => entry.text), ['Hari 1', 'Hari 3', 'Hari 4']);
    final timeline = await repository
        .watchAllEntries(order: EntryOrder.oldestFirst)
        .first;
    expect(timeline.map((entry) => entry.text), [
      'Hari 1',
      'Hari 3',
      'Hari 4',
      'Hari 5',
    ]);
  });

  test('Entries with the same date come in the order written', () async {
    final book = await repository.createBook('Kebun');
    final sameTime = DateTime(2026, 11, 17, 8);
    for (final text in ['Pertama', 'Kedua', 'Ketiga']) {
      // A little apart, so each is written at a later millisecond.
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await repository.createEntry(
        bookId: book.id,
        text: text,
        dateTime: sameTime,
      );
    }

    final newest = await repository.watchEntries(book.id).first;
    expect(newest.map((entry) => entry.text), ['Ketiga', 'Kedua', 'Pertama']);
    final oldest = await repository
        .watchEntries(book.id, order: EntryOrder.oldestFirst)
        .first;
    expect(oldest.map((entry) => entry.text), ['Pertama', 'Kedua', 'Ketiga']);
  });

  test('a new Entry takes the clock when no date is given', () async {
    final now = DateTime(2026, 11, 19, 21, 15, 42, 123);
    final clocked = CoreRepository(store, clock: () => now);
    addTearDown(clocked.dispose);

    final book = await clocked.createBook('Kebun');
    final entry = await clocked.createEntry(bookId: book.id, text: 'Malam');
    expect(entry.dateTime, DateTime(2026, 11, 19, 21, 15, 42));
  });

  NewImage image(int byte) => NewImage(
    ProcessedImage(
      full: Uint8List.fromList([byte, byte]),
      thumbnail: Uint8List.fromList([byte]),
    ),
  );

  test('a Book summary counts the Images of its latest Entry', () async {
    final empty = await repository.createBook('Kosong');
    final book = await repository.createBook('Kebun');
    await repository.createEntry(
      bookId: book.id,
      text: '',
      images: [image(1), image(2)],
    );

    final summaries = {
      for (final summary in await repository.watchBookSummaries().first)
        summary.book.id: summary,
    };
    expect(summaries[book.id]!.lastEntryText, '');
    expect(summaries[book.id]!.lastEntryImageCount, 2);
    expect(summaries[empty.id]!.lastEntryText, isNull);
    expect(summaries[empty.id]!.lastEntryImageCount, 0);
  });

  test('Images are saved, moved, removed, and read back in order', () async {
    final book = await repository.createBook('Kebun');
    final created = await repository.createEntry(
      bookId: book.id,
      text: 'Tiga foto.',
      images: [image(1), image(2), image(3)],
    );
    final [a, b, c] = created.imageIds;
    expect(await repository.image(created.id, b, thumbnail: false), [2, 2]);
    expect(await repository.image(created.id, b, thumbnail: true), [2]);

    final updated = await repository.updateEntry(
      created,
      images: [KeptImage(c), image(4), KeptImage(a)],
    );
    expect(updated.imageIds, hasLength(3));
    expect([updated.imageIds[0], updated.imageIds[2]], [c, a]);

    final reopened = (await repository.watchEntry(created.id).first)!;
    expect(reopened.imageIds, updated.imageIds);
    expect(
      [
        for (final id in reopened.imageIds)
          await repository.image(created.id, id, thumbnail: true),
      ],
      [
        [3],
        [4],
        [1],
      ],
    );
    expect(
      repository.image(created.id, b, thumbnail: true),
      throwsA(isA<StoreFailure>()),
    );
  });

  test('editing an Entry keeps its images', () async {
    final book = await repository.createBook('Kebun');
    final saved = await store.saveEntry(
      draft: EntryDraftItem(
        bookId: book.id,
        date: '2026-11-17T08:00:00+07:00',
        text: 'Tomat.',
        images: [
          ImageDraftItem(
            full: Uint8List.fromList([1, 2, 3]),
            thumbnail: Uint8List.fromList([4]),
          ),
        ],
      ),
    );
    final entry = (await repository.watchEntry(saved.id).first)!;

    await repository.updateEntry(entry.copyWith(text: 'Tomat merah.'));

    final edited = await store.getEntry(id: saved.id);
    expect(edited.text, 'Tomat merah.');
    expect(edited.imageIds, saved.imageIds);
    expect(
      await store.getImage(
        entryId: saved.id,
        imageId: saved.imageIds.single,
        thumbnail: false,
      ),
      [1, 2, 3],
    );
  });

  test('the device store only opens on a device', () {
    expect(
      openDeviceStore(),
      throwsA(
        isA<StoreFailure>().having(
          (failure) => failure.kind,
          'kind',
          StoreFailureKind.unsupported,
        ),
      ),
    );
  });

  test('Entry dates keep their moment and offset', () {
    final time = DateTime(2026, 11, 19, 6, 5, 4, 999);
    final text = formatEntryDate(time);
    expect(text, matches(RegExp(r'^2026-11-19T06:05:04[+-]\d\d:\d\d$')));
    expect(parseEntryDate(text), DateTime(2026, 11, 19, 6, 5, 4));
    expect(
      parseEntryDate('2026-11-19T08:00:00+07:00'),
      DateTime.utc(2026, 11, 19, 1).toLocal(),
    );
  });
}
