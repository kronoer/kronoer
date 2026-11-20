import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:kronoer/src/welcome/welcome_screen.dart';
import 'package:material_ui/material_ui.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  final now = DateTime(2026, 11, 19, 14, 32);
  late InMemoryStore store;

  setUp(() => store = InMemoryStore(clock: () => now));
  tearDown(() => store.dispose());

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester, {bool started = true}) async {
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => now),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(started)),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the editor for a new Entry in [book].
  Future<void> writeIn(WidgetTester tester, Book book) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text(book.name));
    await tapAndSettle(tester, find.byType(FloatingActionButton));
    expect(find.byType(EntryEditorScreen), findsOneWidget);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
  }

  Future<List<String>> textsIn(Book book) async => [
    for (final entry in await store.watchEntries(book.id).first) entry.text,
  ];

  group('first launch', () {
    testWidgets('Welcome creates "Buku Saya" and opens its first Entry', (
      tester,
    ) async {
      await pumpApp(tester, started: false);
      expect(find.byType(WelcomeScreen), findsOneWidget);

      await tapAndSettle(tester, find.text('Yuk, mulai cerita'));

      final books = await store.watchBooks().first;
      expect(books.map((b) => b.name), ['Buku Saya']);
      expect(find.byType(WelcomeScreen), findsNothing);
      final editor = tester.widget<EntryEditorScreen>(
        find.byType(EntryEditorScreen),
      );
      expect(editor.bookId, books.single.id);
      expect(editor.entryId, isNull);
      expect(
        find.text('Tulis apa saja. Hanya kamu yang bisa membacanya.'),
        findsOneWidget,
      );
      expect(find.text('Buku Saya'), findsOneWidget);
    });

    testWidgets('"My Book" on an English device', (tester) async {
      await pumpApp(tester, started: false);
      tester.platformDispatcher.localesTestValue = [const Locale('en')];
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text("Let's start writing"));

      final books = await store.watchBooks().first;
      expect(books.single.name, 'My Book');
    });

    testWidgets('the editor has no "Terenkripsi" label', (tester) async {
      await pumpApp(tester, started: false);
      await tapAndSettle(tester, find.text('Yuk, mulai cerita'));

      expect(find.textContaining('enkripsi'), findsNothing);
    });

    testWidgets('the first Entry is saved as it is typed', (tester) async {
      await pumpApp(tester, started: false);
      await tapAndSettle(tester, find.text('Yuk, mulai cerita'));

      await type(tester, 'Hari pertama.');

      final book = (await store.watchBooks().first).single;
      expect(await textsIn(book), ['Hari pertama.']);
    });
  });

  group('editor', () {
    late Book book;
    setUp(() async => book = await store.createBook('Buku Saya'));

    testWidgets('turns off personalized learning for the text', (tester) async {
      await writeIn(tester, book);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enableIMEPersonalizedLearning, isFalse);
    });

    testWidgets('the page has no box around it', (tester) async {
      await writeIn(tester, book);

      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;
      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
    });

    testWidgets('autosaves while typing, then shows "Tersimpan"', (
      tester,
    ) async {
      await writeIn(tester, book);
      expect(find.text('Tersimpan'), findsNothing);

      await type(tester, 'Pagi ini hujan.');
      expect(await textsIn(book), ['Pagi ini hujan.']);
      expect(find.text('Tersimpan'), findsOneWidget);

      await type(tester, 'Pagi ini hujan turun pelan.');
      expect(await textsIn(book), ['Pagi ini hujan turun pelan.']);
    });

    testWidgets('back leaves without a dialog and keeps the Entry', (
      tester,
    ) async {
      await writeIn(tester, book);
      await tester.enterText(find.byType(TextField), 'Belum sempat jeda.');

      await tester.tap(_kIcon(KIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BookScreen), findsOneWidget);
      expect(await textsIn(book), ['Belum sempat jeda.']);
    });

    testWidgets('"Selesai" opens the saved Entry', (tester) async {
      await writeIn(tester, book);
      await type(tester, 'Pagi ini hujan.');

      await tapAndSettle(tester, find.text('Selesai'));

      expect(find.byType(EntryReadScreen), findsOneWidget);
      expect(find.text('Pagi ini hujan.'), findsOneWidget);
    });

    testWidgets('an empty new Entry is discarded', (tester) async {
      await writeIn(tester, book);

      await tester.tap(_kIcon(KIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(BookScreen), findsOneWidget);
      expect(await textsIn(book), isEmpty);
    });

    testWidgets('an Entry emptied before leaving is discarded', (tester) async {
      await writeIn(tester, book);
      await type(tester, 'Salah tulis.');
      expect(await textsIn(book), hasLength(1));

      await type(tester, '   ');
      await tapAndSettle(tester, find.text('Selesai'));

      expect(find.byType(BookScreen), findsOneWidget);
      expect(await textsIn(book), isEmpty);
    });

    testWidgets('edits an existing Entry', (tester) async {
      await store.createEntry(bookId: book.id, text: 'Lama.');
      await pumpApp(tester);
      await tapAndSettle(tester, find.text(book.name));
      await tapAndSettle(tester, find.text('Lama.'));
      await tapAndSettle(tester, _kIcon(KIcons.pen));

      await type(tester, 'Baru.');
      await tapAndSettle(tester, find.text('Selesai'));

      expect(find.byType(EntryReadScreen), findsOneWidget);
      expect(find.text('Baru.'), findsOneWidget);
      expect(await textsIn(book), ['Baru.']);
    });

    testWidgets('images can be taken out', (tester) async {
      await store.createEntry(
        bookId: book.id,
        text: 'Dua foto.',
        imageIds: ['a', 'b'],
      );
      await pumpApp(tester);
      await tapAndSettle(tester, find.text(book.name));
      await tapAndSettle(tester, find.text('Dua foto.'));
      await tapAndSettle(tester, _kIcon(KIcons.pen));
      expect(find.byType(EntryImage), findsNWidgets(2));
      expect(find.text('2/20'), findsOneWidget);

      await tapAndSettle(tester, find.bySemanticsLabel('Hapus foto').first);
      await tester.pump(autosaveDelay);
      await tester.pumpAndSettle();

      expect(find.byType(EntryImage), findsOneWidget);
      final entry = (await store.watchEntries(book.id).first).single;
      expect(entry.imageIds, ['b']);
    });

    testWidgets('"Selipkan foto" opens Galeri and Kamera', (tester) async {
      await writeIn(tester, book);

      await tapAndSettle(tester, find.text('Selipkan foto'));
      expect(find.text('Galeri'), findsOneWidget);
      expect(find.text('Kamera'), findsOneWidget);

      await tapAndSettle(tester, find.text('Kamera'));
      expect(find.text('Galeri'), findsNothing);
    });

    testWidgets('⋮ deletes the Entry with undo', (tester) async {
      await writeIn(tester, book);
      await type(tester, 'Hapus aku.');

      await tapAndSettle(tester, _kIcon(KIcons.moreVertical));
      await tapAndSettle(tester, find.text('Hapus Entry'));

      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.text('Entry dihapus'), findsOneWidget);
      expect(find.text('Hapus aku.'), findsNothing);

      await tapAndSettle(tester, find.text('Urungkan'));
      expect(find.text('Hapus aku.'), findsOneWidget);
    });
  });

  group('entry date', () {
    late Book book;
    setUp(() async => book = await store.createBook('Buku Saya'));

    testWidgets('the chip shows the date and time', (tester) async {
      await writeIn(tester, book);
      expect(find.text('Kamis, 19 Nov 2026 · 14.32'), findsOneWidget);
    });

    testWidgets('the pickers ask "Kapan ini terjadi?"', (tester) async {
      await writeIn(tester, book);

      await tapAndSettle(tester, _kIcon(KIcons.calendar));
      expect(find.text('Kapan ini terjadi?'), findsOneWidget);

      await tapAndSettle(tester, find.text('17'));
      await tapAndSettle(tester, find.text('OKE'));
      expect(find.text('Kapan ini terjadi?'), findsOneWidget);

      await tapAndSettle(tester, find.text('OKE'));
      expect(find.text('Selasa, 17 Nov 2026 · 14.32'), findsOneWidget);
    });

    testWidgets('future days cannot be picked', (tester) async {
      await writeIn(tester, book);
      await tapAndSettle(tester, _kIcon(KIcons.calendar));

      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.lastDate, DateUtils.dateOnly(now));

      await tapAndSettle(tester, find.text('25'));
      await tapAndSettle(tester, find.text('OKE'));
      await tapAndSettle(tester, find.text('OKE'));

      expect(find.text('Kamis, 19 Nov 2026 · 14.32'), findsOneWidget);
    });

    testWidgets('the picked date is saved', (tester) async {
      await writeIn(tester, book);
      await type(tester, 'Kemarin lusa.');

      await tapAndSettle(tester, _kIcon(KIcons.calendar));
      await tapAndSettle(tester, find.text('17'));
      await tapAndSettle(tester, find.text('OKE'));
      await tapAndSettle(tester, find.text('OKE'));
      await tester.pump(autosaveDelay);
      await tester.pumpAndSettle();

      final entry = (await store.watchEntries(book.id).first).single;
      expect(entry.dateTime, DateTime(2026, 11, 17, 14, 32));
    });
  });
}
