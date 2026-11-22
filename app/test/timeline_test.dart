import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/timeline/date_strip.dart';
import 'package:kronoer/src/timeline/day_line.dart';
import 'package:kronoer/src/timeline/timeline_rows.dart';
import 'package:kronoer/src/timeline/timeline_screen.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/scrollbar.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

// A Thursday.
final _now = DateTime(2026, 11, 19, 14, 32);

Entry _entry(String id, DateTime dateTime) => Entry(
  id: id,
  bookId: 'b',
  text: id,
  dateTime: dateTime,
  createdAt: dateTime,
  updatedAt: dateTime,
);

/// Each row as text, to compare whole lists.
List<String> _describe(TimelineRows rows) => [
  for (final row in rows.rows)
    switch (row) {
      DayHeadingRow(:final day, :final empty) =>
        '${empty ? 'empty' : 'day'} ${day.month}-${day.day}',
      EntryLineRow(:final entry, :final first, :final last) =>
        '  ${entry.id}${first ? ' first' : ''}${last ? ' last' : ''}',
      EmptyRangeRow(:final from, :final to) =>
        'range ${from.month}-${from.day}..${to.month}-${to.day}',
      NoEntryRow() => '  no Entry',
    },
];

void main() {
  group('timelineRows', () {
    final entries = [
      _entry('a', DateTime(2026, 11, 19, 9)),
      _entry('b', DateTime(2026, 11, 19, 7)),
      _entry('c', DateTime(2026, 11, 16, 12)),
      _entry('d', DateTime(2026, 11, 5, 8)),
    ];

    test('every day, newest first, with runs of 7 empty days as one row', () {
      final rows = timelineRows(
        entries,
        today: _now,
        order: EntryOrder.newestFirst,
      );

      expect(_describe(rows), [
        'day 11-19',
        '  a first',
        '  b last',
        'empty 11-18',
        'empty 11-17',
        'day 11-16',
        '  c first last',
        'range 11-6..11-15',
        'day 11-5',
        '  d first last',
        'empty 11-4',
        'empty 11-3',
        'empty 11-2',
        'empty 11-1',
      ]);
      expect(rows.oldest, DateTime(2026, 11));
      expect(rows.newest, DateTime(2026, 11, 19));
      // A day in the run is on the run's row; days outside are on none.
      expect(rows.rowOf(DateTime(2026, 11, 10)), 7);
      expect(rows.rowOf(DateTime(2026, 11, 16)), 5);
      expect(rows.rowOf(DateTime(2026, 11, 20)), isNull);
      expect(rows.rowOf(DateTime(2026, 10, 31)), isNull);
    });

    test('six empty days are six rows', () {
      final rows = timelineRows(
        [
          _entry('a', DateTime(2026, 11, 19, 9)),
          _entry('b', DateTime(2026, 11, 12, 9)),
        ],
        today: _now,
        order: EntryOrder.newestFirst,
      );
      expect(_describe(rows).where((row) => row.startsWith('empty')).take(6), [
        for (var day = 18; day >= 13; day--) 'empty 11-$day',
      ]);
      expect(_describe(rows).where((row) => row.startsWith('range')), [
        'range 11-1..11-11',
      ]);
    });

    test('oldest first turns the days around, today last', () {
      final rows = timelineRows(
        entries.reversed.toList(),
        today: _now,
        order: EntryOrder.oldestFirst,
      );

      expect(_describe(rows), [
        'empty 11-1',
        'empty 11-2',
        'empty 11-3',
        'empty 11-4',
        'day 11-5',
        '  d first last',
        'range 11-6..11-15',
        'day 11-16',
        '  c first last',
        'empty 11-17',
        'empty 11-18',
        'day 11-19',
        '  b first',
        '  a last',
      ]);
      // The strip shows a run's first day in the list's order.
      expect((rows.rows[6] as EmptyRangeRow).day, DateTime(2026, 11, 6));
    });

    test('today is never part of a run', () {
      final rows = timelineRows(
        [_entry('a', DateTime(2026, 11, 2, 9))],
        today: _now,
        order: EntryOrder.newestFirst,
      );
      expect(_describe(rows), [
        'empty 11-19',
        'range 11-3..11-18',
        'day 11-2',
        '  a first last',
        'empty 11-1',
      ]);
    });

    test('with no Entry, today says so, then this month down to the 1st', () {
      final rows = timelineRows(
        const [],
        today: _now,
        order: EntryOrder.newestFirst,
      );
      expect(_describe(rows), ['day 11-19', '  no Entry', 'range 11-1..11-18']);
    });

    test('it reaches back to an older day given, and to a later Entry', () {
      final rows = timelineRows(
        [_entry('a', DateTime(2026, 11, 21, 9))],
        today: _now,
        order: EntryOrder.newestFirst,
        oldest: DateTime(2026, 10, 30),
      );
      expect(rows.newest, DateTime(2026, 11, 21));
      expect(rows.oldest, DateTime(2026, 10, 30));
      expect(_describe(rows).take(4), [
        'day 11-21',
        '  a first last',
        'empty 11-20',
        'empty 11-19',
      ]);
    });
  });

  group('Linimasa', () {
    late InMemoryStore store;
    late Book kebun;
    late Book jalan;

    setUp(() async {
      store = InMemoryStore(clock: () => _now);
      kebun = await store.createBook('Kebun');
      jalan = await store.createBook('Jalan-jalan');
    });
    tearDown(() => store.dispose());

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Finder tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

    Future<void> openTimeline(WidgetTester tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('id')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      // Tall enough for a few days.
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryStoreProvider.overrideWithValue(store),
            clockProvider.overrideWithValue(() => _now),
            hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
          ],
          child: const KronoerApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, tab('Linimasa'));
      expect(find.byType(TimelineScreen), findsOneWidget);
    }

    Future<void> write(
      Book book,
      String text,
      DateTime dateTime, {
      List<String> imageIds = const [],
    }) => store.createEntry(
      bookId: book.id,
      text: text,
      dateTime: dateTime,
      imageIds: imageIds,
    );

    Finder list() => find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;

    Finder inStrip(String text) =>
        find.descendant(of: find.byType(DateStrip), matching: find.text(text));

    /// The crumbs, in order.
    List<String> crumbs(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(DateStrip),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.style?.fontSize == 15,
          ),
        ),
      ))
        if (tester.getTopLeft(find.byWidget(text)).dy <
            tester.getTopLeft(find.byType(DateStrip)).dy + 40)
          text.data!,
    ];

    /// The strip item with [label] for screen readers.
    SemanticsNode item(WidgetTester tester, String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    testWidgets('each Entry hangs on its day: time, Book, then text', (
      tester,
    ) async {
      await write(kebun, 'Tomat berbuah.', DateTime(2026, 11, 19, 8, 15));
      await write(jalan, 'Naik kereta.', DateTime(2026, 11, 19, 7, 5));
      await write(
        kebun,
        'Panen.\n\nDua.\n\nTiga.\n\nEmpat.',
        DateTime(2026, 11, 17, 10),
      );
      await openTimeline(tester);

      expect(find.text('Hari ini'), findsOneWidget);
      expect(find.text('Kamis, 19 November'), findsOneWidget);
      // No Entry yesterday: one faded line.
      expect(find.text('Kemarin  Rabu, 18 November'), findsOneWidget);
      expect(find.text('Selasa'), findsOneWidget);
      expect(find.text('17 November'), findsOneWidget);

      final line = find.ancestor(
        of: find.text('Tomat berbuah.'),
        matching: find.byType(EntryLine),
      );
      for (final text in ['08.15', 'Kebun']) {
        expect(
          find.descendant(of: line, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Naik kereta.'),
            matching: find.byType(EntryLine),
          ),
          matching: find.text('Jalan-jalan'),
        ),
        findsOneWidget,
      );
      // Newest first within the day too.
      expect(
        tester.getTopLeft(find.text('Tomat berbuah.')).dy,
        lessThan(tester.getTopLeft(find.text('Naik kereta.')).dy),
      );
      // At most three lines of text.
      final preview = tester.widget<Text>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Kebun').last,
            matching: find.byType(EntryLine),
          ),
          matching: find.byWidgetPredicate((w) => w is Text && w.maxLines == 3),
        ),
      );
      expect(preview.maxLines, 3);
      // Not the Book screen's cards, month separators, or scrollbar.
      expect(find.byType(KCard), findsNothing);
      expect(find.byType(LabeledScrollbar), findsNothing);
      expect(find.text('November 2026'), findsNothing);
    });

    testWidgets('Images are 72 px, 96 px with no text, three at most', (
      tester,
    ) async {
      await write(
        kebun,
        'Kebun pagi.',
        DateTime(2026, 11, 19, 9),
        imageIds: ['a', 'b', 'c', 'd', 'e'],
      );
      await write(kebun, '', DateTime(2026, 11, 19, 8), imageIds: ['f']);
      await openTimeline(tester);

      final images = tester.widgetList<EntryImage>(find.byType(EntryImage));
      expect([for (final image in images) image.imageId], ['a', 'b', 'c', 'f']);
      expect(tester.getSize(find.byType(EntryImage).first), const Size(72, 72));
      expect(tester.getSize(find.byType(EntryImage).last), const Size(96, 96));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('opens on today at the day level, dots on days with Entries', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await write(kebun, 'Tomat berbuah.', DateTime(2026, 11, 19, 8));
      await write(kebun, 'Panen.', DateTime(2026, 11, 17, 8));
      await openTimeline(tester);

      expect(crumbs(tester), ['Semua tahun', '2026', 'November']);
      expect(
        item(tester, 'Kamis, 19 November 2026'),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        item(tester, 'Selasa, 17 November 2026'),
        isSemantics(isSelected: false),
      );
      expect(
        find.bySemanticsLabel('Rabu, 18 November 2026, tidak ada Entry'),
        findsOneWidget,
      );
      // Up to today, today on the right.
      expect(inStrip('20'), findsNothing);
      expect(
        tester.getTopLeft(inStrip('19')).dx,
        greaterThan(tester.getTopLeft(inStrip('18')).dx),
      );
      semantics.dispose();
    });

    testWidgets('a day in the strip moves the list to it', (tester) async {
      for (var day = 1; day <= 28; day++) {
        await write(kebun, 'Hari $day.', DateTime(2026, 10, day, 8));
      }
      await write(kebun, 'Tomat berbuah.', DateTime(2026, 11, 19, 8));
      await openTimeline(tester);

      // Up to the months, then October's days.
      await tapAndSettle(tester, inStrip('2026'));
      expect(crumbs(tester), ['Semua tahun', '2026']);
      expect(inStrip('Nov'), findsOneWidget);
      expect(inStrip('Okt'), findsOneWidget);
      expect(inStrip('Sep'), findsNothing);
      await tapAndSettle(tester, inStrip('Okt'));
      expect(crumbs(tester), ['Semua tahun', '2026', 'Oktober']);
      // October's last days have no Entry: the list is at their run.
      expect(find.text('29 Okt – 18 Nov').hitTestable(), findsOneWidget);

      await tapAndSettle(tester, inStrip('25'));
      final listTop = tester.getTopLeft(list()).dy;
      expect(
        tester
            .getTopLeft(
              find.ancestor(
                of: find.text('25 Oktober'),
                matching: find.byType(DayHeading),
              ),
            )
            .dy,
        closeTo(listTop, 1),
      );
      expect(find.text('Hari 25.').hitTestable(), findsOneWidget);
    });

    testWidgets('scrolling the list moves the strip and the crumbs', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      for (var day = 1; day <= 28; day++) {
        await write(kebun, 'Hari $day.', DateTime(2026, 10, day, 8));
      }
      await write(kebun, 'Tomat berbuah.', DateTime(2026, 11, 19, 8));
      await openTimeline(tester);

      await tester.drag(list(), const Offset(0, -1500));
      await tester.pumpAndSettle();

      expect(crumbs(tester), ['Semua tahun', '2026', 'Oktober']);
      final selected = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(DateStrip),
              matching: find.byType(Semantics),
            ),
          )
          .where((s) => s.properties.selected ?? false)
          .map((s) => s.properties.label)
          .toList();
      expect(selected, hasLength(1));
      expect(selected.single, contains('Oktober 2026'));

      // Tapping the open tab goes back to today, at the day level.
      await tapAndSettle(tester, inStrip('Semua tahun'));
      expect(crumbs(tester), ['Semua tahun']);
      await tapAndSettle(tester, tab('Linimasa'));
      expect(crumbs(tester), ['Semua tahun', '2026', 'November']);
      expect(tester.state<ScrollableState>(list()).position.pixels, 0);
      expect(
        item(tester, 'Kamis, 19 November 2026'),
        isSemantics(isSelected: true),
      );
      semantics.dispose();
    });

    testWidgets(
      'the years run from the oldest Entry; a year opens its months',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await write(kebun, 'Dulu.', DateTime(2024, 10, 4, 8));
        await write(kebun, 'Tomat berbuah.', DateTime(2026, 11, 19, 8));
        await openTimeline(tester);

        await tapAndSettle(tester, inStrip('Semua tahun'));
        for (final year in ['2026', '2024']) {
          expect(find.bySemanticsLabel(year), findsOneWidget);
        }
        expect(find.bySemanticsLabel('2025, tidak ada Entry'), findsOneWidget);
        expect(inStrip('2023'), findsNothing);

        await tapAndSettle(tester, inStrip('2024'));
        expect(crumbs(tester), ['Semua tahun', '2024']);
        // From the oldest Entry's month.
        expect(inStrip('Okt'), findsOneWidget);
        expect(inStrip('Sep'), findsNothing);
        expect(find.bySemanticsLabel('Oktober 2024'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Desember 2024, tidak ada Entry'),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );

    testWidgets('a Book kept out of the Timeline counts for nothing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await write(kebun, 'Tomat berbuah.', DateTime(2026, 11, 19, 8));
      await write(jalan, 'Naik kereta.', DateTime(2026, 11, 15, 8));
      await write(jalan, 'Dulu sekali.', DateTime(2024, 1, 1, 8));
      await store.setBookInTimeline(jalan.id, inTimeline: false);
      await openTimeline(tester);

      expect(find.text('Naik kereta.'), findsNothing);
      expect(
        find.bySemanticsLabel('Minggu, 15 November 2026, tidak ada Entry'),
        findsOneWidget,
      );
      await tapAndSettle(tester, inStrip('Semua tahun'));
      expect(inStrip('2024'), findsNothing);
      semantics.dispose();
    });

    testWidgets('with no Entry: today says so, then this month', (
      tester,
    ) async {
      await openTimeline(tester);

      expect(find.text('Hari ini'), findsOneWidget);
      expect(find.text('Belum ada Entry'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Hari ini')).dy,
        lessThan(tester.getTopLeft(find.text('Belum ada Entry')).dy),
      );
      expect(find.byType(TextButton), findsNothing);
      expect(find.text('1 Nov – 18 Nov'), findsOneWidget);
      expect(crumbs(tester), ['Semua tahun', '2026', 'November']);
      // The crumbs start on the left.
      expect(tester.getTopLeft(inStrip('Semua tahun')).dx, closeTo(20, 1));
      expect(inStrip('19'), findsOneWidget);
      expect(
        tester.getTopLeft(inStrip('19')).dx,
        greaterThan(tester.getTopLeft(inStrip('18')).dx),
      );
    });

    testWidgets('oldest first turns only the list around', (tester) async {
      await write(kebun, 'Tomat berbuah.', DateTime(2026, 11, 19, 8));
      await write(kebun, 'Panen.', DateTime(2026, 11, 2, 8));
      await openTimeline(tester);

      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      await tapAndSettle(tester, find.text('Urutkan'));
      await tapAndSettle(tester, find.text('Terlama dulu'));

      expect(
        tester.getTopLeft(find.text('Panen.')).dy,
        lessThan(tester.getTopLeft(find.text('Tomat berbuah.')).dy),
      );
      // The strip still has the newest on the right; it shows the top day.
      expect(
        tester.getTopLeft(inStrip('2')).dx,
        lessThan(tester.getTopLeft(inStrip('3')).dx),
      );
    });
  });
}
