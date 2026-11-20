import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
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

  group('rename', () {
    Future<void> openRename(WidgetTester tester) async {
      await openBook(tester);
      await tapAndSettle(tester, find.byTooltip('Menu Book'));
      await tapAndSettle(tester, find.text('Ganti nama'));
      expect(find.byType(RenameBookScreen), findsOneWidget);
    }

    Finder checkFab() => find.byTooltip('Simpan nama');

    testWidgets('the page has the title and the current name', (tester) async {
      await openRename(tester);

      expect(find.widgetWithText(AppBar, 'Ganti nama Book'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Nama Book'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Buku Saya'), findsOneWidget);
    });

    testWidgets('saves a trimmed name and goes back to the Book', (
      tester,
    ) async {
      await openRename(tester);

      await tester.enterText(find.byType(TextField), '  Buku Harian  ');
      await tapAndSettle(tester, checkFab());

      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Buku Harian'), findsOneWidget);

      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
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
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Buku Saya'), findsOneWidget);
    });
  });

  group('delete', () {
    Future<void> askDelete(WidgetTester tester, {Locale? locale}) async {
      final english = locale?.languageCode == 'en';
      await openBook(tester, locale: locale ?? const Locale('id'));
      await tapAndSettle(
        tester,
        find.byTooltip(english ? 'Book menu' : 'Menu Book'),
      );
      await tapAndSettle(
        tester,
        find.text(english ? 'Delete Book' : 'Hapus Book'),
      );
    }

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

      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Buku Saya'), findsOneWidget);
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
