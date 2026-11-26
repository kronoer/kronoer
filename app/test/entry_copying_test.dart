import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_copying.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

Entry _entry(
  String text,
  DateTime dateTime, {
  List<String> imageIds = const [],
}) => Entry(
  id: text,
  bookId: 'book',
  text: text,
  dateTime: dateTime,
  createdAt: dateTime,
  updatedAt: dateTime,
  imageIds: imageIds,
);

/// Remembers what it was asked to copy and answers with [result].
class _FakeClipboard implements TextClipboard {
  CopyResult result = CopyResult.copied;
  final asked = <String>[];

  @override
  Future<CopyResult> copySensitive(String text) async {
    asked.add(text);
    return result;
  }
}

// These tests never show Welcome, so they do not need the Rust library.
void main() {
  group('copied text', () {
    String dateLine(DateTime dateTime) => '${dateTime.day} Nov';

    test('starts with the date line and a blank line', () {
      expect(
        copiedText([
          _entry('*Pagi* ini hujan.\n- kopi', DateTime(2026, 11, 16)),
        ], dateLine),
        '16 Nov\n\nPagi ini hujan.\n• kopi',
      );
    });

    test('parts Entries by two blank lines, in the order given', () {
      expect(
        copiedText([
          _entry('Kedua.', DateTime(2026, 11, 17)),
          _entry('Pertama.', DateTime(2026, 11, 16)),
        ], dateLine),
        '17 Nov\n\nKedua.\n\n\n16 Nov\n\nPertama.',
      );
    });

    test('leaves out Entries with no text', () {
      expect(
        copiedText([
          _entry('', DateTime(2026, 11, 18), imageIds: ['a']),
          _entry(' \n ', DateTime(2026, 11, 17), imageIds: ['b']),
          _entry('Ada teks.', DateTime(2026, 11, 16)),
        ], dateLine),
        '16 Nov\n\nAda teks.',
      );
      expect(copiedText([_entry('', DateTime(2026))], dateLine), '');
    });
  });

  group('platform clipboard', () {
    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(TestWidgetsFlutterBinding.ensureInitialized);
    tearDown(() {
      messenger()
        ..setMockMethodCallHandler(PlatformClipboard.channel, null)
        ..setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('on Android, copies through the channel', () async {
      final calls = <MethodCall>[];
      messenger().setMockMethodCallHandler(PlatformClipboard.channel, (
        call,
      ) async {
        calls.add(call);
        return 'copiedWithPreview';
      });

      final result = await PlatformClipboard(isAndroid: true)
          .copySensitive('teks');

      expect(result, CopyResult.copiedWithPreview);
      expect(calls.single.method, 'copySensitive');
      expect(calls.single.arguments, 'teks');
    });

    test('on Android, says when the system found it too long', () async {
      messenger().setMockMethodCallHandler(
        PlatformClipboard.channel,
        (_) async => 'tooLong',
      );

      expect(
        await PlatformClipboard(isAndroid: true).copySensitive('teks'),
        CopyResult.tooLong,
      );
    });

    test('text too long is never sent', () async {
      var sent = false;
      messenger().setMockMethodCallHandler(PlatformClipboard.channel, (
        _,
      ) async {
        sent = true;
        return 'copied';
      });

      final result = await PlatformClipboard(isAndroid: true)
          .copySensitive('a' * (PlatformClipboard.maxLength + 1));

      expect(result, CopyResult.tooLong);
      expect(sent, isFalse);
    });

    test('elsewhere, copies with Flutter', () async {
      final calls = <MethodCall>[];
      messenger().setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        calls.add(call);
        return null;
      });

      final result = await PlatformClipboard(isAndroid: false)
          .copySensitive('teks');

      expect(result, CopyResult.copied);
      expect(calls.single.method, 'Clipboard.setData');
      expect(calls.single.arguments, {'text': 'teks'});
    });
  });

  group('copying in the app', () {
    late DateTime now;
    late InMemoryStore store;
    late Book mine;
    late _FakeClipboard clipboard;

    void later() => now = now.add(const Duration(minutes: 1));

    setUp(() async {
      now = DateTime(2026, 11, 22, 9, 30);
      store = InMemoryStore(clock: () => now);
      clipboard = _FakeClipboard();
      mine = await store.createBook('My Book').whenComplete(later);
      for (final (text, dateTime) in [
        ('Rapat *pagi* dengan tim.', DateTime(2026, 10, 28, 9)),
        ('Presentasi selesai.', DateTime(2026, 10, 30, 13, 5)),
        ('', DateTime(2026, 11, 1, 8)),
        ('Pagi ini hujan.\n- kopi', DateTime(2026, 11, 16, 19, 40)),
      ]) {
        await store
            .createEntry(
              bookId: mine.id,
              text: text,
              dateTime: dateTime,
              imageIds: text.isEmpty ? ['a'] : const [],
            )
            .whenComplete(later);
      }
    });
    tearDown(() => store.dispose());

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openMine(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      tester.platformDispatcher.localesTestValue = [locale];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      // Tall enough for every card.
      tester.view
        ..physicalSize = const Size(800, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryStoreProvider.overrideWithValue(store),
            clockProvider.overrideWithValue(() => now),
            hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
            textClipboardProvider.overrideWithValue(clipboard),
          ],
          child: const KronoerApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('My Book'));
      expect(find.byType(BookScreen), findsOneWidget);
    }

    Finder card(String text) => find.ancestor(
      of: find.textContaining(text),
      matching: find.byType(KCard),
    );

    /// The card of the Entry of Images only.
    Finder imagesOnly() => find
        .ancestor(of: find.byType(EntryImage), matching: find.byType(KCard))
        .first;

    Future<void> select(WidgetTester tester, List<Finder> cards) async {
      await tester.longPress(cards.first);
      await tester.pumpAndSettle();
      for (final card in cards.skip(1)) {
        await tap(tester, card);
      }
    }

    IconButton copyButton(WidgetTester tester) => tester.widget<IconButton>(
      find.ancestor(of: _kIcon(KIcons.copy), matching: find.byType(IconButton)),
    );

    bool selecting(WidgetTester tester) =>
        find.byTooltip('Move').hitTestable().evaluate().isNotEmpty;

    group('selection mode', () {
      testWidgets('Copy sits before Move and Delete', (tester) async {
        await openMine(tester);
        await select(tester, [card('Presentasi selesai.')]);

        final copy = tester.getTopLeft(find.byTooltip('Copy'));
        final move = tester.getTopLeft(find.byTooltip('Move'));
        final delete = tester.getTopLeft(find.byTooltip('Delete'));
        expect(copy.dx, lessThan(move.dx));
        expect(move.dx, lessThan(delete.dx));
      });

      testWidgets('copies in Book order, skipping Entries with no text', (
        tester,
      ) async {
        await openMine(tester);
        // Picked oldest first; the Book shows newest first.
        await select(tester, [
          card('Rapat pagi dengan tim.'),
          imagesOnly(),
          card('Pagi ini hujan.'),
        ]);

        await tap(tester, find.byTooltip('Copy'));

        expect(clipboard.asked, [
          'Monday, November 16, 2026 at 19:40\n\n'
              'Pagi ini hujan.\n• kopi\n\n\n'
              'Wednesday, October 28, 2026 at 09:00\n\n'
              'Rapat pagi dengan tim.',
        ]);
        expect(selecting(tester), isFalse);
        // Only the Entries with text count.
        expect(find.text('Text of 2 Entries copied'), findsOneWidget);
      });

      testWidgets('one Entry says Teks disalin', (tester) async {
        await openMine(tester);
        await select(tester, [card('Presentasi selesai.')]);

        await tap(tester, find.byTooltip('Copy'));

        expect(find.text('Text copied'), findsOneWidget);
      });

      testWidgets('no snackbar where the system shows the clipboard', (
        tester,
      ) async {
        clipboard.result = CopyResult.copiedWithPreview;
        await openMine(tester);
        await select(tester, [card('Presentasi selesai.')]);

        await tap(tester, find.byTooltip('Copy'));

        expect(clipboard.asked, hasLength(1));
        expect(find.byType(SnackBar), findsNothing);
        expect(selecting(tester), isFalse);
      });

      testWidgets('Copy is disabled with only Entries with no text', (
        tester,
      ) async {
        await openMine(tester);
        await select(tester, [imagesOnly()]);
        expect(copyButton(tester).onPressed, isNull);

        await tap(tester, card('Presentasi selesai.'));
        expect(copyButton(tester).onPressed, isNotNull);
      });

      testWidgets('too long copies nothing and keeps the selection', (
        tester,
      ) async {
        clipboard.result = CopyResult.tooLong;
        await openMine(tester);
        await select(tester, [
          card('Presentasi selesai.'),
          card('Pagi ini hujan.'),
        ]);

        await tap(tester, find.byTooltip('Copy'));

        expect(
          find.text('The text is too long to copy. Select fewer Entries.'),
          findsOneWidget,
        );
        expect(selecting(tester), isTrue);
        expect(find.bySemanticsLabel('2 selected'), findsOneWidget);
      });
    });

    group('read view menu', () {
      Future<void> openMenu(WidgetTester tester) =>
          tap(tester, _kIcon(KIcons.moreVertical));

      testWidgets('Copy text comes first and copies the Entry', (tester) async {
        await openMine(tester);
        await tap(tester, card('Pagi ini hujan.'));
        await openMenu(tester);

        final copy = tester.getTopLeft(find.text('Copy text'));
        final move = tester.getTopLeft(find.text('Move to another Book'));
        expect(copy.dy, lessThan(move.dy));

        await tap(tester, find.text('Copy text'));

        expect(clipboard.asked, [
          'Monday, November 16, 2026 at 19:40\n\nPagi ini hujan.\n• kopi',
        ]);
        expect(find.byType(EntryReadScreen), findsOneWidget);
        expect(find.text('Text copied'), findsOneWidget);
      });

      testWidgets('the date line is in Indonesian too', (tester) async {
        await openMine(tester, locale: const Locale('id'));
        await tap(tester, card('Presentasi selesai.'));
        await openMenu(tester);

        await tap(tester, find.text('Salin teks'));

        expect(clipboard.asked, [
          'Jumat, 30 Oktober 2026 pukul 13.05\n\nPresentasi selesai.',
        ]);
        expect(find.text('Teks disalin'), findsOneWidget);
      });

      testWidgets('too long says so without asking for fewer', (tester) async {
        clipboard.result = CopyResult.tooLong;
        await openMine(tester);
        await tap(tester, card('Presentasi selesai.'));
        await openMenu(tester);

        await tap(tester, find.text('Copy text'));

        expect(find.text('The text is too long to copy.'), findsOneWidget);
      });

      testWidgets('an Entry with no text has no Copy text', (tester) async {
        await openMine(tester);
        await tap(tester, imagesOnly());
        await openMenu(tester);

        expect(find.text('Move to another Book'), findsOneWidget);
        expect(find.text('Copy text'), findsNothing);
      });

      testWidgets('the editor menu has no Copy text', (tester) async {
        await openMine(tester);
        await tap(tester, card('Pagi ini hujan.'));
        await tap(tester, find.byTooltip('Edit Entry'));
        expect(find.byType(EntryEditorScreen), findsOneWidget);

        await tap(tester, _kIcon(KIcons.moreVertical).last);

        expect(find.text('Delete Entry'), findsOneWidget);
        expect(find.text('Copy text'), findsNothing);
      });
    });
  });
}
