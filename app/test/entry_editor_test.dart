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
import 'package:kronoer/src/theme/colors.dart';
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
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
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
    testWidgets('Welcome creates "My Book" and opens its first Entry', (
      tester,
    ) async {
      await pumpApp(tester, started: false);
      expect(find.byType(WelcomeScreen), findsOneWidget);

      await tapAndSettle(tester, find.text('Let\'s start writing'));

      final books = await store.watchBooks().first;
      expect(books.map((b) => b.name), ['My Book']);
      expect(find.byType(WelcomeScreen), findsNothing);
      final editor = tester.widget<EntryEditorScreen>(
        find.byType(EntryEditorScreen),
      );
      expect(editor.bookId, books.single.id);
      expect(editor.entryId, isNull);
      expect(
        find.text('Write anything. Only you can read it.'),
        findsOneWidget,
      );
      expect(find.text('My Book'), findsOneWidget);
    });

    testWidgets('"Buku Saya" on an Indonesian device', (tester) async {
      await pumpApp(tester, started: false);
      tester.platformDispatcher.localesTestValue = [const Locale('id')];
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text('Yuk, mulai cerita'));

      final books = await store.watchBooks().first;
      expect(books.single.name, 'Buku Saya');
    });

    testWidgets('the editor has no "Terenkripsi" label', (tester) async {
      await pumpApp(tester, started: false);
      await tapAndSettle(tester, find.text('Let\'s start writing'));

      expect(find.textContaining('enkripsi'), findsNothing);
    });

    testWidgets('the first Entry is saved as it is typed', (tester) async {
      await pumpApp(tester, started: false);
      await tapAndSettle(tester, find.text('Let\'s start writing'));

      await type(tester, 'Hari pertama.');

      final book = (await store.watchBooks().first).single;
      expect(await textsIn(book), ['Hari pertama.']);
    });
  });

  group('editor', () {
    late Book book;
    setUp(() async => book = await store.createBook('My Book'));

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

    for (final (brightness, scheme, alpha) in [
      (Brightness.light, lightColorScheme, 0.07),
      (Brightness.dark, darkColorScheme, 0.08),
    ]) {
      testWidgets(
        'the bottom bar blends into the screen (${brightness.name})',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await writeIn(tester, book);

          final bar = tester.widget<DecoratedBox>(
            find.ancestor(
              of: find.text('Add a photo'),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).border != null,
              ),
            ),
          );
          final decoration = bar.decoration as BoxDecoration;
          expect(decoration.color, scheme.surface);
          expect(
            (decoration.border! as Border).top,
            BorderSide(color: scheme.onSurface.withValues(alpha: alpha)),
          );
        },
      );
    }

    testWidgets('autosaves while typing, then shows "Saved"', (tester) async {
      await writeIn(tester, book);
      expect(find.text('Saved'), findsNothing);

      await type(tester, 'Pagi ini hujan.');
      expect(await textsIn(book), ['Pagi ini hujan.']);
      expect(find.text('Saved'), findsOneWidget);

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

    testWidgets('"Done" opens the saved Entry', (tester) async {
      await writeIn(tester, book);
      await type(tester, 'Pagi ini hujan.');

      await tapAndSettle(tester, find.text('Done'));

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
      await tapAndSettle(tester, find.text('Done'));

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
      await tapAndSettle(tester, find.text('Done'));

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

      await tapAndSettle(tester, find.bySemanticsLabel('Remove photo').first);
      await tester.pump(autosaveDelay);
      await tester.pumpAndSettle();

      expect(find.byType(EntryImage), findsOneWidget);
      final entry = (await store.watchEntries(book.id).first).single;
      expect(entry.imageIds, ['b']);
    });

    testWidgets('"Add a photo" opens Gallery and Camera', (tester) async {
      await writeIn(tester, book);

      await tapAndSettle(tester, find.text('Add a photo'));
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);

      // The camera never answers here, and the editor waits for it with a
      // spinner, so this does not settle.
      await tester.tap(find.text('Camera'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Gallery'), findsNothing);
    });

    testWidgets('⋮ deletes the Entry with undo', (tester) async {
      await writeIn(tester, book);
      await type(tester, 'Hapus aku.');

      await tapAndSettle(tester, _kIcon(KIcons.moreVertical));
      await tapAndSettle(tester, find.text('Delete Entry'));

      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.text('Entry moved to the Trash'), findsOneWidget);
      expect(find.text('Hapus aku.'), findsNothing);

      await tapAndSettle(tester, find.text('Undo'));
      expect(find.text('Hapus aku.'), findsOneWidget);
    });
  });

  group('entry date', () {
    late Book book;
    setUp(() async => book = await store.createBook('My Book'));

    testWidgets('the chip shows the date and time', (tester) async {
      await writeIn(tester, book);
      expect(find.text('Thursday, 19 Nov 2026 · 14:32'), findsOneWidget);
    });

    testWidgets('the pickers ask "When did this happen?"', (tester) async {
      await writeIn(tester, book);

      await tapAndSettle(tester, _kIcon(KIcons.calendar));
      expect(find.text('When did this happen?'), findsOneWidget);

      await tapAndSettle(tester, find.text('17'));
      await tapAndSettle(tester, find.text('OK'));
      expect(find.text('When did this happen?'), findsOneWidget);

      await tapAndSettle(tester, find.text('OK'));
      expect(find.text('Tuesday, 17 Nov 2026 · 14:32'), findsOneWidget);
    });

    testWidgets('future days cannot be picked', (tester) async {
      await writeIn(tester, book);
      await tapAndSettle(tester, _kIcon(KIcons.calendar));

      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.lastDate, DateUtils.dateOnly(now));

      await tapAndSettle(tester, find.text('25'));
      await tapAndSettle(tester, find.text('OK'));
      await tapAndSettle(tester, find.text('OK'));

      expect(find.text('Thursday, 19 Nov 2026 · 14:32'), findsOneWidget);
    });

    testWidgets('the picked date is saved', (tester) async {
      await writeIn(tester, book);
      await type(tester, 'Kemarin lusa.');

      await tapAndSettle(tester, _kIcon(KIcons.calendar));
      await tapAndSettle(tester, find.text('17'));
      await tapAndSettle(tester, find.text('OK'));
      await tapAndSettle(tester, find.text('OK'));
      await tester.pump(autosaveDelay);
      await tester.pumpAndSettle();

      final entry = (await store.watchEntries(book.id).first).single;
      expect(entry.dateTime, DateTime(2026, 11, 17, 14, 32));
    });
  });

  group('word count', () {
    late Book book;
    setUp(() async => book = await store.createBook('My Book'));

    Finder wordCount() =>
        find.textContaining(RegExp(r'^[\d.,]+ (kata|words?)$'));

    testWidgets('is hidden while the text is empty, and counts as you type', (
      tester,
    ) async {
      await writeIn(tester, book);
      expect(wordCount(), findsNothing);

      await tester.enterText(find.byType(TextField), 'Pagi');
      await tester.pump();
      expect(find.text('1 word'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Pagi ini hujan.');
      await tester.pump();
      expect(find.text('3 words'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(wordCount(), findsNothing);
    });

    testWidgets('counts like the Book insight: marks are not words', (
      tester,
    ) async {
      await writeIn(tester, book);
      await type(
        tester,
        '> kutipan pendek\n1. satu\n12. dua belas\n- *tebal* _miring_\n* ~',
      );
      // The words: kutipan pendek, satu, dua belas, tebal, miring.
      expect(find.text('7 words'), findsOneWidget);
      final insight = await store.watchBookInsight(book.id).first;
      expect(insight.wordCount, 7);
    });

    testWidgets('sits before Saved, and groups as the language does', (
      tester,
    ) async {
      await writeIn(tester, book);
      await type(tester, List.filled(1234, 'kata').join(' '));

      expect(find.text('1,234 words'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('1,234 words')).dx,
        lessThan(tester.getTopLeft(find.text('Saved')).dx),
      );
    });

    testWidgets('one word and many in Indonesian', (tester) async {
      await writeIn(tester, book);
      tester.platformDispatcher.localesTestValue = [const Locale('id')];
      await tester.pumpAndSettle();

      await type(tester, 'Hujan');
      expect(find.text('1 kata'), findsOneWidget);
      await type(tester, List.filled(1234, 'hujan').join(' '));
      expect(find.text('1.234 kata'), findsOneWidget);
    });

    testWidgets('a narrow bar keeps the counts whole and only the ✓ of '
        'Saved', (tester) async {
      // The test font draws every letter a full em wide: at this width
      // "1,234 words · ✓" fits beside Add a photo, "Saved" does not.
      await tester.binding.setSurfaceSize(const Size(480, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await writeIn(tester, book);
      await type(tester, List.filled(1234, 'kata').join(' '));

      expect(find.text('1,234 words'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.bySemanticsLabel('Saved'), findsOneWidget);
      expect(_kIcon(KIcons.check), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
