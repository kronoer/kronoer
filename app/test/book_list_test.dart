import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_fab.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/books/book_name_screen.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  late DateTime now;
  late InMemoryStore store;

  setUp(() {
    now = DateTime(2026, 11, 19, 14, 32);
    store = InMemoryStore(clock: () => now);
  });
  tearDown(() => store.dispose());

  void later([Duration by = const Duration(minutes: 1)]) => now = now.add(by);

  Future<void> pumpBookList(
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
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  /// The icons in the Book rows' preview lines, and whether each is filled.
  List<(KIcons, bool)> icons(WidgetTester tester) {
    Iterable<KIcon> iconsIn(Finder of) => tester.widgetList<KIcon>(
      find.descendant(of: of, matching: find.byType(KIcon)),
    );
    final onTiles = iconsIn(find.byType(CoverThumbnail)).toSet();
    return [
      for (final icon in iconsIn(find.byType(BookRow)))
        if (!onTiles.contains(icon)) (icon.icon, icon.filled),
    ];
  }

  group('order', () {
    testWidgets('by the last written Entry, not by entry date', (tester) async {
      final a = await store.createBook('Buku A');
      later();
      await store.createBook('Buku B');
      later();
      // Written last, but dated long ago.
      await store.createEntry(
        bookId: a.id,
        text: 'Pagi ini hujan.',
        dateTime: DateTime(2020),
      );

      await pumpBookList(tester);

      expect(top(tester, 'Buku A'), lessThan(top(tester, 'Buku B')));
    });

    testWidgets('an edit moves the Book to the top', (tester) async {
      final a = await store.createBook('Buku A');
      final entry = await store.createEntry(bookId: a.id, text: 'Lama.');
      later();
      await store.createBook('Buku B');
      later();
      await store.updateEntry(entry.copyWith(text: 'Baru diedit.'));

      await pumpBookList(tester);

      expect(top(tester, 'Buku A'), lessThan(top(tester, 'Buku B')));
      expect(find.text('Baru diedit.'), findsOneWidget);
    });

    testWidgets('a renamed Book keeps its place', (tester) async {
      final a = await store.createBook('Buku A');
      later();
      await store.createBook('Buku B');
      later();
      await store.renameBook(a.id, 'Buku A2');

      await pumpBookList(tester);

      expect(top(tester, 'Buku B'), lessThan(top(tester, 'Buku A2')));
    });
  });

  group('card', () {
    testWidgets('shows the name, the last Entry, and its time', (tester) async {
      final book = await store.createBook('Buku Saya');
      await store.createEntry(bookId: book.id, text: 'Entry pertama.');
      later();
      await store.createEntry(bookId: book.id, text: 'Pagi ini hujan.');

      await pumpBookList(tester);

      expect(find.text('Buku Saya'), findsOneWidget);
      expect(find.text('Pagi ini hujan.'), findsOneWidget);
      expect(find.text('Entry pertama.'), findsNothing);
      expect(find.text('14.33'), findsOneWidget);
    });

    testWidgets('older activity shows the date', (tester) async {
      await store.createBook('Buku A');
      later(const Duration(days: 1));
      await store.createBook('Buku B');
      now = DateTime(2026, 12, 5, 9);

      await pumpBookList(tester);

      expect(find.text('19 Nov'), findsOneWidget);
      expect(find.text('20 Nov'), findsOneWidget);
    });

    testWidgets('yesterday reads "Kemarin"', (tester) async {
      await store.createBook('Buku Saya');
      later(const Duration(days: 1));

      await pumpBookList(tester);

      expect(find.text('Kemarin'), findsOneWidget);
    });

    testWidgets('the preview is one paragraph on 1 line', (tester) async {
      final book = await store.createBook('Buku Saya');
      await store.createEntry(
        bookId: book.id,
        text: 'Paragraf satu.\n\nParagraf dua.',
      );

      await pumpBookList(tester);

      expect(find.text('Paragraf satu. Paragraf dua.'), findsOneWidget);
      final preview = tester.widget<Text>(
        find.text('Paragraf satu. Paragraf dua.'),
      );
      expect(preview.maxLines, 1);
      expect(preview.overflow, TextOverflow.ellipsis);
      expect(icons(tester), isEmpty);
    });

    testWidgets('Images and text show the count, then the text', (
      tester,
    ) async {
      final book = await store.createBook('Jurnal');
      await store.createEntry(
        bookId: book.id,
        text: 'Hari ketiga.',
        imageIds: ['a', 'b', 'c'],
      );

      await pumpBookList(tester);

      final line = find.textContaining('3 foto · Hari ketiga.');
      expect(line, findsOneWidget);
      expect(tester.widget<Text>(line).maxLines, 1);
      expect(icons(tester), [(KIcons.image, true)]);
    });

    testWidgets('one Image and no text shows "Foto"', (tester) async {
      final book = await store.createBook('Foto');
      await store.createEntry(bookId: book.id, text: '', imageIds: ['a']);

      await pumpBookList(tester);

      final card = find.byType(BookRow);
      expect(
        find.descendant(of: card, matching: find.textContaining('Foto')),
        findsNWidgets(2),
      );
      expect(find.textContaining('·'), findsNothing);
      expect(icons(tester), [(KIcons.image, true)]);
    });

    testWidgets('Images and no text show how many', (tester) async {
      final book = await store.createBook('Buku Saya');
      await store.createEntry(bookId: book.id, text: ' ', imageIds: ['a', 'b']);

      await pumpBookList(tester);

      expect(find.textContaining('2 foto'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('a Book without Entries says so, with a pen', (tester) async {
      await store.createBook('Buku Kosong');

      await pumpBookList(tester);

      expect(find.textContaining('Belum ada Entry'), findsOneWidget);
      expect(icons(tester), [(KIcons.pen, true)]);
    });

    testWidgets('the Image count is in English on an English device', (
      tester,
    ) async {
      final one = await store.createBook('One');
      await store.createEntry(bookId: one.id, text: '', imageIds: ['a']);
      final three = await store.createBook('Three');
      await store.createEntry(
        bookId: three.id,
        text: 'Text.',
        imageIds: ['b', 'c', 'd'],
      );
      await store.createBook('Empty');

      await pumpBookList(tester, locale: const Locale('en'));

      expect(find.textContaining('Photo'), findsOneWidget);
      expect(find.textContaining('3 photos · Text.'), findsOneWidget);
      expect(find.textContaining('No Entries yet'), findsOneWidget);
    });

    testWidgets('an Entry with only Images still shows the search field', (
      tester,
    ) async {
      final book = await store.createBook('Buku Saya');
      await store.createEntry(bookId: book.id, text: '', imageIds: ['a']);

      await pumpBookList(tester);

      expect(find.text('Cari di semua Book'), findsOneWidget);
    });

    testWidgets('shows no entry count', (tester) async {
      final book = await store.createBook('Buku Saya');
      await store.createEntry(bookId: book.id, text: 'Satu.');
      await store.createEntry(bookId: book.id, text: 'Dua.');

      await pumpBookList(tester);

      final card = find.byType(BookRow);
      final texts = find.descendant(of: card, matching: find.byType(Text));
      // Name, time, and preview only.
      expect(texts, findsNWidgets(3));
    });

    testWidgets('a tap opens the Book', (tester) async {
      await store.createBook('Buku Saya');
      await pumpBookList(tester);

      await tapAndSettle(tester, find.text('Buku Saya'));

      expect(find.byType(BookScreen), findsOneWidget);
    });
  });

  group('FAB', () {
    /// Pumps a route change frame by frame, failing on any overflow, and
    /// says whether the FAB flew. In flight it is clipped to its shape.
    Future<bool> flies(WidgetTester tester) async {
      var flew = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'frame $i');
        final inFlight = find.byKey(fabInFlightKey);
        if (inFlight.evaluate().isNotEmpty) {
          flew = true;
          expect(
            tester
                .widget<Material>(
                  find
                      .descendant(of: inFlight, matching: find.byType(Material))
                      .first,
                )
                .clipBehavior,
            Clip.antiAlias,
          );
        }
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return flew;
    }

    for (final (name, locale, textScale) in [
      ('in Indonesian', const Locale('id'), 1.0),
      ('in English with large text', const Locale('en'), 2.0),
    ]) {
      testWidgets('changes in place to and from a Book, $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await store.createBook('Buku Saya');
        await pumpBookList(tester, locale: locale);

        await tester.tap(find.text('Buku Saya'));
        expect(await flies(tester), isTrue);
        expect(find.byType(BookScreen), findsOneWidget);

        await tester.binding.handlePopRoute();
        expect(await flies(tester), isTrue);
        expect(find.byType(BookListScreen), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);
      });
    }
  });

  group('app bar', () {
    testWidgets('shows the wordmark and no gear: Settings is a tab', (
      tester,
    ) async {
      await pumpBookList(tester);

      expect(find.bySemanticsLabel('Kronoer'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );

      await tapAndSettle(tester, find.text('Pengaturan'));
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('empty state', () {
    testWidgets('shows the message and the New Book FAB', (tester) async {
      await pumpBookList(tester);

      expect(find.text('Belum ada Book'), findsOneWidget);
      expect(
        find.text('Bikin Book pertamamu, lalu mulai bercerita.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FloatingActionButton, 'Book baru'),
        findsOneWidget,
      );
      expect(find.byType(BookRow), findsNothing);
    });

    testWidgets('goes away once a Book exists', (tester) async {
      await pumpBookList(tester);
      await store.createBook('Buku Saya');
      await tester.pumpAndSettle();

      expect(find.text('Belum ada Book'), findsNothing);
      expect(find.text('Buku Saya'), findsOneWidget);
    });

    testWidgets('is in English on an English device', (tester) async {
      await pumpBookList(tester, locale: const Locale('en'));

      expect(find.text('No Books yet'), findsOneWidget);
      expect(find.text('New Book'), findsOneWidget);
    });
  });

  group('create', () {
    Future<void> openCreate(WidgetTester tester) async {
      await pumpBookList(tester);
      await tapAndSettle(tester, find.text('Book baru'));
      expect(find.byType(CreateBookScreen), findsOneWidget);
    }

    Finder checkFab() => find.byTooltip('Buat Book');

    testWidgets('the page has the title, the name field, and the check', (
      tester,
    ) async {
      await openCreate(tester);

      expect(find.widgetWithText(AppBar, 'Book baru'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Nama Book'), findsOneWidget);
      expect(checkFab(), findsOneWidget);
    });

    testWidgets('an empty or blank name is refused', (tester) async {
      await openCreate(tester);

      await tapAndSettle(tester, checkFab());
      expect(find.text('Isi nama Book dulu.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '   ');
      await tapAndSettle(tester, checkFab());
      expect(find.text('Isi nama Book dulu.'), findsOneWidget);

      expect(find.byType(CreateBookScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      expect(find.text('Belum ada Book'), findsOneWidget);
    });

    testWidgets('typing clears the error', (tester) async {
      await openCreate(tester);
      await tapAndSettle(tester, checkFab());

      await tester.enterText(find.byType(TextField), 'R');
      await tester.pump();

      expect(find.text('Isi nama Book dulu.'), findsNothing);
    });

    testWidgets('creates the Book with a trimmed name and opens it', (
      tester,
    ) async {
      await openCreate(tester);

      await tester.enterText(find.byType(TextField), '  Resep Keluarga  ');
      await tapAndSettle(tester, checkFab());

      expect(find.byType(BookScreen), findsOneWidget);
      // An exact match, so the spaces are gone.
      expect(find.widgetWithText(AppBar, 'Resep Keluarga'), findsOneWidget);
    });

    testWidgets('the keyboard Done key creates too', (tester) async {
      await openCreate(tester);

      await tester.enterText(find.byType(TextField), 'Resep Keluarga');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(BookScreen), findsOneWidget);
    });

    testWidgets('Back from the new Book skips the create page', (tester) async {
      await openCreate(tester);
      await tester.enterText(find.byType(TextField), 'Resep Keluarga');
      await tapAndSettle(tester, checkFab());

      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('Resep Keluarga'), findsOneWidget);
    });

    testWidgets('Back from the create page creates nothing', (tester) async {
      await openCreate(tester);
      await tester.enterText(find.byType(TextField), 'Resep Keluarga');

      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('Belum ada Book'), findsOneWidget);
    });
  });
}
