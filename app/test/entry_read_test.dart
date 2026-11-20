import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/image_placeholder.dart';
import 'package:kronoer/src/entries/image_viewer_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  final now = DateTime(2026, 11, 19, 14, 32);
  late InMemoryStore store;
  late Book book;
  late Entry entry;

  setUp(() async {
    store = InMemoryStore(clock: () => now);
    book = await store.createBook('Buku Saya');
    entry = await store.createEntry(
      bookId: book.id,
      text: 'Pagi ini hujan turun pelan.\n\nSiangnya Ibu menelepon.',
      dateTime: DateTime(2026, 11, 16, 19, 40),
      imageIds: ['a', 'b', 'c'],
    );
  });
  tearDown(() => store.dispose());

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Opens [entry] from its Book.
  Future<void> openEntry(
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
    await tapAndSettle(tester, find.text(book.name));
    await tapAndSettle(tester, find.textContaining('Pagi ini hujan'));
    expect(find.byType(EntryReadScreen), findsOneWidget);
  }

  Future<void> deleteFromMenu(WidgetTester tester) async {
    await tapAndSettle(tester, _kIcon(KIcons.moreVertical));
    await tapAndSettle(tester, find.text('Hapus Entry'));
  }

  group('read view', () {
    testWidgets('shows the date, the time, and every paragraph', (
      tester,
    ) async {
      await openEntry(tester);

      expect(find.text('Senin, 16 November 2026'), findsOneWidget);
      expect(find.text('19.40'), findsOneWidget);
      expect(find.text('Pagi ini hujan turun pelan.'), findsOneWidget);
      expect(find.text('Siangnya Ibu menelepon.'), findsOneWidget);
      expect(find.text(book.name), findsOneWidget);
    });

    testWidgets('shows the date in English too', (tester) async {
      await openEntry(tester, locale: const Locale('en'));

      expect(find.text('Monday, November 16, 2026'), findsOneWidget);
    });

    testWidgets('shows every image', (tester) async {
      await openEntry(tester);

      // The list builds lazily, so each image is checked as it scrolls in.
      for (var i = 1; i <= 3; i++) {
        final image = find.bySemanticsLabel('Foto $i dari 3, buka layar penuh');
        await tester.scrollUntilVisible(image, 200);
        expect(image, findsOneWidget);
      }
    });

    testWidgets('only the pen opens the editor', (tester) async {
      await openEntry(tester);

      await tapAndSettle(tester, find.text('Pagi ini hujan turun pelan.'));
      expect(find.byType(EntryEditorScreen), findsNothing);

      await tapAndSettle(tester, _kIcon(KIcons.pen));
      expect(find.byType(EntryEditorScreen), findsOneWidget);
    });
  });

  group('image viewer', () {
    testWidgets('opens on the tapped image and swipes to the next', (
      tester,
    ) async {
      await openEntry(tester);

      await tapAndSettle(tester, find.byType(ImagePlaceholder).first);
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('is dark in a light app', (tester) async {
      await openEntry(tester);
      await tapAndSettle(tester, find.byType(ImagePlaceholder).first);

      final context = tester.element(find.byType(ImagePlaceholder).first);
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        Colors.black,
      );
    });

    testWidgets('zooms with a pinch', (tester) async {
      await openEntry(tester);
      await tapAndSettle(tester, find.byType(ImagePlaceholder).first);

      final center = tester.getCenter(find.byType(PageView));
      final a = await tester.startGesture(center - const Offset(20, 0));
      final b = await tester.startGesture(center + const Offset(20, 0));
      await a.moveBy(const Offset(-100, 0));
      await b.moveBy(const Offset(100, 0));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer).first,
      );
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
    });

    testWidgets('× closes it', (tester) async {
      await openEntry(tester);
      await tapAndSettle(tester, find.byType(ImagePlaceholder).first);

      await tapAndSettle(tester, _kIcon(KIcons.x));
      expect(find.byType(ImageViewerScreen), findsNothing);
      expect(find.byType(EntryReadScreen), findsOneWidget);
    });
  });

  group('delete', () {
    testWidgets('returns to the Book and offers undo, with no dialog', (
      tester,
    ) async {
      await openEntry(tester);

      await deleteFromMenu(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.byType(EntryReadScreen), findsNothing);
      expect(find.text('Entry dihapus'), findsOneWidget);
      expect(find.text('Urungkan'), findsOneWidget);
      expect(find.textContaining('Pagi ini hujan'), findsNothing);
    });

    testWidgets('the Entry is gone once the snackbar closes', (tester) async {
      await openEntry(tester);
      await deleteFromMenu(tester);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('Entry dihapus'), findsNothing);
      expect(await store.watchEntry(entry.id).first, isNull);
      expect(find.textContaining('Pagi ini hujan'), findsNothing);
    });

    testWidgets('undo brings the Entry back as it was', (tester) async {
      await openEntry(tester);
      await deleteFromMenu(tester);

      await tapAndSettle(tester, find.text('Urungkan'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pagi ini hujan'), findsOneWidget);
      final restored = await store.watchEntry(entry.id).first;
      expect(restored?.text, entry.text);
      expect(restored?.imageIds, entry.imageIds);
    });
  });
}
