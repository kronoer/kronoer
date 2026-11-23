import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/trash/trash.dart';

void main() {
  late DateTime now;
  late InMemoryStore store;

  setUp(() {
    now = DateTime(2026, 11, 17, 9);
    store = InMemoryStore(clock: () => now);
  });
  tearDown(() => store.dispose());

  void later() => now = now.add(const Duration(minutes: 1));

  Future<List<String>> bookNames() async => [
    for (final book in await store.watchBooks().first) book.name,
  ];

  group('Books', () {
    test('start empty', () async {
      expect(await bookNames(), isEmpty);
    });

    test('are listed most recent activity first', () async {
      await store.createBook('A');
      later();
      await store.createBook('B');

      expect(await bookNames(), ['B', 'A']);
    });

    test('get distinct opaque IDs', () async {
      final a = await store.createBook('A');
      final b = await store.createBook('B');

      expect(a.id, isNot(b.id));
      expect(a.id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('rename keeps the ID and the activity time', () async {
      final book = await store.createBook('A');
      later();
      await store.renameBook(book.id, 'A2');

      final renamed = (await store.watchBook(book.id).first)!;
      expect(renamed.name, 'A2');
      expect(renamed.lastActivityAt, book.lastActivityAt);
    });

    test('rename of a missing Book throws', () {
      expect(store.renameBook('missing', 'A'), throwsStateError);
    });

    test('a Description is set, kept by a rename, and removed', () async {
      final book = await store.createBook('A');
      expect(book.description, '');

      await store.setBookDescription(book.id, 'Satu.\nDua.');
      await store.renameBook(book.id, 'A2');
      final described = (await store.watchBook(book.id).first)!;
      expect(described.description, 'Satu.\nDua.');
      expect(described.lastActivityAt, book.lastActivityAt);

      await store.setBookDescription(book.id, '');
      expect((await store.watchBook(book.id).first)!.description, '');
      expect(store.setBookDescription('missing', 'A'), throwsStateError);
    });

    test('a Cover is set with a new ID each time, and removed', () async {
      final book = await store.createBook('A');
      expect(book.coverId, isNull);
      ProcessedImage cover(int byte) => ProcessedImage(
        full: Uint8List.fromList([byte, byte]),
        thumbnail: Uint8List.fromList([byte]),
      );

      await store.setBookCover(book.id, cover(1));
      final first = (await store.watchBook(book.id).first)!.coverId;
      expect(first, isNotNull);
      expect(await store.bookCover(book.id, thumbnail: false), [1, 1]);

      await store.setBookCover(book.id, cover(2));
      final second = (await store.watchBook(book.id).first)!;
      expect(second.coverId, allOf(isNotNull, isNot(first)));
      expect(second.lastActivityAt, book.lastActivityAt);
      expect(await store.bookCover(book.id, thumbnail: true), [2]);

      await store.removeBookCover(book.id);
      expect((await store.watchBook(book.id).first)!.coverId, isNull);
      expect(store.bookCover(book.id, thumbnail: true), throwsStateError);
      expect(store.setBookCover('missing', cover(3)), throwsStateError);
    });

    test('deleting for good removes the Book and its Entries', () async {
      final book = await store.createBook('A');
      final entry = await store.createEntry(bookId: book.id, text: 'x');

      await store.deleteForever(bookIds: [book.id]);

      expect(await bookNames(), isEmpty);
      expect(await store.watchBook(book.id).first, isNull);
      expect(await store.watchEntry(entry.id).first, isNull);
      expect(await store.watchEntries(book.id).first, isEmpty);
    });
  });

  group('Entries', () {
    late Book book;

    setUp(() async {
      book = await store.createBook('A');
    });

    test('date and time default to now', () async {
      final entry = await store.createEntry(bookId: book.id, text: 'x');

      expect(entry.dateTime, now);
      expect(entry.createdAt, now);
      expect(entry.updatedAt, now);
    });

    test('are listed newest date and time first', () async {
      final day = DateTime(2026, 11, 10);
      await store.createEntry(
        bookId: book.id,
        text: 'morning',
        dateTime: day.add(const Duration(hours: 8)),
      );
      await store.createEntry(
        bookId: book.id,
        text: 'last month',
        dateTime: DateTime(2026, 10, 3),
      );
      await store.createEntry(
        bookId: book.id,
        text: 'evening',
        dateTime: day.add(const Duration(hours: 20)),
      );

      final entries = await store.watchEntries(book.id).first;
      expect(
        [for (final e in entries) e.text],
        ['evening', 'morning', 'last month'],
      );
    });

    test(
      'come oldest first when asked, same date in the order written',
      () async {
        final day = DateTime(2026, 11, 10, 8);
        for (final text in ['first', 'second']) {
          later();
          await store.createEntry(bookId: book.id, text: text, dateTime: day);
        }
        later();
        await store.createEntry(
          bookId: book.id,
          text: 'earlier',
          dateTime: DateTime(2026, 11, 9),
        );

        Future<List<String>> texts(EntryOrder order) async => [
          for (final e in await store.watchEntries(book.id, order: order).first)
            e.text,
        ];
        expect(await texts(EntryOrder.oldestFirst), [
          'earlier',
          'first',
          'second',
        ]);
        expect(await texts(EntryOrder.newestFirst), [
          'second',
          'first',
          'earlier',
        ]);
        expect(
          [
            for (final e
                in await store
                    .watchAllEntries(order: EntryOrder.oldestFirst)
                    .first)
              e.text,
          ],
          ['earlier', 'first', 'second'],
        );
      },
    );

    test('are listed per Book', () async {
      final other = await store.createBook('B');
      await store.createEntry(bookId: book.id, text: 'in A');
      await store.createEntry(bookId: other.id, text: 'in B');

      final entries = await store.watchEntries(book.id).first;
      expect([for (final e in entries) e.text], ['in A']);
    });

    test('create in a missing Book throws', () {
      expect(store.createEntry(bookId: 'missing', text: 'x'), throwsStateError);
    });

    test('writing an Entry moves its Book to the top', () async {
      later();
      await store.createBook('B');
      expect(await bookNames(), ['B', 'A']);

      later();
      await store.createEntry(bookId: book.id, text: 'x');
      expect(await bookNames(), ['A', 'B']);
    });

    test('update saves text, date and images, keeps the rest', () async {
      final entry = await store.createEntry(
        bookId: book.id,
        text: 'x',
        imageIds: ['image-1'],
      );
      later();

      await store.updateEntry(
        entry.copyWith(text: 'y', dateTime: DateTime(2026, 1, 1)),
      );

      final updated = (await store.watchEntry(entry.id).first)!;
      expect(updated.text, 'y');
      expect(updated.dateTime, DateTime(2026, 1, 1));
      expect(updated.imageIds, ['image-1']);
      expect(updated.bookId, book.id);
      expect(updated.createdAt, entry.createdAt);
      expect(updated.updatedAt, now);
    });

    test('update of a missing Entry throws', () async {
      final entry = await store.createEntry(bookId: book.id, text: 'x');
      await store.deleteForever(entryIds: [entry.id]);

      expect(store.updateEntry(entry), throwsStateError);
    });

    test(
      'deleting for good removes the Entry; doing it again does nothing',
      () async {
        final entry = await store.createEntry(bookId: book.id, text: 'x');

        await store.deleteForever(entryIds: [entry.id]);
        await store.deleteForever(entryIds: [entry.id]);

        expect(await store.watchEntry(entry.id).first, isNull);
        expect(await store.watchEntries(book.id).first, isEmpty);
      },
    );

    test('images cannot be changed in place', () async {
      final entry = await store.createEntry(
        bookId: book.id,
        text: 'x',
        imageIds: ['image-1'],
      );

      expect(() => entry.imageIds.add('image-2'), throwsUnsupportedError);
    });

    test('deleting an older Entry keeps the activity time', () async {
      final older = await store.createEntry(bookId: book.id, text: 'satu');
      later();
      final newer = await store.createEntry(bookId: book.id, text: 'dua');
      later();

      await store.trashEntries([older.id]);

      final [summary] = await store.watchBookSummaries().first;
      expect(summary.book.lastActivityAt, newer.updatedAt);
      expect(summary.lastEntryText, 'dua');
    });

    test(
      'deleting the last Entry moves activity back to the one before',
      () async {
        final first = await store.createEntry(bookId: book.id, text: 'satu');
        later();
        final second = await store.createEntry(bookId: book.id, text: 'dua');
        later();

        await store.trashEntries([second.id]);

        final [summary] = await store.watchBookSummaries().first;
        expect(summary.lastEntryText, 'satu');
        expect(summary.book.lastActivityAt, first.updatedAt);
      },
    );

    test('deleting the only Entry keeps the Book where it was', () async {
      final entry = await store.createEntry(bookId: book.id, text: 'x');
      final activity = (await store.watchBook(book.id).first)!.lastActivityAt;
      later();

      await store.trashEntries([entry.id]);

      final [summary] = await store.watchBookSummaries().first;
      expect(summary.lastEntryText, isNull);
      expect(summary.book.lastActivityAt, activity);
    });
  });

  group('Book summaries', () {
    test(
      'carry the last written or edited Entry, not the latest date',
      () async {
        final book = await store.createBook('A');
        final first = await store.createEntry(
          bookId: book.id,
          text: 'satu',
          dateTime: DateTime(2020),
        );
        later();
        await store.createEntry(
          bookId: book.id,
          text: 'dua',
          dateTime: DateTime(2026, 11, 17),
        );
        later();
        await store.updateEntry(first.copyWith(text: 'satu lagi'));

        final [summary] = await store.watchBookSummaries().first;
        expect(summary.lastEntryText, 'satu lagi');
        expect(summary.book.lastActivityAt, now);
      },
    );

    test('have no Entry text for an empty Book', () async {
      await store.createBook('A');

      final [summary] = await store.watchBookSummaries().first;
      expect(summary.lastEntryText, isNull);
    });

    test(
      'are ordered like watchBooks and only show their own Entries',
      () async {
        final a = await store.createBook('A');
        later();
        final b = await store.createBook('B');
        later();
        await store.createEntry(bookId: a.id, text: 'in A');
        later();
        await store.createEntry(bookId: b.id, text: 'in B');

        final summaries = await store.watchBookSummaries().first;
        expect([for (final s in summaries) s.book.name], await bookNames());
        expect([for (final s in summaries) s.lastEntryText], ['in B', 'in A']);
      },
    );

    test('are emitted again on every change', () async {
      final texts = store.watchBookSummaries().map(
        (summaries) => [for (final s in summaries) s.lastEntryText],
      );
      final expectation = expectLater(
        texts,
        emitsInOrder([
          isEmpty,
          [null],
          ['x'],
          [null],
        ]),
      );

      final book = await store.createBook('A');
      final entry = await store.createEntry(bookId: book.id, text: 'x');
      await store.deleteForever(entryIds: [entry.id]);
      await expectation;
    });
  });

  test('watchers get the current value, then every change', () async {
    final names = store.watchBooks().map(
      (books) => [for (final book in books) book.name],
    );

    final expectation = expectLater(
      names,
      emitsInOrder([
        isEmpty,
        ['A'],
        ['A2'],
        isEmpty,
      ]),
    );
    final book = await store.createBook('A');
    await store.renameBook(book.id, 'A2');
    await store.trashBook(book.id);
    await expectation;
  });

  group('Trash', () {
    Future<List<String>> trashIds() async => [
      for (final item in await store.watchTrash().first) item.id,
    ];

    test('hides a trashed Entry and brings it back as it was', () async {
      final book = await store.createBook('A');
      final entry = await store.createEntry(
        bookId: book.id,
        text: 'x',
        imageIds: ['image-1'],
      );
      await store.setEntriesStarred([entry.id], starred: true);

      await store.trashEntries([entry.id]);

      expect(await store.watchEntries(book.id).first, isEmpty);
      expect(await store.watchAllEntries().first, isEmpty);
      expect(await trashIds(), [entry.id]);
      final [item as TrashedEntry] = await store.watchTrash().first;
      expect(item.bookName, 'A');
      expect(item.bookInTrash, isFalse);
      expect(item.purgeAt, now.add(const Duration(days: defaultTrashDays)));

      await store.restore(entryIds: [entry.id]);

      final [back] = await store.watchEntries(book.id).first;
      expect(back.starred, isTrue);
      expect(back.imageIds, ['image-1']);
      expect(await trashIds(), isEmpty);
    });

    test('a trashed Book loses its pin and Timeline choice', () async {
      final book = await store.createBook('A');
      await store.createEntry(bookId: book.id, text: 'x');
      await store.setBooksPinned([book.id], pinned: true);
      await store.setBookInTimeline(book.id, inTimeline: false);

      await store.trashBook(book.id);

      expect(await bookNames(), isEmpty);
      final [item as TrashedBook] = await store.watchTrash().first;
      expect(item.entryCount, 1);

      await store.restore(bookIds: [book.id]);

      final restored = (await store.watchBook(book.id).first)!;
      expect(restored.pinned, isFalse);
      expect(restored.inTimeline, isTrue);
      expect(await store.watchAllEntries().first, hasLength(1));
    });

    test('an Entry whose Book is trashed goes elsewhere or with it', () async {
      final a = await store.createBook('A');
      final b = await store.createBook('B');
      final first = await store.createEntry(bookId: a.id, text: '1');
      final second = await store.createEntry(bookId: a.id, text: '2');
      await store.trashEntries([first.id, second.id]);
      later();
      await store.trashBook(a.id);

      expect(
        store.restore(entryIds: [first.id], othersTo: a.id),
        throwsStateError,
      );
      await store.restore(entryIds: [first.id], othersTo: b.id);
      expect((await store.watchEntry(first.id).first)!.bookId, b.id);
      expect(await trashIds(), [a.id, second.id]);

      await store.restore(entryIds: [second.id]);
      expect(await bookNames(), containsAll(['A', 'B']));
      expect(await trashIds(), isEmpty);
    });

    test('deleting for good and emptying leave nothing', () async {
      final book = await store.createBook('A');
      final entry = await store.createEntry(bookId: book.id, text: 'x');
      final other = await store.createEntry(bookId: book.id, text: 'y');
      await store.trashEntries([entry.id, other.id]);

      await store.deleteForever(entryIds: [entry.id]);
      expect(await store.watchEntry(entry.id).first, isNull);
      expect(await trashIds(), [other.id]);

      await store.trashBook(book.id);
      await store.emptyTrash();
      expect(await trashIds(), isEmpty);
      expect(await store.watchBook(book.id).first, isNull);
      expect(await store.watchEntry(other.id).first, isNull);
    });

    test('fewer days delete what is past them at once', () async {
      final book = await store.createBook('A');
      final old = await store.createEntry(bookId: book.id, text: 'x');
      await store.trashEntries([old.id]);
      now = now.add(const Duration(days: 10));
      final recent = await store.createEntry(bookId: book.id, text: 'y');
      await store.trashEntries([recent.id]);

      await store.setTrashDays(90);
      expect(await store.watchTrashDays().first, 90);
      final [newest, _] = await store.watchTrash().first;
      expect(newest.purgeAt, now.add(const Duration(days: 90)));

      await store.setTrashDays(7);
      expect(await trashIds(), [recent.id]);
      expect(await store.watchEntry(old.id).first, isNull);
      expect(() => store.setTrashDays(14), throwsArgumentError);
    });
  });
}
