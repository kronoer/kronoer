import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/search/highlight.dart';
import 'package:kronoer/src/search/search.dart';
import 'package:kronoer/src/search/search_screen.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

import 'core_test_store.dart';
import 'text_weights.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

/// The text of every marked span under [of].
List<String> _marked(WidgetTester tester, Finder of) => [
  for (final rich in tester.widgetList<RichText>(
    find.descendant(of: of, matching: find.byType(RichText)),
  ))
    ..._markedIn(rich.text),
];

List<String> _markedIn(InlineSpan root) {
  final marked = <String>[];
  root.visitChildren((span) {
    if (span is TextSpan && span.style?.backgroundColor != null) {
      marked.add(span.text ?? '');
    }
    return true;
  });
  return marked;
}

SearchScreen _searchScreen(WidgetTester tester) =>
    tester.widget<SearchScreen>(find.byType(SearchScreen));

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  final today = DateTime(2026, 11, 19, 21);
  late TestStore store;
  late TestStore emptyStore;
  late Book garden;
  late Book trips;
  late Book rainy;

  /// The Book list's order, by name.
  late List<String> bookOrder;

  setUp(() async {
    store = await TestStore.open();
    final books = store.repository;

    garden = await books.createBook('Kebun');
    for (var i = 0; i < 5; i++) {
      await books.createEntry(
        bookId: garden.id,
        text: 'Hujan ke-$i turun di kebun.',
        dateTime: today.subtract(Duration(days: i + 1)),
      );
    }
    await books.createEntry(
      bookId: garden.id,
      text: [
        for (var i = 0; i < 30; i++) 'Paragraf $i tentang tanaman.',
        'Lalu muncul pelangi di atas pohon.',
      ].join('\n\n'),
      dateTime: today.subtract(const Duration(days: 10)),
    );

    // Later activity, so this Book comes first in the Book list although it
    // has fewer matches.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    trips = await books.createBook('Perjalanan');
    await books.createEntry(
      bookId: trips.id,
      text: 'Kehujanan di stasiun, lalu hujan reda.',
      dateTime: today.subtract(const Duration(days: 2, hours: 3)),
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    rainy = await books.createBook('Gerimis');
    for (var i = 0; i < 25; i++) {
      await books.createEntry(
        bookId: rainy.id,
        text: 'Gerimis nomor $i.',
        dateTime: today.subtract(Duration(hours: i + 1)),
      );
    }

    await books.createBook('Kosong');
    bookOrder = [for (final book in await store.store.listBooks()) book.name];

    emptyStore = await TestStore.open();
    await emptyStore.repository.createBook('Kosong');
  });

  tearDown(() async {
    await store.close();
    await emptyStore.close();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    TestStore? on,
    Locale locale = const Locale('id'),
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...(on ?? store).overrides,
          clockProvider.overrideWithValue(() => today),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
        ],
        child: const KronoerApp(),
      ),
    );
    await settleCore(tester);
  }

  /// Waits out a route change and the core calls it starts. A focused field
  /// keeps its cursor blinking, so this never waits to settle.
  Future<void> pumpRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await settleCore(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await pumpRoute(tester);
  }

  Future<void> back(WidgetTester tester) async {
    // The system back: the search field holds its own back button.
    await tester.binding.handlePopRoute();
    await pumpRoute(tester);
  }

  /// Types [query] and waits for the search.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(searchDelay);
    await settleCore(tester);
  }

  Future<void> openSearchAll(WidgetTester tester) async {
    await pumpApp(tester);
    await tap(tester, find.text('Cari di semua Book'));
    expect(find.byType(SearchScreen), findsOneWidget);
  }

  Future<void> openSearchIn(WidgetTester tester, Book book) async {
    await pumpApp(tester);
    await tap(tester, find.text(book.name));
    await tap(tester, _kIcon(KIcons.search));
    expect(_searchScreen(tester).bookId, book.id);
  }

  group('where search starts', () {
    testWidgets('the Book list has a search field once there is an Entry', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Cari di semua Book'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Cari di semua Book'),
        ),
        findsOneWidget,
        reason: 'fixed under the app bar, not in the list',
      );
    });

    testWidgets('no search field while there is no Entry at all', (
      tester,
    ) async {
      await pumpApp(tester, on: emptyStore);
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('Cari di semua Book'), findsNothing);
    });

    testWidgets('a Book shows the search icon only once it has an Entry', (
      tester,
    ) async {
      await pumpApp(tester);
      await tap(tester, find.text('Kosong'));
      expect(find.byType(BookScreen), findsOneWidget);
      expect(_kIcon(KIcons.search), findsNothing);

      await back(tester);
      await tap(tester, find.text('Kebun'));
      expect(_kIcon(KIcons.search), findsOneWidget);
    });
  });

  group('search in every Book', () {
    testWidgets(
      'starts focused, with a hint, and the keyboard does not learn',
      (tester) async {
        await openSearchAll(tester);

        expect(find.text('Cari kata di semua Entry.'), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.enableIMEPersonalizedLearning, isFalse);
        expect(field.focusNode!.hasFocus, isTrue);
      },
    );

    testWidgets('searches from 2 characters, once typing pauses', (
      tester,
    ) async {
      await openSearchAll(tester);

      await search(tester, 'h');
      expect(find.byType(KCard), findsNothing);
      expect(find.text('Cari kata di semua Entry.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hu');
      await tester.pump(searchDelay - const Duration(milliseconds: 50));
      await settleCore(tester);
      expect(find.byType(KCard), findsNothing, reason: 'still typing');

      await tester.pump(const Duration(milliseconds: 50));
      await settleCore(tester);
      expect(find.byType(KCard), findsWidgets);
    });

    testWidgets('groups results by Book in Book list order', (tester) async {
      await openSearchAll(tester);
      await search(tester, 'hujan');

      expect(find.text('6 Entry di 2 Book'), findsOneWidget);
      expect(find.text('5 Entry'), findsOneWidget);
      expect(find.text('1 Entry'), findsOneWidget);
      expect(find.byType(KCard), findsNWidgets(3 + 1));
      expect(find.text('Lihat 2 Entry lainnya'), findsOneWidget);

      final shown = [
        for (final name in ['Kebun', 'Perjalanan'])
          (name, tester.getTopLeft(find.text(name)).dy),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      expect(
        [for (final (name, _) in shown) name],
        [
          for (final name in bookOrder)
            if (name == 'Kebun' || name == 'Perjalanan') name,
        ],
      );
    });

    testWidgets('marks the matches in each snippet and hides the markers', (
      tester,
    ) async {
      await openSearchAll(tester);
      await search(tester, 'hujan');

      final marked = _marked(tester, find.byType(SearchScreen));
      expect(marked, containsAll(['Hujan', 'hujan']));
      expect(marked, isNot(contains('Kehujanan')), reason: 'not a prefix');
      expect(find.textContaining(matchStart), findsNothing);
      expect(find.textContaining(matchEnd), findsNothing);
    });

    testWidgets('"Lihat N Entry lainnya" searches that Book; back returns', (
      tester,
    ) async {
      await openSearchAll(tester);
      await search(tester, 'hujan');

      await tap(tester, find.text('Lihat 2 Entry lainnya'));
      expect(_searchScreen(tester).bookId, garden.id);
      expect(_fieldText(tester), 'hujan');
      expect(find.text('5 Entry di Kebun'), findsOneWidget);
      expect(find.byType(KCard), findsNWidgets(5));

      await back(tester);
      expect(_searchScreen(tester).bookId, isNull);
      expect(find.text('6 Entry di 2 Book'), findsOneWidget);
    });

    testWidgets('with no results, suggests the start of the word', (
      tester,
    ) async {
      await openSearchAll(tester);
      await search(tester, 'senja');

      expect(
        find.text('Tidak ada Entry yang cocok dengan “senja”'),
        findsOneWidget,
      );
      expect(
        find.text('Coba kata lain, atau awal katanya saja, misalnya “sen”.'),
        findsOneWidget,
      );
      expect(find.byType(KCard), findsNothing);
    });

    testWidgets('speaks English too', (tester) async {
      await pumpApp(tester, locale: const Locale('en'));
      await tap(tester, find.text('Search all Books'));
      expect(find.text('Search for words in every Entry.'), findsOneWidget);

      await search(tester, 'hujan');
      expect(find.text('6 Entries in 2 Books'), findsOneWidget);
      expect(find.text('See 2 more Entries'), findsOneWidget);
    });

    testWidgets('a result opens the Entry with every match marked', (
      tester,
    ) async {
      await openSearchAll(tester);
      await search(tester, 'hujan');

      await tap(tester, find.textContaining('stasiun'));
      final read = find.byType(EntryReadScreen);
      expect(tester.widget<EntryReadScreen>(read).query, 'hujan');
      expect(_marked(tester, read), ['hujan'], reason: 'not Kehujanan');

      await back(tester);
      expect(_fieldText(tester), 'hujan');
      expect(find.text('6 Entry di 2 Book'), findsOneWidget);
    });

    testWidgets('with Bold text, the marked snippet and Entry are bold', (
      tester,
    ) async {
      turnOnBoldText(tester);
      await openSearchAll(tester);
      await search(tester, 'hujan');

      final snippet = textWeights(tester, find.textContaining('stasiun'));
      expect(snippet, contains(('hujan', FontWeight.bold)));
      expect(snippet.map((piece) => piece.$2), everyElement(FontWeight.bold));

      await tap(tester, find.textContaining('stasiun'));
      final paragraph = textWeights(
        tester,
        find.descendant(
          of: find.byType(EntryReadScreen),
          matching: find.textContaining('stasiun'),
        ),
      );
      expect(paragraph, contains(('hujan', FontWeight.bold)));
      expect(paragraph.map((piece) => piece.$2), everyElement(FontWeight.bold));
    });

    testWidgets('the read view starts at the first match', (tester) async {
      await openSearchAll(tester);
      await search(tester, 'pelangi');

      await tap(tester, find.byType(KCard));
      final match = find.textContaining('Lalu muncul pelangi');
      expect(_marked(tester, find.byType(EntryReadScreen)), ['pelangi']);

      final top = tester.getTopLeft(match).dy;
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(top, inExclusiveRange(0, screen.height), reason: 'on screen');
    });
  });

  group('search in a Book', () {
    testWidgets('starts with a hint naming the Book', (tester) async {
      await openSearchIn(tester, garden);

      expect(find.text('Cari kata di Entry Kebun.'), findsOneWidget);
    });

    testWidgets('finds only that Book\'s Entries', (tester) async {
      await openSearchIn(tester, garden);
      await search(tester, 'hujan');

      expect(find.text('5 Entry di Kebun'), findsOneWidget);
      expect(find.byType(KCard), findsNWidgets(5));
      expect(find.textContaining('stasiun'), findsNothing);
    });

    testWidgets('switching to every Book keeps the query; back returns', (
      tester,
    ) async {
      await openSearchIn(tester, garden);
      await search(tester, 'hujan');

      await tap(tester, find.widgetWithText(TextButton, 'Cari di semua Book'));
      expect(_searchScreen(tester).bookId, isNull);
      expect(_fieldText(tester), 'hujan');
      expect(find.text('6 Entry di 2 Book'), findsOneWidget);

      await back(tester);
      expect(_searchScreen(tester).bookId, garden.id);
      expect(_fieldText(tester), 'hujan');
      expect(find.text('5 Entry di Kebun'), findsOneWidget);
    });

    testWidgets('with no results, offers to search every Book', (tester) async {
      await openSearchIn(tester, garden);
      await search(tester, 'stasiun');

      expect(find.text('“stasiun” tidak ada di Kebun'), findsOneWidget);
      expect(find.text('Mungkin Entry-nya ada di Book lain.'), findsOneWidget);

      await tap(tester, find.text('Cari di semua Book'));
      expect(_searchScreen(tester).bookId, isNull);
      expect(find.text('1 Entry di 1 Book'), findsOneWidget);
    });

    testWidgets('loads more results while scrolling', (tester) async {
      await openSearchIn(tester, rainy);
      await search(tester, 'gerimis');
      expect(find.text('25 Entry di Gerimis'), findsOneWidget);

      final last = find.textContaining('Gerimis nomor 24.');
      for (var i = 0; i < 20 && last.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pump();
        await settleCore(tester);
      }
      expect(last, findsOneWidget);
    });
  });

  group('helpers', () {
    test('every search screen has a path with its query', () {
      expect(Routes.search(), '/search');
      expect(Routes.search(query: 'pagi hujan'), '/search?q=pagi+hujan');
      expect(Routes.bookSearch('ab', query: 'kopi'), '/books/ab/search?q=kopi');
      expect(
        Routes.entry('ab', 'cd', query: 'é'),
        '/books/ab/entries/cd?q=%C3%A9',
      );
    });

    test('a query needs 2 characters', () {
      expect(isSearchable(' h '), isFalse);
      expect(isSearchable('hu'), isTrue);
      expect(isSearchable('🌧🌧'), isTrue);
    });

    test('snippets lose their markers and keep the matches', () {
      const marked = TextStyle(backgroundColor: Color(0xFF000000));
      final span = snippetSpan(
        '…pagi\n${matchStart}hujan$matchEnd turun',
        marked,
      );
      expect(span.toPlainText(), '…pagi hujan turun');
      expect(_markedIn(span), ['hujan']);
    });

    test('paragraphs keep where they start', () {
      const text = '  Satu.\n\n\nDua\nbaris.\n \n';
      expect(paragraphs(text), [
        (start: 2, text: 'Satu.'),
        (start: 10, text: 'Dua\nbaris.'),
      ]);
    });
  });
}
