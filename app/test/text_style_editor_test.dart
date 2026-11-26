import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

import 'text_weights.dart';

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  final now = DateTime(2026, 11, 21, 9);
  late InMemoryStore store;
  late Book book;

  setUp(() async {
    store = InMemoryStore(clock: () => now);
    book = await store.createBook('Kebun');
  });
  tearDown(() => store.dispose());

  Future<void> openEditor(WidgetTester tester) async {
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
    await tester.tap(find.text('Kebun'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditorScreen), findsOneWidget);
  }

  EditableTextState editable(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText));

  TextEditingValue valueOf(WidgetTester tester) =>
      editable(tester).textEditingValue;

  /// Each piece of the editor's text with its style, after inheriting.
  List<(String, TextStyle?)> pieces(WidgetTester tester) {
    final text = tester
        .renderObject<RenderEditable>(
          find.descendant(
            of: find.byType(EditableText),
            matching: find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_Editable',
            ),
          ),
        )
        .text!;
    List<(String, TextStyle?)> walk(InlineSpan span, TextStyle? parent) {
      final style = parent?.merge(span.style) ?? span.style;
      return [
        if (span case TextSpan(:final text?) when text.isNotEmpty)
          (text, style),
        if (span case TextSpan(:final children?))
          for (final child in children) ...walk(child, style),
      ];
    }

    return walk(text, null);
  }

  TextStyle? styleOf(WidgetTester tester, String text) =>
      pieces(tester).firstWhere((piece) => piece.$1 == text).$2;

  /// Selects [selected] in the editor and opens the selection menu.
  Future<void> select(WidgetTester tester, String selected) async {
    final text = valueOf(tester).text;
    final start = text.indexOf(selected);
    editable(tester).userUpdateTextEditingValue(
      valueOf(tester).copyWith(
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + selected.length,
        ),
      ),
      SelectionChangedCause.drag,
    );
    await tester.pump();
    editable(tester).showToolbar();
    await tester.pumpAndSettle();
  }

  /// Taps [label] in the selection menu, opening its overflow if needed.
  Future<void> pick(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isEmpty) {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('styles show while typing, the marks dimmed', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), '*Pagi* ini `kopi`');
    await tester.pump();

    final scheme = Theme.of(tester.element(find.byType(EditableText)))
        .colorScheme;
    // The marks stay, so the cursor moves over the text as written.
    expect(pieces(tester).map((piece) => piece.$1).join(), '*Pagi* ini `kopi`');
    expect(styleOf(tester, '*')?.color, scheme.outline);
    expect(styleOf(tester, 'Pagi')?.fontWeight, FontWeight.w700);
    expect(styleOf(tester, ' ini ')?.fontWeight, isNot(FontWeight.w700));
    expect(styleOf(tester, 'kopi')?.fontFamily, 'monospace');

    // Deleting a mark takes its style away.
    await tester.enterText(find.byType(TextField), '*Pagi ini `kopi`');
    await tester.pump();
    expect(styleOf(tester, '*Pagi ini ')?.fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('with Bold text, bold parts still stand out', (tester) async {
    turnOnBoldText(tester);
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), '*Pagi* ini');
    await tester.pump();

    expect(styleOf(tester, 'Pagi')?.fontWeight, FontWeight.w900);
  });

  testWidgets('the selection menu has the eight styles', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Pagi ini hujan');
    await select(tester, 'ini');

    // The first page of the menu holds the system's items and the first
    // styles; the rest are behind ⋮.
    for (final label in [
      'Bold',
      'Italic',
      'Strikethrough',
      'Mono',
      'Code',
      'Bulleted list',
      'Numbered list',
      'Quote',
    ]) {
      if (find.text(label).evaluate().isEmpty &&
          find.byIcon(Icons.more_vert).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('without a selection, the menu has no styles', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Pagi ini hujan');
    await tester.pump();
    editable(tester).showToolbar();
    await tester.pumpAndSettle();

    if (find.byIcon(Icons.more_vert).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }
    expect(find.text('Bold'), findsNothing);
  });

  testWidgets('picking a style adds it, and again takes it away', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Pagi ini hujan');
    await select(tester, 'ini');
    await pick(tester, 'Bold');
    expect(valueOf(tester).text, 'Pagi *ini* hujan');
    expect(styleOf(tester, 'ini')?.fontWeight, FontWeight.w700);

    // The selection stays on the text, so picking again undoes it.
    editable(tester).showToolbar();
    await tester.pumpAndSettle();
    await pick(tester, 'Bold');
    expect(valueOf(tester).text, 'Pagi ini hujan');
  });

  testWidgets('a line style goes on every selected line, and is saved', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'roti\nteh');
    await select(tester, 'roti\nteh');
    await pick(tester, 'Numbered list');
    expect(valueOf(tester).text, '1. roti\n2. teh');

    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    final entries = await store.watchEntries(book.id).first;
    expect(entries.single.text, '1. roti\n2. teh');
  });

  testWidgets('Enter continues a list, and ends it in an empty item', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), '- roti');
    await tester.pump();

    Future<void> enter() async {
      final value = valueOf(tester);
      final at = value.selection.start;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: value.text.replaceRange(at, at, '\n'),
          selection: TextSelection.collapsed(offset: at + 1),
        ),
      );
      await tester.pump();
    }

    await enter();
    expect(valueOf(tester).text, '- roti\n- ');
    expect(valueOf(tester).selection.start, 9);

    await enter();
    expect(valueOf(tester).text, '- roti\n');
    expect(valueOf(tester).selection.start, 7);
  });
}
