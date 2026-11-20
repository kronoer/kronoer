import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/image_viewer_screen.dart';
import 'package:kronoer/src/sample/sample_data.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:kronoer/src/welcome/welcome_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'core_test_store.dart';

Future<void> _pumpApp(
  WidgetTester tester, [
  List<Override> overrides = const [],
]) async {
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const KronoerApp()),
  );
  await tester.pumpAndSettle();
}

/// A started app with one Book holding one Entry with one image.
Future<List<Override>> _oneBook() async {
  final store = InMemoryStore();
  final book = await store.createBook('Buku Saya');
  await store.createEntry(
    bookId: book.id,
    text: 'Pagi ini hujan.',
    imageIds: ['image-1'],
  );
  return [
    inMemoryStoreProvider.overrideWithValue(store),
    hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
  ];
}

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Welcome', () {
    testWidgets('falls back to English on a non-Indonesian device', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await _pumpApp(tester);
      expect(
        find.text('Your secret place to tell your stories'),
        findsOneWidget,
      );
      expect(find.text("Let's start writing"), findsOneWidget);
    });

    testWidgets('uses Indonesian on an Indonesian device', (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('id')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await _pumpApp(tester);
      expect(find.text('Ruang rahasiamu untuk bercerita'), findsOneWidget);
      expect(find.text('Tanpa akun, tanpa password.'), findsOneWidget);
      expect(find.text('Yuk, mulai cerita'), findsOneWidget);
    });
  });

  group('first launch', () {
    testWidgets('an empty app opens Welcome', (tester) async {
      await _pumpApp(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('with sample data it opens the Book list', (tester) async {
      // The sample data lives in a core store, which answers in real time.
      final overrides = (await tester.runAsync(sampleOverrides))!;
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const KronoerApp()),
      );
      await settleCore(tester);

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.byType(KCard), findsWidgets);
    });
  });

  group('navigation', () {
    testWidgets('Book list → Book → Entry → image, and back', (tester) async {
      await _pumpApp(tester, await _oneBook());

      await _tapAndSettle(tester, find.text('Buku Saya'));
      expect(find.byType(BookScreen), findsOneWidget);

      await _tapAndSettle(tester, find.text('Pagi ini hujan.'));
      expect(find.byType(EntryReadScreen), findsOneWidget);

      await _tapAndSettle(tester, find.byType(EntryImage));
      expect(find.byType(ImageViewerScreen), findsOneWidget);

      await _tapAndSettle(tester, _kIcon(KIcons.x));
      expect(find.byType(EntryReadScreen), findsOneWidget);

      for (final screen in [BookScreen, BookListScreen]) {
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget);
      }
    });

    testWidgets('the pen opens the editor for a new Entry', (tester) async {
      await _pumpApp(tester, await _oneBook());
      await _tapAndSettle(tester, find.text('Buku Saya'));

      await _tapAndSettle(tester, find.byType(FloatingActionButton));
      final editor = tester.widget<EntryEditorScreen>(
        find.byType(EntryEditorScreen),
      );
      expect(editor.entryId, isNull);
    });

    testWidgets('the pen in the read view edits that Entry', (tester) async {
      await _pumpApp(tester, await _oneBook());
      await _tapAndSettle(tester, find.text('Buku Saya'));
      await _tapAndSettle(tester, find.text('Pagi ini hujan.'));

      await _tapAndSettle(tester, _kIcon(KIcons.pen));
      final editor = tester.widget<EntryEditorScreen>(
        find.byType(EntryEditorScreen),
      );
      expect(editor.entryId, isNotNull);
    });

    testWidgets('the settings button opens Settings', (tester) async {
      await _pumpApp(tester, await _oneBook());

      await _tapAndSettle(tester, _kIcon(KIcons.settings));
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}
