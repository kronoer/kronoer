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
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
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

  /// Opens [book] and then its Book info, from the ⓘ button.
  Future<void> openInfo(
    WidgetTester tester, {
    Locale locale = const Locale('id'),
  }) async {
    await openBook(tester, locale: locale);
    await tapAndSettle(
      tester,
      find.byTooltip(locale.languageCode == 'en' ? 'Book info' : 'Info Book'),
    );
    expect(find.byType(BookInfoScreen), findsOneWidget);
  }

  Future<void> chooseInMenu(WidgetTester tester, String item) async {
    await tapAndSettle(tester, find.byTooltip('Menu Book'));
    await tapAndSettle(tester, find.text(item));
  }

  group('top bar', () {
    testWidgets('has back, the name, search, and ⓘ, but no ⋮', (tester) async {
      await write('Satu.', DateTime(2026, 11, 16));
      await openBook(tester);

      expect(find.byTooltip('Kembali'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Buku Saya'), findsOneWidget);
      expect(find.byTooltip('Cari di Buku Saya'), findsOneWidget);
      expect(find.byTooltip('Info Book'), findsOneWidget);
      expect(find.byTooltip('Menu Book'), findsNothing);
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

    testWidgets('the menu has Ubah nama, Ubah deskripsi, Hapus Book last', (
      tester,
    ) async {
      await openInfo(tester);

      await tapAndSettle(tester, find.byTooltip('Menu Book'));

      final items = tester
          .widgetList<MenuItemButton>(find.byType(MenuItemButton))
          .toList();
      expect(
        [for (final item in items) (item.child! as Text).data],
        ['Ubah nama', 'Ubah deskripsi', 'Hapus Book'],
      );
      expect([for (final item in items) item.leadingIcon], [null, null, null]);
    });

    testWidgets('is in English on an English device', (tester) async {
      await openInfo(tester, locale: const Locale('en'));

      expect(find.text('Add description'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Book menu'));
      expect(find.text('Edit name'), findsOneWidget);
      expect(find.text('Edit description'), findsOneWidget);
      expect(find.text('Delete Book'), findsOneWidget);
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
        find.byTooltip(english ? 'Book menu' : 'Menu Book'),
      );
      await tapAndSettle(
        tester,
        find.text(english ? 'Delete Book' : 'Hapus Book'),
      );
    }

    testWidgets('Hapus Book is red', (tester) async {
      await openInfo(tester);
      await tapAndSettle(tester, find.byTooltip('Menu Book'));

      final scheme = Theme.of(tester.element(find.byType(BookInfoScreen)))
          .colorScheme;
      final style = tester
          .widget<MenuItemButton>(
            find.widgetWithText(MenuItemButton, 'Hapus Book'),
          )
          .style!;
      expect(style.foregroundColor!.resolve({}), scheme.error);
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
