import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/image_viewer_screen.dart';
import 'package:kronoer/src/search/search_screen.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/timeline/timeline_books_screen.dart';
import 'package:kronoer/src/timeline/timeline_screen.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  final now = DateTime(2026, 11, 19, 14, 32);
  late InMemoryStore store;

  setUp(() => store = InMemoryStore(clock: () => now));
  tearDown(() => store.dispose());

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

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  int selectedTab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  /// The bar on screen, not under a screen that covers it.
  Finder visibleBar() => find.byType(NavigationBar).hitTestable();

  /// The screen of type [T] on screen, not under another one.
  Finder visible<T>() => find.byType(T).hitTestable();

  /// The labels in the open ⋮ menu, in order.
  List<String?> menuItems(WidgetTester tester) => [
    for (final item in tester.widgetList<Widget>(
      find.byWidgetPredicate((w) => w is MenuItemButton || w is SubmenuButton),
    ))
      switch (item) {
        MenuItemButton(:final child) ||
        SubmenuButton(:final child) => (child! as Text).data,
        _ => null,
      },
  ];

  ScrollPosition timelinePosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(TimelineScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  group('tabs', () {
    testWidgets('the app opens on Book, with Linimasa and Pengaturan', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(visible<BookListScreen>(), findsOneWidget);
      expect(selectedTab(tester), 0);
      for (final label in ['Book', 'Linimasa', 'Pengaturan']) {
        expect(tab(label), findsOneWidget, reason: label);
      }
      // The active tab has a filled icon, the others a stroke one.
      final icons = tester.widgetList<KIcon>(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byType(KIcon),
        ),
      );
      expect(
        [for (final icon in icons) (icon.icon, icon.filled)],
        [
          (KIcons.book, true),
          (KIcons.timeline, false),
          (KIcons.settings, false),
        ],
      );
    });

    testWidgets('the bar shows only on the three tabs', (tester) async {
      final book = await store.createBook('Kebun');
      await store.createEntry(bookId: book.id, text: 'Tomat berbuah.');
      await pumpApp(tester);
      expect(visibleBar(), findsOneWidget);

      await tapAndSettle(tester, find.text('Kebun'));
      expect(visible<BookScreen>(), findsOneWidget);
      expect(visibleBar(), findsNothing);

      await tapAndSettle(tester, find.text('Tomat berbuah.'));
      expect(visible<EntryReadScreen>(), findsOneWidget);
      expect(visibleBar(), findsNothing);

      await tapAndSettle(tester, find.byTooltip('Ubah Entry'));
      expect(visible<EntryEditorScreen>(), findsOneWidget);
      expect(visibleBar(), findsNothing);

      await back(tester);
      await back(tester);
      await back(tester);
      expect(visible<BookListScreen>(), findsOneWidget);
      await tapAndSettle(tester, find.text('Cari di semua Book'));
      expect(visible<SearchScreen>(), findsOneWidget);
      expect(visibleBar(), findsNothing);

      await back(tester);
      await tapAndSettle(tester, tab('Pengaturan'));
      expect(visibleBar(), findsOneWidget);
      await tapAndSettle(tester, find.text('Tema'));
      expect(visible<ThemeScreen>(), findsOneWidget);
      expect(visibleBar(), findsNothing);
    });

    testWidgets('Pengaturan has no back button', (tester) async {
      await pumpApp(tester);

      await tapAndSettle(tester, tab('Pengaturan'));

      expect(visible<SettingsScreen>(), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    for (final label in ['Linimasa', 'Pengaturan']) {
      testWidgets('back from $label goes to the Book tab', (tester) async {
        await pumpApp(tester);
        await tapAndSettle(tester, tab(label));
        expect(selectedTab(tester), isNot(0));

        await back(tester);

        expect(selectedTab(tester), 0);
        expect(visible<BookListScreen>(), findsOneWidget);
      });
    }

    testWidgets('back from the Book tab leaves the app', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpApp(tester);

      await back(tester);

      expect(calls, contains('SystemNavigator.pop'));
    });

    testWidgets('each tab keeps its scroll; tapping it again goes to the top', (
      tester,
    ) async {
      final book = await store.createBook('Kebun');
      for (var day = 1; day <= 28; day++) {
        await store.createEntry(
          bookId: book.id,
          text: 'Hari $day di kebun.',
          dateTime: DateTime(2026, 10, day, 8),
        );
      }
      await pumpApp(tester);
      await tapAndSettle(tester, tab('Linimasa'));

      await tester.drag(find.byType(TimelineScreen), const Offset(0, -900));
      await tester.pumpAndSettle();
      final scrolled = timelinePosition(tester).pixels;
      expect(scrolled, greaterThan(0));

      await tapAndSettle(tester, tab('Book'));
      await tapAndSettle(tester, tab('Linimasa'));
      expect(timelinePosition(tester).pixels, scrolled);

      await tapAndSettle(tester, tab('Linimasa'));
      expect(timelinePosition(tester).pixels, 0);
    });
  });

  group('Linimasa', () {
    testWidgets('lists every Entry of every Book, newest Entry date first', (
      tester,
    ) async {
      final kebun = await store.createBook('Kebun');
      final jalan = await store.createBook('Jalan-jalan');
      for (final (book, text, date) in [
        (kebun, 'Tomat berbuah.', DateTime(2026, 11, 18, 7)),
        (jalan, 'Sampai di stasiun.', DateTime(2026, 11, 2, 19)),
        (kebun, 'Menanam cabai.', DateTime(2019, 6, 1, 9)),
        (jalan, 'Naik kereta pagi.', DateTime(2026, 10, 30, 6)),
      ]) {
        await store.createEntry(bookId: book.id, text: text, dateTime: date);
      }
      await pumpApp(tester);

      await tapAndSettle(tester, tab('Linimasa'));

      expect(visible<TimelineScreen>(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Linimasa'),
        ),
        findsOneWidget,
      );
      // An Entry dated 2019 sits in 2019, not at the top.
      final texts = [
        'November 2026',
        'Tomat berbuah.',
        'Sampai di stasiun.',
        'Oktober 2026',
        'Naik kereta pagi.',
        'Juni 2019',
        'Menanam cabai.',
      ];
      for (final text in texts) {
        await tester.scrollUntilVisible(
          find.text(text),
          200,
          scrollable: find
              .descendant(
                of: find.byType(TimelineScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      await tester.drag(find.byType(TimelineScreen), const Offset(0, 3000));
      await tester.pumpAndSettle();

      // Each card names its Book.
      for (final (text, book) in [
        ('Tomat berbuah.', 'Kebun'),
        ('Sampai di stasiun.', 'Jalan-jalan'),
      ]) {
        final card = find.ancestor(
          of: find.text(text),
          matching: find.byType(KCard),
        );
        expect(
          find.descendant(of: card, matching: find.text(book)),
          findsOneWidget,
          reason: text,
        );
      }
      final tops = [
        for (final text in texts.take(3)) tester.getTopLeft(find.text(text)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('with no Entry at all, says so', (tester) async {
      await store.createBook('Kebun');
      await pumpApp(tester);

      await tapAndSettle(tester, tab('Linimasa'));

      expect(find.text('Belum ada Entry'), findsOneWidget);
      expect(
        find.text('Entry yang kamu tulis di Book akan muncul di sini.'),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);

      // Nothing to find or sort, but the Books can still be chosen.
      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      expect(menuItems(tester), ['Book di Linimasa']);
    });

    testWidgets('with no Book at all, there is no ⋮', (tester) async {
      await pumpApp(tester);

      await tapAndSettle(tester, tab('Linimasa'));

      expect(find.text('Belum ada Entry'), findsOneWidget);
      expect(find.byTooltip('Opsi lainnya'), findsNothing);
    });

    testWidgets('a card opens the Entry; back returns to Linimasa', (
      tester,
    ) async {
      final book = await store.createBook('Kebun');
      await store.createEntry(bookId: book.id, text: 'Tomat berbuah.');
      await pumpApp(tester);
      await tapAndSettle(tester, tab('Linimasa'));

      await tapAndSettle(tester, find.text('Tomat berbuah.'));
      expect(visible<EntryReadScreen>(), findsOneWidget);

      await back(tester);
      expect(visible<TimelineScreen>(), findsOneWidget);
      expect(selectedTab(tester), 1);
    });

    /// Opens the Entry "Tomat berbuah." from Linimasa.
    Future<void> openFromTimeline(
      WidgetTester tester, {
      List<String> imageIds = const [],
    }) async {
      final book = await store.createBook('Kebun');
      await store.createEntry(
        bookId: book.id,
        text: 'Tomat berbuah.',
        imageIds: imageIds,
      );
      await pumpApp(tester);
      await tapAndSettle(tester, tab('Linimasa'));
      await tapAndSettle(tester, find.text('Tomat berbuah.'));
      expect(visible<EntryReadScreen>(), findsOneWidget);
    }

    void expectTimeline(WidgetTester tester) {
      expect(visible<TimelineScreen>(), findsOneWidget);
      expect(selectedTab(tester), 1);
    }

    testWidgets('editing returns to the Entry, and back to Linimasa', (
      tester,
    ) async {
      await openFromTimeline(tester);

      await tapAndSettle(tester, find.byTooltip('Ubah Entry'));
      await back(tester);
      expect(visible<EntryReadScreen>(), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Ubah Entry'));
      await tester.enterText(find.byType(TextField), 'Tomat merah.');
      await tapAndSettle(tester, find.text('Selesai'));
      expect(visible<EntryReadScreen>(), findsOneWidget);
      expect(find.text('Tomat merah.'), findsOneWidget);

      await back(tester);
      expectTimeline(tester);
      expect(find.text('Tomat merah.'), findsOneWidget);
    });

    testWidgets('an Image closes to the Entry, and back to Linimasa', (
      tester,
    ) async {
      await openFromTimeline(tester, imageIds: ['a']);

      await tapAndSettle(tester, find.byType(EntryImage).first);
      expect(visible<ImageViewerScreen>(), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byWidgetPredicate((w) => w is KIcon && w.icon == KIcons.x),
      );
      expect(visible<EntryReadScreen>(), findsOneWidget);

      await back(tester);
      expectTimeline(tester);
    });

    for (final from in ['read view', 'editor']) {
      testWidgets('deleting from the $from returns to Linimasa', (
        tester,
      ) async {
        await openFromTimeline(tester);
        if (from == 'editor') {
          await tapAndSettle(tester, find.byTooltip('Ubah Entry'));
        }

        await tapAndSettle(
          tester,
          find.byWidgetPredicate(
            (w) => w is KIcon && w.icon == KIcons.moreVertical,
          ),
        );
        await tapAndSettle(tester, find.text('Hapus Entry'));

        expectTimeline(tester);
        expect(find.text('Entry dihapus'), findsOneWidget);
        expect(find.text('Tomat berbuah.'), findsNothing);
      });
    }

    testWidgets('⋮ has Cari and Urutkan; oldest first flips the list', (
      tester,
    ) async {
      final kebun = await store.createBook('Kebun');
      final jalan = await store.createBook('Jalan-jalan');
      for (final (book, text, date) in [
        (kebun, 'Tomat berbuah.', DateTime(2026, 11, 18, 7)),
        (jalan, 'Naik kereta pagi.', DateTime(2026, 10, 30, 6)),
        (kebun, 'Menanam cabai.', DateTime(2019, 6, 1, 9)),
      ]) {
        await store.createEntry(bookId: book.id, text: text, dateTime: date);
      }
      await pumpApp(tester);
      await tapAndSettle(tester, tab('Linimasa'));
      expect(find.byTooltip('Cari di semua Book'), findsNothing);

      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      expect(menuItems(tester), ['Cari', 'Urutkan', 'Book di Linimasa']);
      await tapAndSettle(tester, find.text('Urutkan'));
      await tapAndSettle(tester, find.text('Terlama dulu'));

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      final texts = [
        'Juni 2019',
        'Menanam cabai.',
        'Oktober 2026',
        'Naik kereta pagi.',
        'November 2026',
        'Tomat berbuah.',
      ];
      for (var i = 1; i < texts.length; i++) {
        expect(top(texts[i - 1]), lessThan(top(texts[i])));
      }

      // It stays while switching tabs.
      await tapAndSettle(tester, tab('Book'));
      await tapAndSettle(tester, tab('Linimasa'));
      expect(top('Menanam cabai.'), lessThan(top('Tomat berbuah.')));
    });

    testWidgets('search opens in every Book; back returns to Linimasa', (
      tester,
    ) async {
      final book = await store.createBook('Kebun');
      await store.createEntry(bookId: book.id, text: 'Tomat berbuah.');
      await pumpApp(tester);
      await tapAndSettle(tester, tab('Linimasa'));

      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      await tapAndSettle(tester, find.text('Cari'));
      final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
      expect(search.bookId, isNull);

      await back(tester);
      expect(visible<TimelineScreen>(), findsOneWidget);
    });

    testWidgets('a new Entry shows up', (tester) async {
      final book = await store.createBook('Kebun');
      await pumpApp(tester);
      await tapAndSettle(tester, tab('Linimasa'));
      expect(find.text('Belum ada Entry'), findsOneWidget);

      await store.createEntry(bookId: book.id, text: 'Tomat berbuah.');
      await tester.pumpAndSettle();

      expect(find.text('Tomat berbuah.'), findsOneWidget);
      expect(find.text('Kebun'), findsOneWidget);
    });
  });

  group('Book di Linimasa', () {
    late Book kebun;
    late Book jalan;

    setUp(() async {
      kebun = await store.createBook('Kebun');
      jalan = await store.createBook('Jalan-jalan');
      await store.createEntry(bookId: kebun.id, text: 'Tomat berbuah.');
      await store.createEntry(bookId: jalan.id, text: 'Naik kereta pagi.');
    });

    Future<void> openPage(WidgetTester tester) async {
      await pumpApp(tester);
      await tapAndSettle(tester, tab('Linimasa'));
      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      await tapAndSettle(tester, find.text('Book di Linimasa'));
      expect(visible<TimelineBooksScreen>(), findsOneWidget);
    }

    bool? checked(WidgetTester tester, String name) => tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, name))
        .value;

    testWidgets('lists every Book in Book list order, all checked', (
      tester,
    ) async {
      // A pinned Book comes first in the Book list, so here too.
      await store.setBooksPinned([jalan.id], pinned: true);
      await openPage(tester);

      expect(find.widgetWithText(AppBar, 'Book di Linimasa'), findsOneWidget);
      expect(find.byTooltip('Kembali'), findsOneWidget);
      final rows = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(
        [for (final row in rows) (row.title! as Text).data],
        ['Jalan-jalan', 'Kebun'],
      );
      expect([for (final row in rows) row.value], [true, true]);
      expect(find.byType(CoverThumbnail), findsNWidgets(2));
    });

    testWidgets('unchecking keeps the Book out at once; back shows it gone', (
      tester,
    ) async {
      await openPage(tester);

      await tapAndSettle(tester, find.text('Kebun'));
      expect(checked(tester, 'Kebun'), isFalse);
      expect((await store.watchBook(kebun.id).first)!.inTimeline, isFalse);

      await back(tester);
      expect(visible<TimelineScreen>(), findsOneWidget);
      expect(find.text('Tomat berbuah.'), findsNothing);
      expect(find.text('Naik kereta pagi.'), findsOneWidget);
    });

    testWidgets('checking it again brings it back', (tester) async {
      await store.setBookInTimeline(kebun.id, inTimeline: false);
      await openPage(tester);
      expect(checked(tester, 'Kebun'), isFalse);

      await tapAndSettle(tester, find.text('Kebun'));
      await back(tester);

      expect(find.text('Tomat berbuah.'), findsOneWidget);
    });

    testWidgets('with every Book kept out, the Timeline says so', (
      tester,
    ) async {
      await openPage(tester);

      await tapAndSettle(tester, find.text('Kebun'));
      await tapAndSettle(tester, find.text('Jalan-jalan'));
      expect(checked(tester, 'Kebun'), isFalse);
      expect(checked(tester, 'Jalan-jalan'), isFalse);
      await back(tester);

      expect(
        find.text('Tidak ada Book yang ditampilkan di Linimasa'),
        findsOneWidget,
      );
      expect(find.text('Belum ada Entry'), findsNothing);
      expect(
        find.text('Entry yang kamu tulis di Book akan muncul di sini.'),
        findsNothing,
      );
      expect(find.byType(FilledButton), findsNothing);

      // The way back stays in ⋮, without Cari and Urutkan.
      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      expect(menuItems(tester), ['Book di Linimasa']);
    });

    testWidgets('a Book kept out without Entries leaves the usual message', (
      tester,
    ) async {
      final empty = await store.createBook('Kosong');
      await store.setBookInTimeline(kebun.id, inTimeline: false);
      await store.setBookInTimeline(jalan.id, inTimeline: false);
      // Kosong is in the Timeline but has nothing to show.
      expect(empty.inTimeline, isTrue);
      await pumpApp(tester);

      await tapAndSettle(tester, tab('Linimasa'));

      expect(find.text('Belum ada Entry'), findsOneWidget);
    });

    testWidgets('a Book kept out from Book info shows unchecked', (
      tester,
    ) async {
      await store.setBookInTimeline(kebun.id, inTimeline: false);
      await pumpApp(tester);

      await tapAndSettle(tester, tab('Linimasa'));
      expect(find.text('Tomat berbuah.'), findsNothing);

      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      await tapAndSettle(tester, find.text('Book di Linimasa'));
      expect(checked(tester, 'Kebun'), isFalse);
    });

    testWidgets('is in English on an English device', (tester) async {
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
      await store.setBookInTimeline(kebun.id, inTimeline: false);
      await store.setBookInTimeline(jalan.id, inTimeline: false);
      await tapAndSettle(tester, tab('Timeline'));

      expect(find.text('No Book is shown in the Timeline'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('More options'));
      expect(find.text('Books in Timeline'), findsOneWidget);
    });
  });
}
