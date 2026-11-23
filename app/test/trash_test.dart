import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/trash/restore_to_screen.dart';
import 'package:kronoer/src/trash/trash_screen.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  late DateTime now;
  late InMemoryStore store;
  late Book mine;
  late Book garden;
  late Entry rain;
  late Entry tomato;

  void later() => now = now.add(const Duration(minutes: 1));

  setUp(() async {
    now = DateTime(2026, 11, 22, 9, 30);
    store = InMemoryStore(clock: () => now);
    garden = await store.createBook('Kebun').whenComplete(later);
    mine = await store.createBook('Buku Saya').whenComplete(later);
    rain = await store
        .createEntry(bookId: mine.id, text: 'Pagi ini hujan.')
        .whenComplete(later);
    await store
        .createEntry(bookId: mine.id, text: 'Rapat pagi.')
        .whenComplete(later);
    tomato = await store
        .createEntry(bookId: garden.id, text: 'Tomat berbuah.')
        .whenComplete(later);
  });
  tearDown(() => store.dispose());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => now),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens Pengaturan and scrolls to its Sampah row.
  Future<void> openSettings(WidgetTester tester) async {
    await tap(tester, find.text('Pengaturan'));
    await tester.scrollUntilVisible(
      find.text('Sampah'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  /// Opens Pengaturan, then Sampah, then Book dan Entry.
  Future<void> openTrash(WidgetTester tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tap(tester, find.text('Sampah'));
    await tap(tester, find.text('Book dan Entry'));
    expect(find.byType(TrashListScreen), findsOneWidget);
  }

  Future<List<String>> trashIds() async => [
    for (final item in await store.watchTrash().first) item.id,
  ];

  Future<List<String>> textsIn(Book book) async => [
    for (final entry in await store.watchEntries(book.id).first) entry.text,
  ];

  group('Settings and the hub', () {
    testWidgets('count what is in the Trash', (tester) async {
      await store.trashEntries([rain.id]);
      later();
      await store.trashBook(garden.id);
      await pumpApp(tester);

      await openSettings(tester);
      expect(find.text('2 item · disimpan 30 hari'), findsOneWidget);

      await tap(tester, find.text('Sampah'));
      expect(find.text('2 item'), findsOneWidget);
      expect(
        find.text(
          'Book dan Entry yang dihapus disimpan di sini, lalu hilang '
          'selamanya setelah waktu ini.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty Trash says so', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.text('Kosong · disimpan 30 hari'), findsOneWidget);
      await tap(tester, find.text('Sampah'));
      await tap(tester, find.text('Book dan Entry'));

      expect(find.text('Sampah kosong'), findsOneWidget);
      await tap(tester, find.byTooltip('Opsi lainnya'));
      final empty = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'Kosongkan Sampah'),
      );
      expect(empty.onPressed, isNull);
    });
  });

  group('list', () {
    testWidgets('shows the most recently deleted first, with days left', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      now = now.add(const Duration(days: 10));
      await store.trashBook(garden.id);
      await openTrash(tester);

      final book = tester.getTopLeft(find.text('Kebun'));
      final entry = tester.getTopLeft(find.text('Pagi ini hujan.'));
      expect(book.dy, lessThan(entry.dy));
      expect(find.text('Book · 1 Entry'), findsOneWidget);
      expect(find.text('Tersisa 30 hari'), findsOneWidget);
      expect(find.text('Tersisa 20 hari'), findsOneWidget);
      expect(find.textContaining('· Buku Saya'), findsOneWidget);
    });

    testWidgets('counts its last day as one left', (tester) async {
      await store.trashEntries([rain.id]);
      now = now.add(const Duration(days: 29, hours: 23));
      await openTrash(tester);

      expect(find.text('Tersisa 1 hari'), findsOneWidget);
    });
  });

  group('restore', () {
    testWidgets('an Entry from its view, back to its Book', (tester) async {
      await store.trashEntries([rain.id]);
      await openTrash(tester);

      await tap(tester, find.text('Pagi ini hujan.'));
      expect(find.byType(TrashItemScreen), findsOneWidget);
      expect(find.text('Di Sampah · tersisa 30 hari'), findsOneWidget);
      expect(find.text('Hapus permanen'), findsOneWidget);

      await tap(tester, find.text('Pulihkan'));

      expect(find.byType(TrashListScreen), findsOneWidget);
      expect(find.text('Entry dipulihkan ke Buku Saya'), findsOneWidget);
      expect(find.text('Sampah kosong'), findsOneWidget);
      expect(await textsIn(mine), contains('Pagi ini hujan.'));
    });

    testWidgets('a Book from its view, with its Entries', (tester) async {
      await store.trashBook(garden.id);
      await openTrash(tester);

      await tap(tester, find.text('Kebun'));
      expect(find.text('Book di Sampah'), findsOneWidget);
      expect(find.text('1 Entry · 0 foto'), findsOneWidget);
      expect(
        find.text(
          'Di Sampah · tersisa 30 hari. Pulihkan untuk membaca Entry-nya.',
        ),
        findsOneWidget,
      );

      await tap(tester, find.text('Pulihkan'));

      expect(find.text('“Kebun” dipulihkan'), findsOneWidget);
      expect(await textsIn(garden), ['Tomat berbuah.']);
    });

    testWidgets('several at once from selection mode', (tester) async {
      final meeting = (await store.watchEntries(mine.id).first).firstWhere(
        (entry) => entry.text == 'Rapat pagi.',
      );
      await store.trashEntries([rain.id, meeting.id]);
      await openTrash(tester);

      await tester.longPress(find.text('Pagi ini hujan.'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Rapat pagi.'));
      expect(find.bySemanticsLabel('2 dipilih'), findsOneWidget);

      await tap(tester, find.byTooltip('Pulihkan'));

      expect(find.text('2 Entry dipulihkan ke Buku Saya'), findsOneWidget);
      expect(await trashIds(), isEmpty);
    });

    group('Pulihkan ke, for an Entry whose Book is in the Trash', () {
      Future<void> restoreStranded(WidgetTester tester) async {
        await store.trashEntries([rain.id]);
        later();
        await store.trashBook(mine.id);
        await openTrash(tester);
        await tap(tester, find.text('Pagi ini hujan.'));
        await tap(tester, find.text('Pulihkan'));
        expect(find.byType(RestoreToScreen), findsOneWidget);
      }

      testWidgets('offers its Book first, then the others', (tester) async {
        await restoreStranded(tester);

        expect(
          find.text('Book Entry ini, Buku Saya, juga ada di Sampah.'),
          findsOneWidget,
        );
        expect(
          find.text('Pulihkan Book ini juga, beserta Entry-nya'),
          findsOneWidget,
        );
        expect(find.text('Book lain'), findsOneWidget);
        final own = tester.getTopLeft(find.text('Buku Saya'));
        final other = tester.getTopLeft(find.text('Kebun'));
        expect(own.dy, lessThan(other.dy));
      });

      testWidgets('to another Book', (tester) async {
        await restoreStranded(tester);

        await tap(tester, find.text('Kebun'));

        expect(find.text('Entry dipulihkan ke Kebun'), findsOneWidget);
        expect(await textsIn(garden), contains('Pagi ini hujan.'));
        expect(await trashIds(), [mine.id]);
      });

      testWidgets('with its Book', (tester) async {
        await restoreStranded(tester);

        await tap(tester, find.text('Buku Saya'));

        expect(find.text('Entry dipulihkan ke Buku Saya'), findsOneWidget);
        expect(await textsIn(mine), hasLength(2));
        expect(await trashIds(), isEmpty);
      });

      testWidgets('back restores nothing', (tester) async {
        await restoreStranded(tester);

        await tap(tester, find.byType(BackButton));

        expect(find.byType(TrashItemScreen), findsOneWidget);
        expect(await trashIds(), [mine.id, rain.id]);
      });
    });
  });

  group('delete for good', () {
    testWidgets('an Entry, after asking', (tester) async {
      await store.trashEntries([rain.id]);
      await openTrash(tester);
      await tap(tester, find.text('Pagi ini hujan.'));

      await tap(tester, find.text('Hapus permanen'));
      expect(find.text('Hapus permanen?'), findsOneWidget);
      expect(
        find.text(
          'Entry ini dan fotonya akan hilang selamanya. Ini tidak bisa '
          'dibatalkan.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Hapus'));

      expect(find.byType(TrashListScreen), findsOneWidget);
      expect(await store.watchEntry(rain.id).first, isNull);
    });

    testWidgets('a Book counts its Entries deleted on their own too', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      later();
      await store.trashBook(mine.id);
      await openTrash(tester);
      await tap(tester, find.text('Buku Saya'));

      await tap(tester, find.text('Hapus permanen'));
      expect(
        find.text(
          '“Buku Saya” dan 2 Entry-nya akan hilang selamanya. Ini tidak bisa '
          'dibatalkan.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Hapus'));

      expect(find.text('Sampah kosong'), findsOneWidget);
      expect(await store.watchEntry(rain.id).first, isNull);
    });

    testWidgets('Batal keeps it', (tester) async {
      await store.trashEntries([rain.id]);
      await openTrash(tester);
      await tap(tester, find.text('Pagi ini hujan.'));

      await tap(tester, find.text('Hapus permanen'));
      await tap(tester, find.text('Batal'));

      expect(find.byType(TrashItemScreen), findsOneWidget);
      expect(await trashIds(), [rain.id]);
    });

    testWidgets('several from selection mode', (tester) async {
      await store.trashEntries([rain.id]);
      later();
      await store.trashBook(garden.id);
      await openTrash(tester);

      await tester.longPress(find.text('Kebun'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Pagi ini hujan.'));
      await tap(tester, find.byTooltip('Hapus permanen'));
      expect(
        find.text(
          '2 item ini akan hilang selamanya. Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Hapus'));

      expect(find.text('Sampah kosong'), findsOneWidget);
      expect(await store.watchBook(garden.id).first, isNull);
      expect(await store.watchEntry(tomato.id).first, isNull);
      expect(await store.watchEntry(rain.id).first, isNull);
    });

    testWidgets('Kosongkan Sampah empties it, after asking', (tester) async {
      await store.trashEntries([rain.id]);
      later();
      await store.trashBook(garden.id);
      await openTrash(tester);

      await tap(tester, find.byTooltip('Opsi lainnya'));
      await tap(tester, find.text('Kosongkan Sampah'));
      expect(
        find.text(
          '2 item di Sampah akan hilang selamanya. Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Kosongkan'));

      expect(find.text('Sampah kosong'), findsOneWidget);
      expect(await store.watchBook(garden.id).first, isNull);
      expect(await textsIn(mine), hasLength(1));
    });
  });

  group('Simpan selama', () {
    Future<void> openHub(WidgetTester tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await tap(tester, find.text('Sampah'));
    }

    testWidgets('a longer time asks nothing and shows everywhere', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      await openHub(tester);
      expect(find.text('30 hari'), findsOneWidget);

      await tap(tester, find.text('Simpan selama'));
      expect(
        find.text('Setelah itu, Book dan Entry di Sampah hilang selamanya.'),
        findsOneWidget,
      );
      await tap(tester, find.text('90 hari'));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('90 hari'), findsOneWidget);
      expect(await store.watchTrashDays().first, 90);
      await tap(tester, find.text('Book dan Entry'));
      expect(find.text('Tersisa 90 hari'), findsOneWidget);
      await tap(tester, find.byType(BackButton));
      await tap(tester, find.byType(BackButton));
      expect(find.text('1 item · disimpan 90 hari'), findsOneWidget);
    });

    testWidgets('a shorter time asks first when items would go', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      now = now.add(const Duration(days: 10));
      await store.trashBook(garden.id);
      await openHub(tester);

      await tap(tester, find.text('Simpan selama'));
      await tap(tester, find.text('7 hari'));
      expect(find.text('Simpan 7 hari saja?'), findsOneWidget);
      expect(
        find.text(
          '1 item yang dihapus lebih dari 7 hari lalu akan langsung hilang '
          'selamanya. Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );

      await tap(tester, find.text('Batal'));
      expect(await store.watchTrashDays().first, 30);
      expect(await trashIds(), hasLength(2));

      await tap(tester, find.text('Simpan selama'));
      await tap(tester, find.text('7 hari'));
      await tap(tester, find.text('Ya, ubah'));

      expect(find.text('7 hari'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
      expect(await trashIds(), [garden.id]);
      expect(await store.watchEntry(rain.id).first, isNull);
    });

    testWidgets('a shorter time asks nothing when no item would go', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      await openHub(tester);

      await tap(tester, find.text('Simpan selama'));
      await tap(tester, find.text('7 hari'));

      expect(find.byType(AlertDialog), findsNothing);
      expect(await store.watchTrashDays().first, 7);
      expect(await trashIds(), [rain.id]);
    });

    testWidgets('deleting a Book and the empty Trash name the time', (
      tester,
    ) async {
      await store.setTrashDays(7);
      await pumpApp(tester);

      await tester.longPress(find.text('Kebun'));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Hapus'));
      expect(
        find.text(
          '“Kebun” dan 1 Entry di dalamnya akan disimpan di Sampah selama 7 '
          'hari, lalu hilang selamanya.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Batal'));

      await openSettings(tester);
      expect(find.text('Kosong · disimpan 7 hari'), findsOneWidget);
      await tap(tester, find.text('Sampah'));
      await tap(tester, find.text('Book dan Entry'));
      expect(
        find.text(
          'Book dan Entry yang dihapus disimpan di sini selama 7 hari, lalu '
          'hilang selamanya.',
        ),
        findsOneWidget,
      );
    });
  });
}
