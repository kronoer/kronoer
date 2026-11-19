import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/books/book_name_screen.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/card.dart';
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

    testWidgets('the preview is one paragraph of at most 2 lines', (
      tester,
    ) async {
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
      expect(preview.maxLines, 2);
    });

    testWidgets('a Book without Entries shows no preview', (tester) async {
      await store.createBook('Buku Kosong');

      await pumpBookList(tester);

      final card = find.byType(KCard);
      final texts = find.descendant(of: card, matching: find.byType(Text));
      // Name and time only.
      expect(texts, findsNWidgets(2));
    });

    testWidgets('shows no entry count', (tester) async {
      final book = await store.createBook('Buku Saya');
      await store.createEntry(bookId: book.id, text: 'Satu.');
      await store.createEntry(bookId: book.id, text: 'Dua.');

      await pumpBookList(tester);

      final card = find.byType(KCard);
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

  group('app bar', () {
    testWidgets('shows the wordmark and a gear that opens Settings', (
      tester,
    ) async {
      await pumpBookList(tester);

      expect(find.bySemanticsLabel('Kronoer'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Pengaturan'));
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
      expect(find.byType(KCard), findsNothing);
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
