import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/timeline/timeline_screen.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

import 'text_weights.dart';

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  final now = DateTime(2026, 11, 21, 9);
  late InMemoryStore store;

  const text =
      '*Pagi* ini _hujan_ ~deras~.\n'
      '\n'
      '- kopi `panas`\n'
      '- teh\n'
      '\n'
      '> kata Ibu\n'
      '\n'
      '```\n'
      'jam *7* pagi\n'
      '```';

  setUp(() async {
    store = InMemoryStore(clock: () => now);
    final book = await store.createBook('Kebun');
    await store.createEntry(bookId: book.id, text: text, dateTime: now);
  });
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

  Future<void> openEntry(WidgetTester tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text('Kebun'));
    await tapAndSettle(tester, find.byType(KCard));
    expect(find.byType(EntryReadScreen), findsOneWidget);
  }

  Finder inRead(Finder finder) =>
      find.descendant(of: find.byType(EntryReadScreen), matching: finder);

  /// Each piece of [finder]'s text with its style, after inheriting.
  List<(String, TextStyle?)> pieces(WidgetTester tester, Finder finder) {
    final rich = tester.widget<RichText>(
      find.descendant(of: finder, matching: find.byType(RichText)).first,
    );
    List<(String, TextStyle?)> walk(InlineSpan span, TextStyle? parent) {
      final style = parent?.merge(span.style) ?? span.style;
      return [
        if (span case TextSpan(:final text?) when text.isNotEmpty)
          (text, style),
        if (span case TextSpan(:final children?))
          for (final child in children) ...walk(child, style),
      ];
    }

    return walk(rich.text, null);
  }

  TextStyle? styleOf(List<(String, TextStyle?)> pieces, String text) =>
      pieces.firstWhere((piece) => piece.$1 == text).$2;

  group('read view', () {
    testWidgets('shows the styles and hides the marks', (tester) async {
      await openEntry(tester);

      // Only the monospace block keeps its marks.
      expect(inRead(find.textContaining('*')), findsOneWidget);
      expect(inRead(find.text('jam *7* pagi')), findsOneWidget);
      expect(inRead(find.textContaining('_')), findsNothing);
      expect(inRead(find.textContaining('~')), findsNothing);
      expect(inRead(find.textContaining('`')), findsNothing);
      expect(inRead(find.textContaining('> ')), findsNothing);

      final first = pieces(tester, inRead(find.text('Pagi ini hujan deras.')));
      expect(styleOf(first, 'Pagi')?.fontWeight, FontWeight.w700);
      expect(styleOf(first, 'hujan')?.fontStyle, FontStyle.italic);
      expect(styleOf(first, 'deras')?.decoration, TextDecoration.lineThrough);
      expect(styleOf(first, ' ini ')?.fontWeight, FontWeight.w400);

      final item = pieces(tester, inRead(find.text('kopi panas')));
      expect(styleOf(item, 'panas')?.fontFamily, 'monospace');
      expect(styleOf(item, 'panas')?.backgroundColor, isNotNull);
    });

    testWidgets('lists, quotes and monospace blocks', (tester) async {
      await openEntry(tester);

      // A dot for each bullet, beside its item.
      expect(inRead(find.text('•')), findsNWidgets(2));
      final dot = tester.getTopLeft(inRead(find.text('•')).first);
      final item = tester.getTopLeft(inRead(find.text('kopi panas')));
      expect(dot.dy, item.dy);
      expect(dot.dx, lessThan(item.dx));

      // The quote is dimmer than the text around it.
      final scheme = Theme.of(tester.element(find.byType(EntryReadScreen)))
          .colorScheme;
      final quote = tester.widget<Text>(inRead(find.text('kata Ibu')));
      expect(quote.style?.color, scheme.onSurfaceVariant);

      // Nothing inside a monospace block is styled.
      final code = tester.widget<Text>(inRead(find.text('jam *7* pagi')));
      expect(code.style?.fontFamily, 'monospace');
    });

    testWidgets('with Bold text, bold parts still stand out', (tester) async {
      turnOnBoldText(tester);
      await openEntry(tester);

      final weights = textWeights(
        tester,
        inRead(find.text('Pagi ini hujan deras.')),
      );
      expect(weights, contains(('Pagi', FontWeight.w900)));
      expect(weights, contains((' ini ', FontWeight.bold)));
    });
  });

  group('cards', () {
    const preview =
        'Pagi ini hujan deras. • kopi panas • teh kata Ibu jam *7* pagi';

    testWidgets('an Entry card shows the styles on one line', (tester) async {
      await pumpApp(tester);
      await tapAndSettle(tester, find.text('Kebun'));

      final card = find.descendant(
        of: find.byType(BookScreen),
        matching: find.text(preview),
      );
      expect(card, findsOneWidget);
      expect(
        styleOf(pieces(tester, card), 'Pagi')?.fontWeight,
        FontWeight.w700,
      );
    });

    testWidgets('the Timeline card too', (tester) async {
      await pumpApp(tester);
      await tapAndSettle(tester, find.text('Linimasa'));

      expect(
        find.descendant(
          of: find.byType(TimelineScreen),
          matching: find.text(preview),
        ),
        findsOneWidget,
      );
    });

    testWidgets('and the latest Entry on its Book card', (tester) async {
      await pumpApp(tester);

      final card = find.descendant(
        of: find.byType(BookListScreen),
        matching: find.byType(BookRow),
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Pagi ini hujan'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('_')),
        findsNothing,
      );
    });
  });
}
