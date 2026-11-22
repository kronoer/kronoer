import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/selection.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  late DateTime now;
  late InMemoryStore store;

  setUp(() {
    now = DateTime(2026, 11, 22, 9, 30);
    store = InMemoryStore(clock: () => now);
  });
  tearDown(() => store.dispose());

  void later() => now = now.add(const Duration(minutes: 1));

  /// Creates Books named [names], the last one with the latest activity, so
  /// the list shows them in reverse.
  Future<List<Book>> createBooks(List<String> names) async => [
    for (final name in names) await store.createBook(name).whenComplete(later),
  ];

  Future<void> pumpBookList(WidgetTester tester) async {
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

  Finder row(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(BookRow));

  Future<void> longPress(WidgetTester tester, String name) async {
    await tester.longPress(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  List<String> names(WidgetTester tester) => [
    for (final row in tester.widgetList<BookRow>(find.byType(BookRow)))
      row.summary.book.name,
  ];

  /// Whether the Book's row shows the check. Out of selection mode it has no
  /// badge at all.
  bool badged(WidgetTester tester, String name) => tester
      .widgetList<SelectionBadge>(
        find.descendant(of: row(name), matching: find.byType(SelectionBadge)),
      )
      .any((badge) => badge.selected);

  bool pinIcon(WidgetTester tester, String name) => tester
      .widgetList<KIcon>(
        find.descendant(of: row(name), matching: find.byType(KIcon)),
      )
      .any((icon) => icon.icon == KIcons.pin);

  bool selecting(WidgetTester tester) =>
      find.byTooltip('Hapus').hitTestable().evaluate().isNotEmpty;

  group('selection mode', () {
    testWidgets('a long press selects the Book and changes the top bar', (
      tester,
    ) async {
      final books = await createBooks(['Kebun', 'Kerja']);
      await store.createEntry(bookId: books.first.id, text: 'Cabai berbunga.');
      await pumpBookList(tester);
      expect(find.text('Cari di semua Book'), findsOneWidget);

      await longPress(tester, 'Kebun');

      expect(selecting(tester), isTrue);
      expect(find.byTooltip('Sematkan'), findsOneWidget);
      expect(find.bySemanticsLabel('1 dipilih'), findsOneWidget);
      expect(badged(tester, 'Kebun'), isTrue);
      expect(badged(tester, 'Kerja'), isFalse);
      // The search field and the FAB are gone; the bottom navigation stays.
      expect(find.text('Cari di semua Book'), findsNothing);
      expect(find.text('Book baru').hitTestable(), findsNothing);
      expect(find.text('Linimasa').hitTestable(), findsOneWidget);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      final context = tester.element(find.byType(BookListScreen));
      expect(bar.backgroundColor, selectionBarColor(Theme.of(context)));
    });

    testWidgets('a tap selects and deselects instead of opening', (
      tester,
    ) async {
      await createBooks(['Kebun', 'Kerja']);
      await pumpBookList(tester);
      await longPress(tester, 'Kebun');

      await tap(tester, find.text('Kerja'));
      expect(find.byType(BookScreen), findsNothing);
      expect(badged(tester, 'Kerja'), isTrue);
      expect(find.bySemanticsLabel('2 dipilih'), findsOneWidget);

      await tap(tester, find.text('Kerja'));
      expect(badged(tester, 'Kerja'), isFalse);
      expect(selecting(tester), isTrue);

      // Deselecting the last Book ends selection mode.
      await tap(tester, find.text('Kebun'));
      expect(selecting(tester), isFalse);
      expect(find.text('Book baru').hitTestable(), findsOneWidget);

      // Out of it, a tap opens the Book again.
      await tap(tester, find.text('Kebun'));
      expect(find.byType(BookScreen), findsOneWidget);
    });

    testWidgets('the top bar back ends it and clears the selection', (
      tester,
    ) async {
      await createBooks(['Kebun', 'Kerja']);
      await pumpBookList(tester);
      await longPress(tester, 'Kebun');
      await tap(tester, find.text('Kerja'));

      await tap(tester, find.byType(BackButton));

      expect(selecting(tester), isFalse);
      expect(badged(tester, 'Kebun'), isFalse);
      expect(badged(tester, 'Kerja'), isFalse);
      // Starting again selects only the Book long pressed.
      await longPress(tester, 'Kerja');
      expect(find.bySemanticsLabel('1 dipilih'), findsOneWidget);
    });

    testWidgets('the system back ends it and stays on the Book list', (
      tester,
    ) async {
      await createBooks(['Kebun']);
      await pumpBookList(tester);
      await longPress(tester, 'Kebun');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(selecting(tester), isFalse);
      expect(badged(tester, 'Kebun'), isFalse);
    });

    testWidgets('Android hands back to the app only while selecting', (
      tester,
    ) async {
      // Without this, Android closes the app on back, never asking it.
      final handlesBack = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            handlesBack.add(call.arguments as bool);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await createBooks(['Kebun']);
      await pumpBookList(tester);
      expect(handlesBack.lastOrNull, isNot(isTrue));

      await longPress(tester, 'Kebun');
      expect(handlesBack.last, isTrue);

      await tap(tester, find.text('Kebun'));
      expect(handlesBack.last, isFalse);
    });
  });

  group('pin', () {
    testWidgets('pins the selected Books to the top, with a pin', (
      tester,
    ) async {
      await createBooks(['Resep', 'Kerja', 'Perjalanan', 'Kebun']);
      await pumpBookList(tester);
      expect(names(tester), ['Kebun', 'Perjalanan', 'Kerja', 'Resep']);

      await longPress(tester, 'Kerja');
      await tap(tester, find.text('Resep'));
      await tap(tester, find.byTooltip('Sematkan'));

      expect(names(tester), ['Kerja', 'Resep', 'Kebun', 'Perjalanan']);
      expect(selecting(tester), isFalse);
      expect(pinIcon(tester, 'Kerja'), isTrue);
      expect(pinIcon(tester, 'Kebun'), isFalse);
      expect(find.bySemanticsLabel(RegExp('Disematkan')), findsNWidgets(2));
    });

    testWidgets('a Book written in stays under the Pinned Books', (
      tester,
    ) async {
      final [resep, kebun] = await createBooks(['Resep', 'Kebun']);
      await store.setBooksPinned([resep.id], pinned: true);
      await pumpBookList(tester);

      await store.createEntry(bookId: kebun.id, text: 'Cabai berbunga.');
      await tester.pumpAndSettle();

      expect(names(tester), ['Resep', 'Kebun']);
    });

    testWidgets('mixed: Sematkan pins them all', (tester) async {
      final [resep, _] = await createBooks(['Resep', 'Kebun']);
      await store.setBooksPinned([resep.id], pinned: true);
      await pumpBookList(tester);

      await longPress(tester, 'Resep');
      await tap(tester, find.text('Kebun'));
      expect(find.byTooltip('Lepas sematan'), findsNothing);
      await tap(tester, find.byTooltip('Sematkan'));

      expect(pinIcon(tester, 'Resep'), isTrue);
      expect(pinIcon(tester, 'Kebun'), isTrue);
    });

    testWidgets('all pinned: Lepas sematan unpins them', (tester) async {
      final books = await createBooks(['Resep', 'Kerja', 'Kebun']);
      await store.setBooksPinned([books[0].id, books[1].id], pinned: true);
      await pumpBookList(tester);
      expect(names(tester), ['Kerja', 'Resep', 'Kebun']);

      await longPress(tester, 'Kerja');
      await tap(tester, find.text('Resep'));
      expect(find.byTooltip('Sematkan'), findsNothing);
      await tap(tester, find.byTooltip('Lepas sematan'));

      expect(names(tester), ['Kebun', 'Kerja', 'Resep']);
      expect(pinIcon(tester, 'Kerja'), isFalse);
      expect(selecting(tester), isFalse);
    });

    testWidgets('a fourth Book is refused and selection stays', (tester) async {
      final books = await createBooks(['A', 'B', 'C', 'D']);
      await store.setBooksPinned([
        for (final book in books.take(3)) book.id,
      ], pinned: true);
      await pumpBookList(tester);

      await longPress(tester, 'D');
      await tap(tester, find.byTooltip('Sematkan'));

      expect(find.text('Maksimal 3 Book yang disematkan'), findsOneWidget);
      expect(pinIcon(tester, 'D'), isFalse);
      expect(selecting(tester), isTrue);
      expect(badged(tester, 'D'), isTrue);
    });
  });

  group('delete', () {
    testWidgets('several Books with one dialog counting their Entries', (
      tester,
    ) async {
      final [resep, kerja, _] = await createBooks(['Resep', 'Kerja', 'Kebun']);
      await store.createEntry(bookId: resep.id, text: 'Sambal.');
      await store.createEntry(bookId: kerja.id, text: 'Rapat.');
      await store.createEntry(bookId: kerja.id, text: 'Revisi.');
      await store.setBooksPinned([resep.id], pinned: true);
      await pumpBookList(tester);

      await longPress(tester, 'Resep');
      await tap(tester, find.text('Kerja'));
      await tap(tester, find.byTooltip('Hapus'));

      expect(find.text('Hapus 2 Book?'), findsOneWidget);
      expect(
        find.text(
          '2 Book dan 3 Entry di dalamnya akan hilang selamanya. '
          'Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Ya, hapus'));

      expect(names(tester), ['Kebun']);
      expect(selecting(tester), isFalse);
    });

    testWidgets('Batal deletes nothing and keeps the selection', (
      tester,
    ) async {
      await createBooks(['Resep', 'Kerja']);
      await pumpBookList(tester);
      await longPress(tester, 'Resep');
      await tap(tester, find.text('Kerja'));
      await tap(tester, find.byTooltip('Hapus'));

      await tap(tester, find.text('Batal'));

      expect(names(tester), ['Kerja', 'Resep']);
      expect(selecting(tester), isTrue);
      expect(find.bySemanticsLabel('2 dipilih'), findsOneWidget);
    });

    testWidgets('one Book asks with its name', (tester) async {
      final [resep] = await createBooks(['Resep']);
      await store.createEntry(bookId: resep.id, text: 'Sambal.');
      await pumpBookList(tester);
      await longPress(tester, 'Resep');

      await tap(tester, find.byTooltip('Hapus'));

      expect(find.text('Hapus Book?'), findsOneWidget);
      expect(
        find.text(
          '“Resep” dan 1 Entry di dalamnya akan hilang selamanya. '
          'Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );
    });
  });
}
