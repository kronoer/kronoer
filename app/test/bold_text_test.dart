import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/bold_text.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

import 'text_weights.dart';

void main() {
  group('BoldTextTheme', () {
    /// A line like the Book card's: a span in a UI style, then one in an
    /// Entry style, each setting its own style.
    Future<List<(String, FontWeight?)>> weightsWith(
      WidgetTester tester, {
      required bool boldText,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(lightColorScheme),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(boldText: boldText),
            child: BoldTextTheme(child: child!),
          ),
          // In a Material, like every screen, for its default text style.
          home: Material(
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'label',
                        style: theme.textTheme.bodyMedium,
                      ),
                      TextSpan(
                        text: 'entry',
                        style: theme
                            .extension<EntryTextStyles>()!
                            .entryPreviewSmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      return textWeights(tester, find.byType(Text));
    }

    testWidgets('makes spans with their own style bold', (tester) async {
      expect(await weightsWith(tester, boldText: true), [
        ('label', FontWeight.bold),
        ('entry', FontWeight.bold),
      ]);
    });

    testWidgets('changes nothing when Bold text is off', (tester) async {
      expect(await weightsWith(tester, boldText: false), [
        ('label', FontWeight.w400),
        ('entry', FontWeight.w400),
      ]);
    });

    test('makes every text style in the theme bold', () {
      final theme = boldTheme(buildTheme(lightColorScheme));
      final entry = theme.extension<EntryTextStyles>()!;
      final styles = [
        for (final textTheme in [theme.textTheme, theme.primaryTextTheme]) ...[
          textTheme.displayLarge,
          textTheme.displayMedium,
          textTheme.displaySmall,
          textTheme.headlineLarge,
          textTheme.headlineMedium,
          textTheme.headlineSmall,
          textTheme.titleLarge,
          textTheme.titleMedium,
          textTheme.titleSmall,
          textTheme.bodyLarge,
          textTheme.bodyMedium,
          textTheme.bodySmall,
          textTheme.labelLarge,
          textTheme.labelMedium,
          textTheme.labelSmall,
        ],
        entry.entryBody,
        entry.entryPreview,
        entry.entryPreviewSmall,
      ];
      for (final style in styles) {
        expect(style?.fontWeight, FontWeight.bold);
      }
      // Everything else stays.
      expect(
        entry.entryPreviewSmall.fontSize,
        EntryTextStyles.of(lightColorScheme).entryPreviewSmall.fontSize,
      );
    });
  });

  group('in the app', () {
    final now = DateTime(2026, 11, 19, 14, 32);
    late InMemoryStore store;
    late Book book;

    setUp(() async {
      store = InMemoryStore(clock: () => now);
      book = await store.createBook('Jurnal');
      await store.createEntry(
        bookId: book.id,
        text: 'Hari ketiga.',
        imageIds: ['a', 'b', 'c'],
      );
    });
    tearDown(() => store.dispose());

    Future<void> pumpApp(WidgetTester tester) async {
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
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Finder previewLine() => find.descendant(
      of: find.byType(BookRow),
      matching: find.textContaining('3 photos · Hari ketiga.'),
    );

    testWidgets('the Book card preview line is bold with Bold text', (
      tester,
    ) async {
      turnOnBoldText(tester);
      await pumpApp(tester);

      expect(textWeights(tester, previewLine()), [
        ('3 photos', FontWeight.bold),
        (' · ', FontWeight.bold),
        ('Hari ketiga.', FontWeight.bold),
      ]);
      // Text with no spans of its own is bold too.
      expect(textWeights(tester, find.text('Jurnal')), [
        ('Jurnal', FontWeight.bold),
      ]);
    });

    testWidgets('the Book card preview line is regular without it', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(textWeights(tester, previewLine()), [
        ('3 photos', FontWeight.w400),
        (' · ', FontWeight.w400),
        ('Hari ketiga.', FontWeight.w400),
      ]);
    });

    testWidgets('the read view and the editor are bold with Bold text', (
      tester,
    ) async {
      turnOnBoldText(tester);
      await pumpApp(tester);
      await tapAndSettle(tester, find.text(book.name));
      await tapAndSettle(tester, find.text('Hari ketiga.'));

      expect(textWeights(tester, find.text('Hari ketiga.')), [
        ('Hari ketiga.', FontWeight.bold),
      ]);

      await tapAndSettle(
        tester,
        find.byWidgetPredicate((w) => w is KIcon && w.icon == KIcons.pen),
      );
      expect(find.byType(EntryEditorScreen), findsOneWidget);
      final editable = tester.allRenderObjects
          .whereType<RenderEditable>()
          .single;
      expect(spanWeights(editable.text!), [('Hari ketiga.', FontWeight.bold)]);
    });
  });
}
