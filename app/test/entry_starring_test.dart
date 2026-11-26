import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_info_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/star_mark.dart';
import 'package:kronoer/src/entries/starred_entries_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/timeline/timeline_screen.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/setting_row.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  late DateTime now;
  late InMemoryStore store;
  late Book mine;
  late Book garden;
  late Map<String, Entry> byText;

  void later() => now = now.add(const Duration(minutes: 1));

  setUp(() async {
    now = DateTime(2026, 11, 22, 9, 30);
    store = InMemoryStore(clock: () => now);
    garden = await store.createBook('Kebun').whenComplete(later);
    mine = await store.createBook('My Book').whenComplete(later);
    byText = {};
    for (final (text, day) in [
      ('Rapat pagi dengan tim.', 10),
      ('Presentasi selesai.', 14),
      ('Pagi ini hujan.', 16),
    ]) {
      byText[text] = await store
          .createEntry(
            bookId: mine.id,
            text: text,
            dateTime: DateTime(2026, 11, day, 9),
          )
          .whenComplete(later);
    }
  });
  tearDown(() => store.dispose());

  String id(String text) => byText[text]!.id;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester, {Locale? locale}) async {
    tester.platformDispatcher.localesTestValue = [locale ?? const Locale('en')];
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

  Future<void> openMine(WidgetTester tester) async {
    await pumpApp(tester);
    await tap(tester, find.text('My Book'));
    expect(find.byType(BookScreen), findsOneWidget);
  }

  Future<void> longPress(WidgetTester tester, String text) async {
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
  }

  Finder card(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(KCard));

  bool starMarked(String text) => find
      .descendant(of: card(text), matching: find.byType(StarMark))
      .evaluate()
      .isNotEmpty;

  Future<List<String>> starredIn(Book book) async => [
    for (final entry in await store.watchStarredEntries(book.id).first)
      entry.text,
  ];

  Future<void> openInfo(WidgetTester tester) async {
    await openMine(tester);
    await tap(tester, find.byTooltip('More options'));
    await tap(tester, find.text('Book info'));
    expect(find.byType(BookInfoScreen), findsOneWidget);
  }

  Future<void> openStarred(WidgetTester tester) async {
    await openInfo(tester);
    await tap(tester, find.text('Starred Entries'));
    expect(find.byType(StarredEntriesScreen), findsOneWidget);
  }

  group('the store', () {
    test('starring is not editing', () async {
      final entry = byText['Pagi ini hujan.']!;
      final activity = (await store.watchBook(mine.id).first)!.lastActivityAt;
      later();

      await store.setEntriesStarred([entry.id], starred: true);

      final starred = (await store.watchEntry(entry.id).first)!;
      expect(starred.starred, isTrue);
      expect(starred.updatedAt, entry.updatedAt);
      expect((await store.watchBook(mine.id).first)!.lastActivityAt, activity);
    });

    test('Starred Entries are one Book\'s, newest first', () async {
      final other = await store.createEntry(
        bookId: garden.id,
        text: 'Tomat.',
        dateTime: DateTime(2026, 11, 20),
      );
      await store.setEntriesStarred([
        id('Rapat pagi dengan tim.'),
        id('Pagi ini hujan.'),
        other.id,
      ], starred: true);

      expect(await starredIn(mine), [
        'Pagi ini hujan.',
        'Rapat pagi dengan tim.',
      ]);
      expect(await starredIn(garden), ['Tomat.']);
    });

    test('the star stays through an edit and a move', () async {
      final entry = byText['Pagi ini hujan.']!;
      await store.setEntriesStarred([entry.id], starred: true);

      await store.updateEntry(entry.copyWith(text: 'Hujan deras.'));
      await store.moveEntries([entry.id], toBookId: garden.id);

      expect(await starredIn(mine), isEmpty);
      expect(await starredIn(garden), ['Hujan deras.']);
    });

    test('starring a missing Entry stars nothing', () async {
      await expectLater(
        store.setEntriesStarred([
          id('Pagi ini hujan.'),
          'missing',
        ], starred: true),
        throwsStateError,
      );
      expect(await starredIn(mine), isEmpty);
    });
  });

  group('selection mode', () {
    testWidgets('Star sits before Copy, Move, and Delete', (tester) async {
      await openMine(tester);
      await longPress(tester, 'Pagi ini hujan.');

      final xs = [
        for (final tooltip in ['Star', 'Copy', 'Move', 'Delete'])
          tester.getCenter(find.byTooltip(tooltip).hitTestable()).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(
        find.descendant(
          of: find.byTooltip('Star'),
          matching: _kIcon(KIcons.star),
        ),
        findsOneWidget,
      );
    });

    testWidgets('stars the selection, ends it, and says nothing', (
      tester,
    ) async {
      await openMine(tester);
      await longPress(tester, 'Pagi ini hujan.');
      await tap(tester, find.text('Rapat pagi dengan tim.'));

      await tap(tester, find.byTooltip('Star'));

      expect(await starredIn(mine), [
        'Pagi ini hujan.',
        'Rapat pagi dengan tim.',
      ]);
      expect(find.byTooltip('Move').hitTestable(), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(starMarked('Pagi ini hujan.'), isTrue);
      expect(starMarked('Rapat pagi dengan tim.'), isTrue);
      expect(starMarked('Presentasi selesai.'), isFalse);
    });

    testWidgets('Unstar only when every selected Entry is starred', (
      tester,
    ) async {
      await store.setEntriesStarred([id('Pagi ini hujan.')], starred: true);
      await openMine(tester);

      await longPress(tester, 'Pagi ini hujan.');
      expect(find.byTooltip('Unstar').hitTestable(), findsOneWidget);

      await tap(tester, find.text('Presentasi selesai.'));
      expect(find.byTooltip('Star').hitTestable(), findsOneWidget);
      await tap(tester, find.text('Presentasi selesai.'));

      await tap(tester, find.byTooltip('Unstar'));
      expect(await starredIn(mine), isEmpty);
      expect(starMarked('Pagi ini hujan.'), isFalse);
    });
  });

  group('read view menu', () {
    testWidgets('Star comes first and stars the Entry', (tester) async {
      await openMine(tester);
      await tap(tester, find.text('Pagi ini hujan.'));
      expect(find.byType(EntryReadScreen), findsOneWidget);

      await tap(tester, _kIcon(KIcons.moreVertical));
      final items = [
        for (final item in [
          'Star',
          'Copy text',
          'Move to another Book',
          'Delete Entry',
        ])
          tester.getTopLeft(find.text(item)).dy,
      ];
      expect(items, orderedEquals([...items]..sort()));

      await tap(tester, find.text('Star'));
      expect(await starredIn(mine), ['Pagi ini hujan.']);
      // Still reading it.
      expect(find.byType(EntryReadScreen), findsOneWidget);

      await tap(tester, _kIcon(KIcons.moreVertical));
      expect(find.text('Star'), findsNothing);
      await tap(tester, find.text('Unstar'));
      expect(await starredIn(mine), isEmpty);
    });

    testWidgets('the editor menu has no star', (tester) async {
      await openMine(tester);
      await tap(tester, find.text('Pagi ini hujan.'));
      await tap(tester, find.byTooltip('Edit Entry'));

      await tap(tester, _kIcon(KIcons.moreVertical));

      expect(find.text('Star'), findsNothing);
      expect(find.text('Delete Entry'), findsOneWidget);
    });
  });

  group('cards', () {
    testWidgets('a star in a Book card sits just before the time', (
      tester,
    ) async {
      await store.setEntriesStarred([id('Pagi ini hujan.')], starred: true);
      await openMine(tester);

      final star = find.descendant(
        of: card('Pagi ini hujan.'),
        matching: find.byType(StarMark),
      );
      final time = find.descendant(
        of: card('Pagi ini hujan.'),
        matching: find.text('09:00'),
      );
      expect(tester.getSize(star), const Size(12, 12));
      expect(tester.getTopRight(star).dx, lessThan(tester.getTopLeft(time).dx));
      final icon = tester.widget<KIcon>(
        find.descendant(of: star, matching: find.byType(KIcon)),
      );
      expect(icon.filled, isTrue);
      expect(find.bySemanticsLabel(RegExp('Starred')), findsOneWidget);
    });

    testWidgets('the Timeline shows the star too', (tester) async {
      await store.setEntriesStarred([id('Pagi ini hujan.')], starred: true);
      await pumpApp(tester);
      await tap(tester, find.text('Timeline'));
      expect(find.byType(TimelineScreen), findsOneWidget);

      expect(find.byType(StarMark), findsOneWidget);
    });
  });

  group('Book info', () {
    testWidgets('Starred Entries shows how many, none when none', (
      tester,
    ) async {
      await openInfo(tester);

      final row = find.widgetWithText(SettingRow, 'Starred Entries');
      expect(tester.widget<SettingRow>(row).trailing, isNull);

      await store.setEntriesStarred([
        id('Pagi ini hujan.'),
        id('Presentasi selesai.'),
      ], starred: true);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.text('2')),
        findsOneWidget,
      );
    });
  });

  group('Starred Entries page', () {
    testWidgets('lists the starred Entries newest first, and opens one', (
      tester,
    ) async {
      await store.setEntriesStarred([
        id('Rapat pagi dengan tim.'),
        id('Pagi ini hujan.'),
      ], starred: true);
      await openStarred(tester);

      expect(find.widgetWithText(AppBar, 'Starred Entries'), findsOneWidget);
      expect(find.text('Presentasi selesai.'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Pagi ini hujan.')).dy,
        lessThan(tester.getTopLeft(find.text('Rapat pagi dengan tim.')).dy),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('More options'), findsNothing);

      await tap(tester, find.text('Pagi ini hujan.'));
      expect(find.byType(EntryReadScreen), findsOneWidget);

      await tap(tester, find.byTooltip('Back'));
      expect(find.byType(StarredEntriesScreen), findsOneWidget);
    });

    testWidgets('empty, it says so under a star', (tester) async {
      await openStarred(tester);

      expect(find.text('No starred Entries yet'), findsOneWidget);
      expect(_kIcon(KIcons.star), findsOneWidget);
    });

    testWidgets('unstarring says so, and Undo stars them again', (
      tester,
    ) async {
      await store.setEntriesStarred([
        id('Rapat pagi dengan tim.'),
        id('Pagi ini hujan.'),
      ], starred: true);
      await openStarred(tester);

      await longPress(tester, 'Pagi ini hujan.');
      await tap(tester, find.text('Rapat pagi dengan tim.'));
      expect(find.byTooltip('Unstar').hitTestable(), findsOneWidget);
      await tap(tester, find.byTooltip('Unstar'));

      expect(find.text('2 stars removed'), findsOneWidget);
      expect(find.text('Pagi ini hujan.'), findsNothing);
      expect(find.text('No starred Entries yet'), findsOneWidget);

      await tap(tester, find.text('Undo'));
      expect(await starredIn(mine), [
        'Pagi ini hujan.',
        'Rapat pagi dengan tim.',
      ]);
      expect(find.text('Pagi ini hujan.'), findsOneWidget);
    });

    testWidgets('an Entry unstarred in the read view leaves the page', (
      tester,
    ) async {
      await store.setEntriesStarred([id('Pagi ini hujan.')], starred: true);
      await openStarred(tester);
      await tap(tester, find.text('Pagi ini hujan.'));

      await tap(tester, _kIcon(KIcons.moreVertical));
      await tap(tester, find.text('Unstar'));
      await tap(tester, find.byTooltip('Back'));

      expect(find.text('No starred Entries yet'), findsOneWidget);
    });

    testWidgets('in Indonesian', (tester) async {
      await store.setEntriesStarred([id('Pagi ini hujan.')], starred: true);
      await pumpApp(tester, locale: const Locale('id'));
      await tap(tester, find.text('My Book'));
      await tap(tester, find.byTooltip('Opsi lainnya'));
      await tap(tester, find.text('Info Book'));
      await tap(tester, find.text('Entry berbintang'));

      await longPress(tester, 'Pagi ini hujan.');
      await tap(tester, find.byTooltip('Hapus bintang'));

      expect(find.text('Bintang Entry dihapus'), findsOneWidget);
      expect(find.text('Belum ada Entry berbintang'), findsOneWidget);
    });
  });
}
