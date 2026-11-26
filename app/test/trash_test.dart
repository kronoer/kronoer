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
    mine = await store.createBook('My Book').whenComplete(later);
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
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
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

  /// Opens Settings and scrolls to its Trash row.
  Future<void> openSettings(WidgetTester tester) async {
    await tap(tester, find.text('Settings'));
    await tester.scrollUntilVisible(
      find.text('Trash'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  /// Opens Settings, then Trash, then Books and Entries.
  Future<void> openTrash(WidgetTester tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tap(tester, find.text('Trash'));
    await tap(tester, find.text('Books and Entries'));
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
      expect(find.text('2 items · kept 30 days'), findsOneWidget);

      await tap(tester, find.text('Trash'));
      expect(find.text('2 items'), findsOneWidget);
      expect(
        find.text(
          'Deleted Books and Entries are kept here, then they are gone forever '
          'after this time.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty Trash says so', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.text('Empty · kept 30 days'), findsOneWidget);
      await tap(tester, find.text('Trash'));
      await tap(tester, find.text('Books and Entries'));

      expect(find.text('The Trash is empty'), findsOneWidget);
      await tap(tester, find.byTooltip('More options'));
      final empty = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'Empty Trash'),
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
      expect(find.text('30 days left'), findsOneWidget);
      expect(find.text('20 days left'), findsOneWidget);
      expect(find.textContaining('· My Book'), findsOneWidget);
    });

    testWidgets('counts its last day as one left', (tester) async {
      await store.trashEntries([rain.id]);
      now = now.add(const Duration(days: 29, hours: 23));
      await openTrash(tester);

      expect(find.text('1 day left'), findsOneWidget);
    });
  });

  group('restore', () {
    testWidgets('an Entry from its view, back to its Book', (tester) async {
      await store.trashEntries([rain.id]);
      await openTrash(tester);

      await tap(tester, find.text('Pagi ini hujan.'));
      expect(find.byType(TrashItemScreen), findsOneWidget);
      expect(find.text('In the Trash · 30 days left'), findsOneWidget);
      expect(find.text('Delete forever'), findsOneWidget);

      await tap(tester, find.text('Restore'));

      expect(find.byType(TrashListScreen), findsOneWidget);
      expect(find.text('Entry restored to My Book'), findsOneWidget);
      expect(find.text('The Trash is empty'), findsOneWidget);
      expect(await textsIn(mine), contains('Pagi ini hujan.'));
    });

    testWidgets('a Book from its view, with its Entries', (tester) async {
      await store.trashBook(garden.id);
      await openTrash(tester);

      await tap(tester, find.text('Kebun'));
      expect(find.text('Book in the Trash'), findsOneWidget);
      expect(find.text('1 Entry · 0 photos'), findsOneWidget);
      expect(
        find.text(
          'In the Trash · 30 days left. Restore it to read its Entries.',
        ),
        findsOneWidget,
      );

      await tap(tester, find.text('Restore'));

      expect(find.text('“Kebun” restored'), findsOneWidget);
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
      expect(find.bySemanticsLabel('2 selected'), findsOneWidget);

      await tap(tester, find.byTooltip('Restore'));

      expect(find.text('2 Entries restored to My Book'), findsOneWidget);
      expect(await trashIds(), isEmpty);
    });

    group('Restore to, for an Entry whose Book is in the Trash', () {
      Future<void> restoreStranded(WidgetTester tester) async {
        await store.trashEntries([rain.id]);
        later();
        await store.trashBook(mine.id);
        await openTrash(tester);
        await tap(tester, find.text('Pagi ini hujan.'));
        await tap(tester, find.text('Restore'));
        expect(find.byType(RestoreToScreen), findsOneWidget);
      }

      testWidgets('offers its Book first, then the others', (tester) async {
        await restoreStranded(tester);

        expect(
          find.text('This Entry\'s Book, My Book, is in the Trash too.'),
          findsOneWidget,
        );
        expect(
          find.text('Restore this Book too, with its Entries'),
          findsOneWidget,
        );
        expect(find.text('Other Books'), findsOneWidget);
        final own = tester.getTopLeft(find.text('My Book'));
        final other = tester.getTopLeft(find.text('Kebun'));
        expect(own.dy, lessThan(other.dy));
      });

      testWidgets('to another Book', (tester) async {
        await restoreStranded(tester);

        await tap(tester, find.text('Kebun'));

        expect(find.text('Entry restored to Kebun'), findsOneWidget);
        expect(await textsIn(garden), contains('Pagi ini hujan.'));
        expect(await trashIds(), [mine.id]);
      });

      testWidgets('with its Book', (tester) async {
        await restoreStranded(tester);

        await tap(tester, find.text('My Book'));

        expect(find.text('Entry restored to My Book'), findsOneWidget);
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

      await tap(tester, find.text('Delete forever'));
      expect(find.text('Delete forever?'), findsOneWidget);
      expect(
        find.text(
          'This Entry and its photos will be gone forever. This can\'t be '
          'undone.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Delete'));

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
      await tap(tester, find.text('My Book'));

      await tap(tester, find.text('Delete forever'));
      expect(
        find.text(
          '“My Book” and its 2 Entries will be gone forever. This can\'t be '
          'undone.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Delete'));

      expect(find.text('The Trash is empty'), findsOneWidget);
      expect(await store.watchEntry(rain.id).first, isNull);
    });

    testWidgets('Cancel keeps it', (tester) async {
      await store.trashEntries([rain.id]);
      await openTrash(tester);
      await tap(tester, find.text('Pagi ini hujan.'));

      await tap(tester, find.text('Delete forever'));
      await tap(tester, find.text('Cancel'));

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
      await tap(tester, find.byTooltip('Delete forever'));
      expect(
        find.text('These 2 items will be gone forever. This can\'t be undone.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Delete'));

      expect(find.text('The Trash is empty'), findsOneWidget);
      expect(await store.watchBook(garden.id).first, isNull);
      expect(await store.watchEntry(tomato.id).first, isNull);
      expect(await store.watchEntry(rain.id).first, isNull);
    });

    testWidgets('Empty Trash empties it, after asking', (tester) async {
      await store.trashEntries([rain.id]);
      later();
      await store.trashBook(garden.id);
      await openTrash(tester);

      await tap(tester, find.byTooltip('More options'));
      await tap(tester, find.text('Empty Trash'));
      expect(
        find.text(
          'The 2 items in the Trash will be gone forever. This can\'t be '
          'undone.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Empty'));

      expect(find.text('The Trash is empty'), findsOneWidget);
      expect(await store.watchBook(garden.id).first, isNull);
      expect(await textsIn(mine), hasLength(1));
    });
  });

  group('Keep for', () {
    Future<void> openHub(WidgetTester tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await tap(tester, find.text('Trash'));
    }

    testWidgets('a longer time asks nothing and shows everywhere', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      await openHub(tester);
      expect(find.text('30 days'), findsOneWidget);

      await tap(tester, find.text('Keep for'));
      expect(
        find.text(
          'After that, Books and Entries in the Trash are gone forever.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('90 days'));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('90 days'), findsOneWidget);
      expect(await store.watchTrashDays().first, 90);
      await tap(tester, find.text('Books and Entries'));
      expect(find.text('90 days left'), findsOneWidget);
      await tap(tester, find.byType(BackButton));
      await tap(tester, find.byType(BackButton));
      expect(find.text('1 item · kept 90 days'), findsOneWidget);
    });

    testWidgets('a shorter time asks first when items would go', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      now = now.add(const Duration(days: 10));
      await store.trashBook(garden.id);
      await openHub(tester);

      await tap(tester, find.text('Keep for'));
      await tap(tester, find.text('7 days'));
      expect(find.text('Keep for only 7 days?'), findsOneWidget);
      expect(
        find.text(
          '1 item deleted more than 7 days ago will be gone forever right '
          'away. This can\'t be undone.',
        ),
        findsOneWidget,
      );

      await tap(tester, find.text('Cancel'));
      expect(await store.watchTrashDays().first, 30);
      expect(await trashIds(), hasLength(2));

      await tap(tester, find.text('Keep for'));
      await tap(tester, find.text('7 days'));
      await tap(tester, find.text('Yes, change'));

      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
      expect(await trashIds(), [garden.id]);
      expect(await store.watchEntry(rain.id).first, isNull);
    });

    testWidgets('a shorter time asks nothing when no item would go', (
      tester,
    ) async {
      await store.trashEntries([rain.id]);
      await openHub(tester);

      await tap(tester, find.text('Keep for'));
      await tap(tester, find.text('7 days'));

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
      await tap(tester, find.byTooltip('Delete'));
      expect(
        find.text(
          '“Kebun” and the Entry in it will be kept in the Trash for 7 days, '
          'then be gone forever.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Cancel'));

      await openSettings(tester);
      expect(find.text('Empty · kept 7 days'), findsOneWidget);
      await tap(tester, find.text('Trash'));
      await tap(tester, find.text('Books and Entries'));
      expect(
        find.text(
          'Deleted Books and Entries are kept here for 7 days, then they are '
          'gone forever.',
        ),
        findsOneWidget,
      );
    });
  });
}
