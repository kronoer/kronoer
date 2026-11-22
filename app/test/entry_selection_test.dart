import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_moving.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/timeline/day_line.dart';
import 'package:kronoer/src/timeline/timeline_screen.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/selection.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  late DateTime now;
  late InMemoryStore store;
  late Book mine;
  late Book work;
  late Book garden;

  void later() => now = now.add(const Duration(minutes: 1));

  setUp(() async {
    now = DateTime(2026, 11, 22, 9, 30);
    store = InMemoryStore(clock: () => now);
    work = await store.createBook('Catatan Kerja').whenComplete(later);
    garden = await store.createBook('Kebun').whenComplete(later);
    mine = await store.createBook('Buku Saya').whenComplete(later);
    for (final (text, day) in [
      ('Rapat pagi dengan tim.', 28),
      ('Presentasi selesai.', 30),
      ('Pagi ini hujan.', 16),
    ]) {
      await store
          .createEntry(
            bookId: mine.id,
            text: text,
            dateTime: DateTime(2026, day == 16 ? 11 : 10, day, 9),
          )
          .whenComplete(later);
    }
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

  Future<void> openMine(WidgetTester tester) async {
    await pumpApp(tester);
    await tap(tester, find.text('Buku Saya'));
    expect(find.byType(BookScreen), findsOneWidget);
  }

  Future<void> longPress(WidgetTester tester, String text) async {
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
  }

  Finder card(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(KCard));

  /// Whether the Entry's card shows the check. Out of selection mode it has
  /// no badge at all.
  bool badged(WidgetTester tester, String text) => tester
      .widgetList<SelectionBadge>(
        find.descendant(
          // The Stack that lays the badge over the card.
          of: find.ancestor(of: card(text), matching: find.byType(Stack)).first,
          matching: find.byType(SelectionBadge),
        ),
      )
      .any((badge) => badge.selected);

  bool selecting(WidgetTester tester) =>
      find.byTooltip('Pindahkan').hitTestable().evaluate().isNotEmpty;

  Future<List<Entry>> entriesOf(Book book) => store.watchEntries(book.id).first;

  Future<List<String>> textsIn(Book book) async => [
    for (final entry in await entriesOf(book)) entry.text,
  ];

  group('selection mode', () {
    testWidgets('a long press selects the Entry and changes the top bar', (
      tester,
    ) async {
      await openMine(tester);

      await longPress(tester, 'Presentasi selesai.');

      expect(selecting(tester), isTrue);
      expect(find.byTooltip('Hapus').hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel('1 dipilih'), findsOneWidget);
      expect(badged(tester, 'Presentasi selesai.'), isTrue);
      expect(badged(tester, 'Pagi ini hujan.'), isFalse);
      final context = tester.element(find.byType(BookScreen));
      final theme = Theme.of(context);
      expect(
        tester.widget<KCard>(card('Presentasi selesai.')).color,
        selectedTint(theme),
      );
      // The FAB, the Book's name, and its menu are gone.
      expect(find.byTooltip('Tulis Entry').hitTestable(), findsNothing);
      expect(find.text('Buku Saya').hitTestable(), findsNothing);
      expect(find.byTooltip('Opsi lainnya').hitTestable(), findsNothing);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, selectionBarColor(theme));
    });

    testWidgets('the badge lies over the card without moving its contents', (
      tester,
    ) async {
      await openMine(tester);
      final before = tester.getTopLeft(find.text('Presentasi selesai.'));

      await longPress(tester, 'Presentasi selesai.');

      expect(tester.getTopLeft(find.text('Presentasi selesai.')), before);
      final badge = find.byWidgetPredicate(
        (w) => w is SelectionBadge && w.selected,
      );
      final corner = tester.getTopLeft(card('Presentasi selesai.'));
      expect(tester.getTopLeft(badge), corner - const Offset(6, 6));
    });

    testWidgets('a tap selects and deselects instead of opening', (
      tester,
    ) async {
      await openMine(tester);
      await longPress(tester, 'Presentasi selesai.');

      await tap(tester, find.text('Pagi ini hujan.'));
      expect(find.byType(EntryReadScreen), findsNothing);
      expect(badged(tester, 'Pagi ini hujan.'), isTrue);
      expect(find.bySemanticsLabel('2 dipilih'), findsOneWidget);

      await tap(tester, find.text('Pagi ini hujan.'));
      expect(badged(tester, 'Pagi ini hujan.'), isFalse);
      expect(selecting(tester), isTrue);

      // Deselecting the last Entry ends selection mode.
      await tap(tester, find.text('Presentasi selesai.'));
      expect(selecting(tester), isFalse);
      expect(find.byTooltip('Tulis Entry').hitTestable(), findsOneWidget);
      expect(find.byType(SelectionBadge), findsNothing);

      // Out of it, a tap opens the Entry again.
      await tap(tester, find.text('Pagi ini hujan.'));
      expect(find.byType(EntryReadScreen), findsOneWidget);
    });

    testWidgets('the top bar back ends it and stays in the Book', (
      tester,
    ) async {
      await openMine(tester);
      await longPress(tester, 'Presentasi selesai.');

      await tap(tester, find.byType(BackButton).hitTestable());

      expect(find.byType(BookScreen), findsOneWidget);
      expect(selecting(tester), isFalse);
      expect(find.text('Buku Saya').hitTestable(), findsOneWidget);

      // A long press starts afresh, with only that Entry.
      await longPress(tester, 'Pagi ini hujan.');
      expect(find.bySemanticsLabel('1 dipilih'), findsOneWidget);
    });

    testWidgets('the system back ends it, and then leaves the Book', (
      tester,
    ) async {
      await openMine(tester);
      await longPress(tester, 'Presentasi selesai.');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookScreen), findsOneWidget);
      expect(selecting(tester), isFalse);
      expect(badged(tester, 'Presentasi selesai.'), isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookScreen), findsNothing);
    });

    testWidgets('only a Book has it: the Timeline opens on a long press', (
      tester,
    ) async {
      await pumpApp(tester);
      await tap(tester, find.text('Linimasa'));
      expect(find.byType(TimelineScreen), findsOneWidget);

      await longPress(tester, 'Pagi ini hujan.');

      expect(find.byType(SelectionBadge), findsNothing);
      expect(find.byTooltip('Pindahkan'), findsNothing);
    });
  });

  group('move', () {
    Future<void> selectTwo(WidgetTester tester) async {
      await openMine(tester);
      await longPress(tester, 'Presentasi selesai.');
      await tap(tester, find.text('Rapat pagi dengan tim.'));
    }

    testWidgets('Pindahkan ke lists the Books, this one disabled', (
      tester,
    ) async {
      await selectTwo(tester);

      await tap(tester, find.byTooltip('Pindahkan'));

      expect(find.byType(MoveTargetScreen), findsOneWidget);
      expect(find.text('Pindahkan ke'), findsOneWidget);
      // In Book list order: the latest activity first.
      final names = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data,
      ];
      expect(names, ['Buku Saya', 'Kebun', 'Catatan Kerja']);
      final here = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Buku Saya').last,
          matching: find.byType(ListTile),
        ),
      );
      expect(here.enabled, isFalse);
      expect(find.text('Book ini'), findsOneWidget);

      // Tapping this Book does nothing.
      await tap(tester, find.text('Book ini'));
      expect(find.byType(MoveTargetScreen), findsOneWidget);
    });

    testWidgets('a tap moves at once, with Urungkan', (tester) async {
      final before = {for (final e in await entriesOf(mine)) e.id: e};
      await selectTwo(tester);
      await tap(tester, find.byTooltip('Pindahkan'));

      await tap(tester, find.text('Catatan Kerja'));

      // Back in the Book, out of selection mode, without the two.
      expect(find.byType(MoveTargetScreen), findsNothing);
      expect(find.byType(BookScreen), findsOneWidget);
      expect(selecting(tester), isFalse);
      expect(find.text('Presentasi selesai.'), findsNothing);
      expect(find.text('Rapat pagi dengan tim.'), findsNothing);
      expect(find.text('Pagi ini hujan.'), findsOneWidget);
      expect(find.text('2 Entry dipindahkan ke Catatan Kerja'), findsOneWidget);
      expect(await textsIn(mine), ['Pagi ini hujan.']);
      expect(
        await textsIn(work),
        unorderedEquals(['Presentasi selesai.', 'Rapat pagi dengan tim.']),
      );
      // Moving is not editing: the times stay.
      for (final moved in await entriesOf(work)) {
        final was = before[moved.id]!;
        expect(moved.createdAt, was.createdAt);
        expect(moved.updatedAt, was.updatedAt);
        expect(moved.dateTime, was.dateTime);
      }

      await tap(tester, find.text('Urungkan'));

      expect(await textsIn(work), isEmpty);
      expect(find.text('Presentasi selesai.'), findsOneWidget);
      expect(find.text('Rapat pagi dengan tim.'), findsOneWidget);
    });

    testWidgets('back on Pindahkan ke moves nothing and keeps the selection', (
      tester,
    ) async {
      await selectTwo(tester);
      await tap(tester, find.byTooltip('Pindahkan'));

      await tap(tester, find.byType(BackButton));

      expect(find.byType(MoveTargetScreen), findsNothing);
      expect(await textsIn(mine), hasLength(3));
      expect(find.bySemanticsLabel('2 dipilih'), findsOneWidget);
    });
  });

  group('delete', () {
    testWidgets('several Entries, after asking, with no undo', (tester) async {
      await openMine(tester);
      await longPress(tester, 'Presentasi selesai.');
      await tap(tester, find.text('Rapat pagi dengan tim.'));

      await tap(tester, find.byTooltip('Hapus'));

      expect(find.text('Hapus 2 Entry?'), findsOneWidget);
      expect(
        find.text(
          '2 Entry ini dan fotonya akan hilang selamanya. '
          'Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );

      await tap(tester, find.text('Ya, hapus'));

      expect(await textsIn(mine), ['Pagi ini hujan.']);
      expect(find.text('Presentasi selesai.'), findsNothing);
      expect(selecting(tester), isFalse);
      expect(find.text('Urungkan'), findsNothing);
    });

    testWidgets('Batal deletes nothing and keeps the selection', (
      tester,
    ) async {
      await openMine(tester);
      await longPress(tester, 'Presentasi selesai.');
      await tap(tester, find.byTooltip('Hapus'));

      // One Entry is asked about too.
      expect(find.text('Hapus Entry?'), findsOneWidget);
      await tap(tester, find.text('Batal'));

      expect(await textsIn(mine), hasLength(3));
      expect(find.bySemanticsLabel('1 dipilih'), findsOneWidget);
    });
  });

  group('read view menu', () {
    Future<void> moveFromMenu(WidgetTester tester) async {
      await tap(tester, _kIcon(KIcons.moreVertical));
      await tap(tester, find.text('Pindahkan ke Book lain'));
      await tap(tester, find.text('Kebun'));
    }

    testWidgets('Pindahkan ke Book lain sits above Hapus Entry', (
      tester,
    ) async {
      await openMine(tester);
      await tap(tester, find.text('Pagi ini hujan.'));

      await tap(tester, _kIcon(KIcons.moreVertical));

      final move = tester.getTopLeft(find.text('Pindahkan ke Book lain'));
      final delete = tester.getTopLeft(find.text('Hapus Entry'));
      expect(move.dy, lessThan(delete.dy));
    });

    testWidgets('moving closes the read view back to the Book', (tester) async {
      await openMine(tester);
      await tap(tester, find.text('Pagi ini hujan.'));

      await moveFromMenu(tester);

      expect(find.byType(EntryReadScreen), findsNothing);
      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.text('Pagi ini hujan.'), findsNothing);
      expect(find.text('Entry dipindahkan ke Kebun'), findsOneWidget);
      expect(await textsIn(garden), ['Pagi ini hujan.']);

      await tap(tester, find.text('Urungkan'));
      expect(await textsIn(garden), isEmpty);
      expect(find.text('Pagi ini hujan.'), findsOneWidget);
    });

    testWidgets('from the Timeline, the Entry stays with its new Book', (
      tester,
    ) async {
      await pumpApp(tester);
      await tap(tester, find.text('Linimasa'));
      await tap(tester, find.text('Pagi ini hujan.'));

      await moveFromMenu(tester);

      expect(find.byType(EntryReadScreen), findsNothing);
      expect(find.byType(TimelineScreen), findsOneWidget);
      final moved = find.ancestor(
        of: find.text('Pagi ini hujan.'),
        matching: find.byType(EntryLine),
      );
      expect(
        find.descendant(of: moved, matching: find.text('Kebun')),
        findsOneWidget,
      );
    });

    testWidgets('the editor menu has no move', (tester) async {
      await openMine(tester);
      await tap(tester, find.text('Pagi ini hujan.'));
      await tap(tester, find.byTooltip('Ubah Entry'));
      expect(find.byType(EntryEditorScreen), findsOneWidget);

      await tap(tester, _kIcon(KIcons.moreVertical).last);

      expect(find.text('Hapus Entry'), findsOneWidget);
      expect(find.text('Pindahkan ke Book lain'), findsNothing);
    });
  });
}
