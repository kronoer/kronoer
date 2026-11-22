import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_description_screen.dart';
import 'package:kronoer/src/books/book_info_screen.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_name_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/search/search_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/open_ink_well.dart';
import 'package:kronoer/src/ui/setting_row.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final now = DateTime(2026, 11, 19, 14, 32);
  late InMemoryStore store;
  late Book book;

  setUp(() async {
    store = InMemoryStore(clock: () => now);
    book = await store.createBook('Buku Saya');
  });
  tearDown(() => store.dispose());

  Future<void> write(String text, DateTime at, {int images = 0}) =>
      store.createEntry(
        bookId: book.id,
        text: text,
        dateTime: at,
        imageIds: [for (var i = 0; i < images; i++) '$text-$i'],
      );

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Opens [book] from the Book list.
  Future<void> openBook(
    WidgetTester tester, {
    Locale locale = const Locale('id'),
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];
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
    await tapAndSettle(tester, find.text(book.name));
    expect(find.byType(BookScreen), findsOneWidget);
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  group('order', () {
    testWidgets('newest entry date first, same day by time', (tester) async {
      await write('Sabtu malam.', DateTime(2026, 11, 14, 21, 15));
      await write('Senin pagi.', DateTime(2026, 11, 16, 7, 5));
      await write('Senin malam.', DateTime(2026, 11, 16, 19, 40));
      // Written last, but dated earliest.
      await write('Oktober.', DateTime(2026, 10, 3, 9));

      await openBook(tester);

      final order = ['Senin malam.', 'Senin pagi.', 'Sabtu malam.', 'Oktober.'];
      for (var i = 1; i < order.length; i++) {
        expect(top(tester, order[i - 1]), lessThan(top(tester, order[i])));
      }
    });

    testWidgets('a card shows the day, the time, and the text', (tester) async {
      await write('Pagi ini hujan.', DateTime(2026, 11, 16, 19, 40));

      await openBook(tester);

      expect(find.text('Senin, 16 Nov'), findsOneWidget);
      expect(find.text('19.40'), findsOneWidget);
      expect(find.text('Pagi ini hujan.'), findsOneWidget);
    });

    testWidgets('the text is one paragraph of at most 4 lines', (tester) async {
      await write('Satu.\n\nDua.', DateTime(2026, 11, 16));

      await openBook(tester);

      expect(tester.widget<Text>(find.text('Satu. Dua.')).maxLines, 4);
    });

    testWidgets('images show as placeholders', (tester) async {
      await write('Satu foto.', DateTime(2026, 11, 16), images: 1);
      await write('Tiga foto.', DateTime(2026, 11, 15), images: 3);

      await openBook(tester);

      expect(find.byType(EntryImage), findsNWidgets(4));
    });

    testWidgets('a tap on a card opens the Entry', (tester) async {
      await write('Pagi ini hujan.', DateTime(2026, 11, 16));
      await openBook(tester);

      await tapAndSettle(tester, find.text('Pagi ini hujan.'));

      expect(find.byType(EntryReadScreen), findsOneWidget);
    });
  });

  group('sort', () {
    Future<void> sortBy(WidgetTester tester, String order) async {
      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      await tapAndSettle(tester, find.text('Urutkan'));
      await tapAndSettle(tester, find.text(order));
    }

    /// The order of [texts] on screen, top to bottom.
    void expectOrder(WidgetTester tester, List<String> texts) {
      for (var i = 1; i < texts.length; i++) {
        expect(
          top(tester, texts[i - 1]),
          lessThan(top(tester, texts[i])),
          reason: '${texts[i - 1]} above ${texts[i]}',
        );
      }
    }

    testWidgets('Urutkan offers both orders, the current one checked', (
      tester,
    ) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await openBook(tester);

      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      await tapAndSettle(tester, find.text('Urutkan'));

      expect(
        top(tester, 'Terbaru dulu'),
        lessThan(top(tester, 'Terlama dulu')),
      );
      Finder checkIn(String item) => find.descendant(
        of: find.widgetWithText(MenuItemButton, item),
        matching: find.byWidgetPredicate(
          (w) => w is KIcon && w.icon == KIcons.check,
        ),
      );
      expect(checkIn('Terbaru dulu'), findsOneWidget);
      expect(checkIn('Terlama dulu'), findsNothing);

      await tapAndSettle(tester, find.text('Terlama dulu'));
      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));
      await tapAndSettle(tester, find.text('Urutkan'));
      expect(checkIn('Terbaru dulu'), findsNothing);
      expect(checkIn('Terlama dulu'), findsOneWidget);
    });

    testWidgets('oldest first flips the cards and the month separators', (
      tester,
    ) async {
      await write('Oktober.', DateTime(2026, 10, 3, 9));
      await write('Senin pagi.', DateTime(2026, 11, 16, 7, 5));
      await write('Senin malam.', DateTime(2026, 11, 16, 19, 40));
      await openBook(tester);

      await sortBy(tester, 'Terlama dulu');

      expectOrder(tester, [
        'Oktober 2026',
        'Oktober.',
        'November 2026',
        'Senin pagi.',
        'Senin malam.',
      ]);

      await sortBy(tester, 'Terbaru dulu');
      expectOrder(tester, [
        'November 2026',
        'Senin malam.',
        'Senin pagi.',
        'Oktober 2026',
        'Oktober.',
      ]);
    });

    testWidgets('switching jumps back to the top', (tester) async {
      for (var i = 0; i < 30; i++) {
        await write(
          'Entry $i.',
          DateTime(2026, 11, 18).subtract(Duration(days: i)),
        );
      }
      await openBook(tester);
      await tester.drag(find.text('Entry 2.'), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(find.text('Entry 0.'), findsNothing);

      await sortBy(tester, 'Terlama dulu');

      expect(find.text('Entry 29.'), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(BookScreen),
                matching: find.byType(Scrollable),
              ),
            )
            .position
            .pixels,
        0,
      );
    });

    testWidgets('stays while an Entry is open and after coming back', (
      tester,
    ) async {
      await write('Lama.', DateTime(2026, 10, 3));
      await write('Baru.', DateTime(2026, 11, 16));
      await openBook(tester);
      await sortBy(tester, 'Terlama dulu');

      await tapAndSettle(tester, find.text('Baru.'));
      expect(find.byType(EntryReadScreen), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Kembali'));

      expectOrder(tester, ['Lama.', 'Baru.']);
    });

    testWidgets('a new Entry lands in its place', (tester) async {
      await write('Lama.', DateTime(2026, 10, 3));
      await write('Baru.', DateTime(2026, 11, 16));
      await openBook(tester);
      await sortBy(tester, 'Terlama dulu');

      await write('Tengah.', DateTime(2026, 11, 1));
      await tester.pumpAndSettle();

      expectOrder(tester, ['Lama.', 'Tengah.', 'Baru.']);
    });

    testWidgets('goes back to newest first after leaving the Book', (
      tester,
    ) async {
      await write('Lama.', DateTime(2026, 10, 3));
      await write('Baru.', DateTime(2026, 11, 16));
      await openBook(tester);
      await sortBy(tester, 'Terlama dulu');
      expectOrder(tester, ['Lama.', 'Baru.']);

      await tapAndSettle(tester, find.byTooltip('Kembali'));
      expect(find.byType(BookListScreen), findsOneWidget);
      await tapAndSettle(tester, find.text(book.name));

      expectOrder(tester, ['Baru.', 'Lama.']);
    });

    testWidgets('is in English on an English device', (tester) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await openBook(tester, locale: const Locale('en'));

      await tapAndSettle(tester, find.byTooltip('More options'));
      expect(find.text('Book info'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      await tapAndSettle(tester, find.text('Sort'));
      expect(find.text('Newest first'), findsOneWidget);
      expect(find.text('Oldest first'), findsOneWidget);
    });
  });

  group('month separators', () {
    testWidgets('one above the first Entry of each month', (tester) async {
      await write('November satu.', DateTime(2026, 11, 16));
      await write('November dua.', DateTime(2026, 11, 2));
      await write('Oktober.', DateTime(2026, 10, 30));
      await write('Tahun lalu.', DateTime(2025, 11, 20));

      await openBook(tester);

      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Oktober 2026'), findsOneWidget);
      expect(find.text('November 2025'), findsOneWidget);
      expect(
        top(tester, 'November 2026'),
        lessThan(top(tester, 'November satu.')),
      );
      expect(
        top(tester, 'November dua.'),
        lessThan(top(tester, 'Oktober 2026')),
      );
      expect(top(tester, 'Oktober 2026'), lessThan(top(tester, 'Oktober.')));
    });

    testWidgets('are in English on an English device', (tester) async {
      await write('Oktober.', DateTime(2026, 10, 30, 21, 5));

      await openBook(tester, locale: const Locale('en'));

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Friday, 30 Oct'), findsOneWidget);
      expect(find.text('21:05'), findsOneWidget);
    });
  });

  group('scrollbar', () {
    final thumb = find.byKey(const ValueKey('scrollbarThumb'));

    testWidgets('is not there when everything fits', (tester) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await openBook(tester);

      expect(thumb, findsNothing);
    });

    testWidgets('shows the month while dragging', (tester) async {
      for (var i = 0; i < 40; i++) {
        await write(
          'Entry $i.',
          DateTime(2026, 11, 18, 20).subtract(Duration(days: 6 * i)),
        );
      }
      // The oldest month holds more than a screen of cards.
      for (var day = 1; day <= 10; day++) {
        await write('Februari $day.', DateTime(2026, 2, day));
      }
      await openBook(tester);

      expect(find.text('Nov 2026'), findsNothing);

      final drag = await tester.startGesture(tester.getCenter(thumb));
      await tester.pump();
      expect(find.text('Nov 2026'), findsOneWidget);

      // Past the end, a few times, as the list learns its real length.
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, 200));
        await tester.pump();
        await tester.pump();
      }
      expect(find.text('Feb 2026'), findsOneWidget);
      expect(find.text('Februari 10.'), findsNothing);

      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('Feb 2026'), findsNothing);
    });
  });

  group('empty Book', () {
    testWidgets('shows the message and the pen', (tester) async {
      await openBook(tester);

      expect(find.text('Belum ada Entry'), findsOneWidget);
      expect(find.text('Tulis Entry pertama di Book ini.'), findsOneWidget);
      expect(find.byTooltip('Tulis Entry'), findsOneWidget);
    });

    testWidgets('the pen opens the editor', (tester) async {
      await openBook(tester);

      await tapAndSettle(tester, find.byTooltip('Tulis Entry'));

      expect(find.byType(EntryEditorScreen), findsOneWidget);
    });
  });

  /// Opens [book] and then its Book info, from the ⋮ menu.
  Future<void> openInfo(
    WidgetTester tester, {
    Locale locale = const Locale('id'),
  }) async {
    await openBook(tester, locale: locale);
    final english = locale.languageCode == 'en';
    await tapAndSettle(
      tester,
      find.byTooltip(english ? 'More options' : 'Opsi lainnya'),
    );
    await tapAndSettle(tester, find.text(english ? 'Book info' : 'Info Book'));
    expect(find.byType(BookInfoScreen), findsOneWidget);
  }

  Future<void> chooseInMenu(WidgetTester tester, String item) async {
    await tapAndSettle(tester, find.byTooltip('Menu Book'));
    await tapAndSettle(tester, find.text(item));
  }

  group('top bar', () {
    testWidgets('has back, the name, and ⋮, with no search or ⓘ icon', (
      tester,
    ) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await openBook(tester);

      expect(find.byTooltip('Kembali'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Buku Saya'), findsOneWidget);
      expect(find.byTooltip('Opsi lainnya'), findsOneWidget);
      expect(find.byTooltip('Cari di Buku Saya'), findsNothing);
      expect(find.byTooltip('Info Book'), findsNothing);
      expect(find.byType(IconButton), findsNWidgets(2), reason: 'back and ⋮');
    });

    testWidgets('⋮ has Info Book, Cari, and Urutkan', (tester) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await openBook(tester);

      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));

      final items = ['Info Book', 'Cari', 'Urutkan'];
      for (var i = 1; i < items.length; i++) {
        expect(top(tester, items[i - 1]), lessThan(top(tester, items[i])));
      }
      await tapAndSettle(tester, find.text('Cari'));
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('⋮ in an empty Book has only Info Book', (tester) async {
      await openBook(tester);

      await tapAndSettle(tester, find.byTooltip('Opsi lainnya'));

      expect(find.text('Info Book'), findsOneWidget);
      expect(find.text('Cari'), findsNothing);
      expect(find.text('Urutkan'), findsNothing);
    });

    testWidgets('a tap on the name opens Book info', (tester) async {
      await openBook(tester);

      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Buku Saya'),
        ),
      );

      expect(find.byType(BookInfoScreen), findsOneWidget);
    });

    testWidgets('the name button fills the bar up to the actions, square', (
      tester,
    ) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await openBook(tester);

      final button = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(OpenInkWell),
      );
      final bar = tester.getRect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(NavigationToolbar),
        ),
      );
      final buttonRect = tester.getRect(button);
      expect((buttonRect.top, buttonRect.bottom), (bar.top, bar.bottom));
      expect(tester.widget<OpenInkWell>(button).customBorder, isNull);

      final name = tester.getRect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Buku Saya'),
        ),
      );
      final menu = tester.getRect(find.byTooltip('Opsi lainnya'));
      expect(menu.left - name.right, greaterThan(100), reason: 'a short name');

      // Just left of ⋮, far from the name.
      await tester.tapAt(Offset(menu.left - 8, menu.center.dy));
      await tester.pumpAndSettle();

      expect(find.byType(BookInfoScreen), findsOneWidget);
    });

    testWidgets('the name is a button TalkBack reads as Info Book', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openBook(tester);

      expect(
        tester.getSemantics(
          find
              .ancestor(
                of: find.text('Buku Saya'),
                matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.label == 'Info Book',
                ),
              )
              .first,
        ),
        matchesSemantics(
          label: 'Info Book\nBuku Saya',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('back from Book info returns to the Book', (tester) async {
      await openInfo(tester);

      await tapAndSettle(tester, find.byTooltip('Kembali'));

      expect(find.byType(BookScreen), findsOneWidget);
    });
  });

  group('Book info', () {
    testWidgets('shows the name and the Description', (tester) async {
      await store.setBookDescription(book.id, 'Catatan harian.\nSejak 2024.');
      await openInfo(tester);

      expect(find.text('Buku Saya'), findsOneWidget);
      expect(find.text('Catatan harian.\nSejak 2024.'), findsOneWidget);
      expect(find.text('Tambah deskripsi'), findsNothing);
      expect(find.text('Selengkapnya', findRichText: true), findsNothing);
    });

    testWidgets('a long Description folds to 3 lines with Selengkapnya', (
      tester,
    ) async {
      final long = List.filled(40, 'Hari ini hujan lagi.').join(' ');
      await store.setBookDescription(book.id, long);
      await openInfo(tester);

      final folded = find.byType(FoldedDescription);
      final more = find.textContaining('Selengkapnya', findRichText: true);
      expect(more, findsOneWidget);
      expect(
        find.textContaining('… Selengkapnya', findRichText: true),
        findsOneWidget,
      );
      final lineHeight = 24.0;
      expect(
        tester.getSize(folded).height,
        lessThanOrEqualTo(3 * lineHeight + 1),
      );

      await tester.tapOnText(find.textRange.ofSubstring('Selengkapnya'));
      await tester.pumpAndSettle();

      expect(find.text(long), findsOneWidget);
      expect(more, findsNothing);
      expect(tester.getSize(folded).height, greaterThan(3 * lineHeight + 1));
    });

    testWidgets('without a Description, Tambah deskripsi opens the page', (
      tester,
    ) async {
      await openInfo(tester);

      expect(
        find.widgetWithText(FilledButton, 'Tambah deskripsi'),
        findsOneWidget,
      );
      await tapAndSettle(tester, find.text('Tambah deskripsi'));

      expect(find.byType(BookDescriptionScreen), findsOneWidget);
    });

    testWidgets('the menu has only Ubah nama and Ubah deskripsi', (
      tester,
    ) async {
      await openInfo(tester);

      await tapAndSettle(tester, find.byTooltip('Menu Book'));

      final items = tester
          .widgetList<MenuItemButton>(find.byType(MenuItemButton))
          .toList();
      expect(
        [for (final item in items) (item.child! as Text).data],
        ['Ubah nama', 'Ubah deskripsi'],
      );
      expect([for (final item in items) item.leadingIcon], [null, null]);
    });

    testWidgets('rows below the Description: Linimasa, then Hapus Book', (
      tester,
    ) async {
      await openInfo(tester);

      final rows = tester
          .widgetList<SettingRow>(find.byType(SettingRow))
          .toList();
      expect(
        [for (final row in rows) (row.icon, row.title)],
        [
          (KIcons.timelineBook, 'Tampilkan di Linimasa'),
          (KIcons.bin, 'Hapus Book'),
        ],
      );
      expect(
        top(tester, 'Tampilkan di Linimasa'),
        greaterThan(top(tester, 'Tambah deskripsi')),
      );
      // Hapus Book has no hint.
      expect(rows.last.subtitle, isNull);
    });

    testWidgets('the icon and the switch line up with the title', (
      tester,
    ) async {
      await openInfo(tester);

      final row = find.widgetWithText(ListTile, 'Tampilkan di Linimasa');
      final title = tester.getCenter(find.text('Tampilkan di Linimasa')).dy;
      final hint = tester.getCenter(
        find.text('Entry Book ini muncul di Linimasa'),
      );
      final icon = find.descendant(of: row, matching: find.byType(KIcon));
      final toggle = find.descendant(of: row, matching: find.byType(Switch));

      expect(tester.getCenter(icon).dy, closeTo(title, 0.5));
      expect(tester.getCenter(toggle).dy, closeTo(title, 0.5));
      expect(hint.dy, greaterThan(title));
    });

    testWidgets('is in English on an English device', (tester) async {
      await openInfo(tester, locale: const Locale('en'));

      expect(find.text('Add description'), findsOneWidget);
      expect(find.text('Show in Timeline'), findsOneWidget);
      expect(
        find.text("This Book's Entries show in the Timeline"),
        findsOneWidget,
      );
      expect(find.text('Delete Book'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Book menu'));
      expect(find.text('Edit name'), findsOneWidget);
      expect(find.text('Edit description'), findsOneWidget);
    });
  });

  group('show in Timeline', () {
    Finder row() => find.widgetWithText(ListTile, 'Tampilkan di Linimasa');
    Switch switchOf(WidgetTester tester) => tester.widget<Switch>(
      find.descendant(of: row(), matching: find.byType(Switch)),
    );
    Future<bool> saved() async =>
        (await store.watchBook(book.id).first)!.inTimeline;

    testWidgets('is on by default, with its hint', (tester) async {
      await openInfo(tester);

      expect(switchOf(tester).value, isTrue);
      expect(find.text('Entry Book ini muncul di Linimasa'), findsOneWidget);
    });

    testWidgets('the switch keeps the Book out, and the hint follows', (
      tester,
    ) async {
      await openInfo(tester);

      await tapAndSettle(
        tester,
        find.descendant(of: row(), matching: find.byType(Switch)),
      );

      expect(await saved(), isFalse);
      expect(switchOf(tester).value, isFalse);
      expect(
        find.text('Entry Book ini tidak muncul di Linimasa'),
        findsOneWidget,
      );
      expect(find.text('Entry Book ini muncul di Linimasa'), findsNothing);
    });

    testWidgets('tapping anywhere on the row toggles it, both ways', (
      tester,
    ) async {
      await openInfo(tester);

      await tapAndSettle(tester, find.text('Tampilkan di Linimasa'));
      expect(await saved(), isFalse);
      expect(switchOf(tester).value, isFalse);

      await tapAndSettle(
        tester,
        find.text('Entry Book ini tidak muncul di Linimasa'),
      );
      expect(await saved(), isTrue);
      expect(switchOf(tester).value, isTrue);
    });

    testWidgets('shows a Book already kept out as off', (tester) async {
      await store.setBookInTimeline(book.id, inTimeline: false);
      await openInfo(tester);

      expect(switchOf(tester).value, isFalse);
      expect(
        find.text('Entry Book ini tidak muncul di Linimasa'),
        findsOneWidget,
      );
    });

    testWidgets('the Book itself still shows its Entries', (tester) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await store.setBookInTimeline(book.id, inTimeline: false);
      await openBook(tester);

      expect(find.text('Satu.'), findsOneWidget);
    });
  });

  group('rename', () {
    Future<void> openRename(WidgetTester tester) async {
      await openInfo(tester);
      await chooseInMenu(tester, 'Ubah nama');
      expect(find.byType(RenameBookScreen), findsOneWidget);
    }

    Finder checkFab() => find.byTooltip('Simpan nama');

    testWidgets('the page has the title and the current name', (tester) async {
      await openRename(tester);

      expect(find.widgetWithText(AppBar, 'Ubah nama Book'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Nama Book'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Buku Saya'), findsOneWidget);
    });

    testWidgets('saves a trimmed name and goes back to Book info', (
      tester,
    ) async {
      await openRename(tester);

      await tester.enterText(find.byType(TextField), '  Buku Harian  ');
      await tapAndSettle(tester, checkFab());

      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Buku Harian'), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Kembali'));
      expect(find.widgetWithText(AppBar, 'Buku Harian'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Kembali'));
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('Buku Harian'), findsOneWidget);
    });

    testWidgets('an empty name is refused', (tester) async {
      await openRename(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tapAndSettle(tester, checkFab());

      expect(find.text('Isi nama Book dulu.'), findsOneWidget);
      expect(find.byType(RenameBookScreen), findsOneWidget);
    });

    testWidgets('Back keeps the old name', (tester) async {
      await openRename(tester);

      await tester.enterText(find.byType(TextField), 'Buku Harian');
      await tapAndSettle(tester, find.byTooltip('Kembali'));

      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Buku Saya'), findsOneWidget);
    });
  });

  group('description', () {
    Future<void> openDescription(WidgetTester tester) async {
      await openInfo(tester);
      await chooseInMenu(tester, 'Ubah deskripsi');
      expect(find.byType(BookDescriptionScreen), findsOneWidget);
    }

    Finder checkFab() => find.byTooltip('Simpan deskripsi');

    testWidgets('the page has the title and the current Description', (
      tester,
    ) async {
      await store.setBookDescription(book.id, 'Catatan harian.');
      await openDescription(tester);

      expect(find.widgetWithText(AppBar, 'Ubah deskripsi'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Deskripsi'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Catatan harian.'), findsOneWidget);
    });

    testWidgets('saves a trimmed Description with line breaks', (tester) async {
      await openDescription(tester);

      await tester.enterText(
        find.byType(TextField),
        '  Catatan harian.\nSejak 2024.\n',
      );
      await tapAndSettle(tester, checkFab());

      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Catatan harian.\nSejak 2024.'), findsOneWidget);
      final saved = await store.watchBook(book.id).first;
      expect(saved!.description, 'Catatan harian.\nSejak 2024.');
    });

    testWidgets('emptying it removes it', (tester) async {
      await store.setBookDescription(book.id, 'Catatan harian.');
      await openDescription(tester);

      await tester.enterText(find.byType(TextField), '  ');
      await tapAndSettle(tester, checkFab());

      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Tambah deskripsi'), findsOneWidget);
      expect((await store.watchBook(book.id).first)!.description, '');
    });

    testWidgets('holds at most 300 characters, counted near the limit', (
      tester,
    ) async {
      await openDescription(tester);
      final field = find.byType(TextField);

      await tester.enterText(field, 'a' * 249);
      await tester.pump();
      expect(find.textContaining('/300'), findsNothing);

      await tester.enterText(field, 'a' * 250);
      await tester.pump();
      expect(find.text('250/300'), findsOneWidget);

      await tester.enterText(field, 'a' * 320);
      await tester.pump();
      expect(find.text('300/300'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text.length, 300);
    });

    testWidgets('creating a Book asks only for its name', (tester) async {
      await openBook(tester);
      await tapAndSettle(tester, find.byTooltip('Kembali'));
      await tapAndSettle(tester, find.text('Book baru'));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Nama Book'), findsOneWidget);
    });
  });

  group('delete', () {
    Future<void> askDelete(WidgetTester tester, {Locale? locale}) async {
      final english = locale?.languageCode == 'en';
      await openInfo(tester, locale: locale ?? const Locale('id'));
      await tapAndSettle(
        tester,
        find.text(english ? 'Delete Book' : 'Hapus Book'),
      );
    }

    testWidgets('Hapus Book is a row in red, icon and text', (tester) async {
      await openInfo(tester);

      final scheme = Theme.of(tester.element(find.byType(BookInfoScreen)))
          .colorScheme;
      final row = find.widgetWithText(ListTile, 'Hapus Book');
      final icon = find.descendant(of: row, matching: find.byType(KIcon));
      expect(tester.widget<KIcon>(icon).icon, KIcons.bin);
      expect(IconTheme.of(tester.element(icon)).color, scheme.error);
      expect(
        DefaultTextStyle.of(tester.element(find.text('Hapus Book')))
            .style
            .color,
        scheme.error,
      );
    });

    testWidgets('asks with the Book name and the entry count', (tester) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await write('Dua.', DateTime(2026, 11, 15));

      await askDelete(tester);

      expect(find.text('Hapus Book?'), findsOneWidget);
      expect(
        find.text(
          '“Buku Saya” dan 2 Entry di dalamnya akan hilang selamanya. '
          'Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty Book has no count', (tester) async {
      await askDelete(tester);

      expect(
        find.text(
          '“Buku Saya” akan hilang selamanya. Ini tidak bisa dibatalkan.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('counts in English too', (tester) async {
      await write('One.', DateTime(2026, 11, 16));

      await askDelete(tester, locale: const Locale('en'));

      expect(
        find.text(
          '“Buku Saya” and the Entry in it will be gone forever. '
          "This can't be undone.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('Cancel keeps the Book', (tester) async {
      await askDelete(tester);

      await tapAndSettle(tester, find.text('Batal'));

      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Buku Saya'), findsOneWidget);
    });

    testWidgets('deleting the last Book leads to the empty Book list', (
      tester,
    ) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await askDelete(tester);

      await tapAndSettle(tester, find.text('Ya, hapus'));

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('Belum ada Book'), findsOneWidget);
    });

    testWidgets('other Books stay', (tester) async {
      await store.createBook('Resep Keluarga');
      await askDelete(tester);

      await tapAndSettle(tester, find.text('Ya, hapus'));

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('Resep Keluarga'), findsOneWidget);
      expect(find.text('Buku Saya'), findsNothing);
    });
  });
}
