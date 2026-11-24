import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_info_screen.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/lock/locked_books_screen.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_app_lock_platform.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  late InMemoryStore store;
  late FakeAppLockPlatform platform;
  late Book garden;
  late Book trips;

  setUp(() async {
    store = InMemoryStore();
    platform = FakeAppLockPlatform();
    garden = await store.createBook('Kebun');
    trips = await store.createBook('Perjalanan');
  });
  tearDown(() => store.dispose());

  Future<void> launch(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
          appLockPlatformProvider.overrideWithValue(platform),
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

  Future<void> go(WidgetTester tester, String location) async {
    ProviderScope.containerOf(tester.element(find.byType(KronoerApp)))
        .read(routerProvider)
        .go(location);
    await tester.pumpAndSettle();
  }

  Future<Book> saved(Book book) async =>
      (await store.watchBook(book.id).first)!;

  Switch lockSwitch(WidgetTester tester) => tester.widget<Switch>(
    find.descendant(
      of: find.widgetWithText(ListTile, 'Kunci Book'),
      matching: find.byType(Switch),
    ),
  );

  String location(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(KronoerApp)))
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .toString();

  bool areaOpen(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(KronoerApp)))
          .read(appLockProvider)
          .lockedBooksOpen;

  /// Pulls the Book list down past its top.
  Future<void> pull(WidgetTester tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await tester.pumpAndSettle();
  }

  /// Opens the Book terkunci page from the Book list.
  Future<void> openArea(WidgetTester tester) async {
    await pull(tester);
    await tapAndSettle(tester, find.text('Book terkunci'));
    expect(find.byType(LockedBooksScreen), findsOneWidget);
  }

  /// Kronoer goes to the background, as on Home, and comes back.
  Future<void> leaveAndComeBack(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  /// Brings the Kunci Book row out from under the bottom of the screen.
  Future<void> showLockRow(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Kunci Book'), 100);
    await tester.pumpAndSettle();
  }

  group('Book info', () {
    testWidgets('Kunci Book locks after the prompt and goes back to the '
        'Book list', (tester) async {
      await launch(tester);
      await go(tester, Routes.bookInfo(garden.id));
      await showLockRow(tester);
      expect(lockSwitch(tester).value, isFalse);
      expect(find.text('Sembunyikan dari daftar Book'), findsOneWidget);

      await tapAndSettle(tester, find.text('Kunci Book'));

      expect(platform.prompts, ['Kunci Book']);
      expect((await saved(garden)).locked, isTrue);
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('Kebun'), findsNothing);
      expect(find.text('Perjalanan'), findsOneWidget);
      expect(find.text('Book dikunci'), findsOneWidget);
    });

    testWidgets('a cancelled prompt locks nothing', (tester) async {
      platform.answer = Unlock.cancelled;
      await launch(tester);
      await go(tester, Routes.bookInfo(garden.id));
      await showLockRow(tester);

      await tapAndSettle(tester, find.byType(Switch).last);

      expect(platform.prompts, hasLength(1));
      expect((await saved(garden)).locked, isFalse);
      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(lockSwitch(tester).value, isFalse);
    });

    testWidgets("a Locked Book's own Book info unlocks it", (tester) async {
      await store.setBooksLocked([garden.id], locked: true);
      await launch(tester);
      expect(find.text('Kebun'), findsNothing);
      await openArea(tester);
      platform.prompts.clear();
      await go(tester, Routes.bookInfo(garden.id));
      expect(location(tester), Routes.lockedBooks + Routes.bookInfo(garden.id));
      await showLockRow(tester);
      expect(lockSwitch(tester).value, isTrue);
      expect(
        find.text(
          'Tersembunyi dari daftar Book, dibuka dengan sidik jari atau '
          'kunci layar',
        ),
        findsOneWidget,
      );

      await tapAndSettle(tester, find.text('Kunci Book'));

      expect(platform.prompts, ['Buka kunci Book']);
      expect((await saved(garden)).locked, isFalse);
      expect(lockSwitch(tester).value, isFalse);

      // Back on the page, which has no Locked Book left.
      await tapAndSettle(tester, find.byType(BackButton));
      await tapAndSettle(tester, find.byType(BackButton));
      expect(find.byType(LockedBooksScreen), findsOneWidget);
      expect(find.text('Tidak ada Book terkunci'), findsOneWidget);
      await tapAndSettle(tester, find.byType(BackButton));
      expect(find.text('Kebun'), findsOneWidget);
    });

    testWidgets('without a screen lock the switch cannot turn on', (
      tester,
    ) async {
      platform.screenLock = false;
      await launch(tester);
      await go(tester, Routes.bookInfo(garden.id));
      await showLockRow(tester);

      expect(lockSwitch(tester).onChanged, isNull);
      expect(
        find.text('Pasang kunci layar di HP ini dulu untuk mengunci Book'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Buka pengaturan'));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Buka pengaturan'));
      expect(platform.securityOpened, 1);
      expect(platform.prompts, isEmpty);
    });
  });

  group('selection mode', () {
    Future<void> select(WidgetTester tester, List<String> names) async {
      await tester.longPress(find.text(names.first));
      await tester.pumpAndSettle();
      for (final name in names.skip(1)) {
        await tapAndSettle(tester, find.text(name));
      }
    }

    testWidgets('Kunci locks every selected Book and unpins it', (
      tester,
    ) async {
      final kitchen = await store.createBook('Dapur');
      await store.setBooksPinned([trips.id], pinned: true);
      await launch(tester);
      await select(tester, ['Kebun', 'Perjalanan']);

      await tapAndSettle(tester, _kIcon(KIcons.lock));

      expect(platform.prompts, ['Kunci Book']);
      expect(find.text('2 Book dikunci'), findsOneWidget);
      expect(find.text('Kebun'), findsNothing);
      expect(find.text('Perjalanan'), findsNothing);
      expect(find.text('Dapur'), findsOneWidget);
      // Selection mode ended.
      expect(_kIcon(KIcons.lock), findsNothing);
      final locked = await saved(trips);
      expect(locked.locked, isTrue);
      expect(locked.pinned, isFalse);
      expect((await saved(kitchen)).locked, isFalse);
    });

    testWidgets('a cancelled prompt keeps the selection', (tester) async {
      platform.answer = Unlock.cancelled;
      await launch(tester);
      await select(tester, ['Kebun']);

      await tapAndSettle(tester, _kIcon(KIcons.lock));

      expect((await saved(garden)).locked, isFalse);
      expect(find.text('Kebun'), findsOneWidget);
      expect(_kIcon(KIcons.lock), findsOneWidget);
    });

    testWidgets('without a screen lock Kunci says to set one first', (
      tester,
    ) async {
      platform.screenLock = false;
      await launch(tester);
      await select(tester, ['Kebun']);

      await tapAndSettle(tester, _kIcon(KIcons.lock));

      expect(find.text('Pasang kunci layar dulu'), findsOneWidget);
      expect(platform.prompts, isEmpty);
      await tapAndSettle(tester, find.text('Buka pengaturan'));
      expect(platform.securityOpened, 1);
      expect((await saved(garden)).locked, isFalse);
    });
  });

  group('Book terkunci', () {
    testWidgets('the link shows only when pulled, and only with a Locked '
        'Book', (tester) async {
      await launch(tester);
      await pull(tester);
      expect(find.text('Book terkunci'), findsNothing);

      await store.setBooksLocked([garden.id], locked: true);
      await tester.pumpAndSettle();
      expect(find.text('Book terkunci'), findsNothing);
      await pull(tester);
      expect(find.text('Book terkunci'), findsOneWidget);
      // Still the first thing in the list, above the Books.
      expect(
        tester.getTopLeft(find.text('Book terkunci')).dy,
        lessThan(tester.getTopLeft(find.text('Perjalanan')).dy),
      );
    });

    testWidgets('it opens the page of Locked Books after the prompt, with '
        'Recents hidden', (tester) async {
      final kitchen = await store.createBook('Dapur');
      await store.setBooksLocked([garden.id, kitchen.id], locked: true);
      await launch(tester);
      expect(platform.recentsHidden, isFalse);

      await openArea(tester);

      expect(platform.prompts, ['Buka Book terkunci']);
      expect(location(tester), Routes.lockedBooks);
      expect(find.text('Kebun'), findsOneWidget);
      expect(find.text('Dapur'), findsOneWidget);
      expect(find.text('Perjalanan'), findsNothing);
      // No Book baru here.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(platform.recentsHidden, isTrue);
    });

    testWidgets('a cancelled prompt stays on the Book list', (tester) async {
      await store.setBooksLocked([garden.id], locked: true);
      platform.answer = Unlock.cancelled;
      await launch(tester);
      await pull(tester);

      await tapAndSettle(tester, find.text('Book terkunci'));

      expect(platform.prompts, hasLength(1));
      expect(find.byType(LockedBooksScreen), findsNothing);
      expect(areaOpen(tester), isFalse);
      expect(platform.recentsHidden, isFalse);
    });

    testWidgets('without a screen lock it says to set one, and nothing '
        'opens', (tester) async {
      await store.setBooksLocked([garden.id], locked: true);
      platform.screenLock = false;
      await launch(tester);
      await pull(tester);

      await tapAndSettle(tester, find.text('Book terkunci'));

      expect(find.text('Pasang kunci layar dulu'), findsOneWidget);
      expect(platform.prompts, isEmpty);
      await tapAndSettle(tester, find.text('Buka pengaturan'));
      expect(platform.securityOpened, 1);
      expect(find.byType(LockedBooksScreen), findsNothing);
      expect((await saved(garden)).locked, isTrue);
    });

    testWidgets('a Locked Book works inside, and back leads to the page', (
      tester,
    ) async {
      await store.createEntry(bookId: garden.id, text: 'Cabai mulai berbunga.');
      await store.setBooksLocked([garden.id], locked: true);
      await launch(tester);
      await openArea(tester);

      await tapAndSettle(tester, find.text('Kebun'));
      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.text('Cabai mulai berbunga.'), findsOneWidget);
      expect(location(tester), Routes.lockedBooks + Routes.book(garden.id));

      // Screens link to the Book's usual paths; they stay in the area.
      await go(tester, Routes.bookInfo(garden.id));
      expect(location(tester), Routes.lockedBooks + Routes.bookInfo(garden.id));
      expect(find.byType(BookInfoScreen), findsOneWidget);

      await tapAndSettle(tester, find.byType(BackButton));
      await tapAndSettle(tester, find.byType(BackButton));
      expect(find.byType(LockedBooksScreen), findsOneWidget);
      expect(areaOpen(tester), isTrue);
    });

    testWidgets('going back to the Book list locks it again', (tester) async {
      await store.setBooksLocked([garden.id], locked: true);
      await launch(tester);
      await openArea(tester);

      await tapAndSettle(tester, find.byType(BackButton));

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(areaOpen(tester), isFalse);
      expect(platform.recentsHidden, isFalse);
      // The link folded away again.
      expect(find.text('Book terkunci'), findsNothing);
      // Nothing inside opens without the prompt.
      await go(tester, Routes.lockedBooks);
      expect(location(tester), Routes.books);
      await go(tester, Routes.book(garden.id));
      expect(location(tester), Routes.books);
      expect(find.byType(BookScreen), findsNothing);
    });

    testWidgets('going to the background locks it again', (tester) async {
      await store.setBooksLocked([garden.id], locked: true);
      await launch(tester);
      await openArea(tester);
      await tapAndSettle(tester, find.text('Kebun'));

      await leaveAndComeBack(tester);

      expect(areaOpen(tester), isFalse);
      expect(location(tester), Routes.books);
      expect(find.byType(BookScreen), findsNothing);
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(platform.recentsHidden, isFalse);
    });

    testWidgets("the prompt's own trip does not lock it again", (tester) async {
      await store.setBooksLocked([garden.id], locked: true);
      await launch(tester);
      await pull(tester);
      platform.holding = Completer();
      await tester.tap(find.text('Book terkunci'));
      await tester.pump();
      // The system prompt takes Kronoer to the background and back.
      await leaveAndComeBack(tester);
      platform.holding!.complete(Unlock.unlocked);
      await tester.pumpAndSettle();

      expect(find.byType(LockedBooksScreen), findsOneWidget);
      expect(areaOpen(tester), isTrue);
    });

    testWidgets('with every Book locked, the empty Book list still has the '
        'link', (tester) async {
      await store.setBooksLocked([garden.id, trips.id], locked: true);
      await launch(tester);
      expect(find.text('Belum ada Book'), findsOneWidget);

      await openArea(tester);

      expect(find.text('Kebun'), findsOneWidget);
      expect(find.text('Perjalanan'), findsOneWidget);
    });
  });

  group('elsewhere', () {
    testWidgets('the Timeline leaves Locked Books out', (tester) async {
      await store.createEntry(bookId: garden.id, text: 'Cabai berbunga.');
      await store.createEntry(bookId: trips.id, text: 'Kereta ke Malang.');
      await store.setBooksLocked([garden.id], locked: true);
      await launch(tester);

      await go(tester, Routes.timeline);

      expect(find.text('Kereta ke Malang.'), findsOneWidget);
      expect(find.text('Cabai berbunga.'), findsNothing);
    });

    /// Selects the Entry [text] in its Book and opens Pindahkan ke.
    Future<void> moveFrom(WidgetTester tester, String text) async {
      await tester.longPress(find.text(text));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byTooltip('Pindahkan'));
    }

    List<String?> targets(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        (tile.title! as Text).data,
    ];

    testWidgets('Pindahkan ke outside the area lists no Locked Book', (
      tester,
    ) async {
      final kitchen = await store.createBook('Dapur');
      await store.createEntry(bookId: trips.id, text: 'Kereta ke Malang.');
      await store.setBooksLocked([garden.id, kitchen.id], locked: true);
      await launch(tester);

      await go(tester, Routes.book(trips.id));
      await moveFrom(tester, 'Kereta ke Malang.');

      expect(targets(tester), ['Perjalanan']);
    });

    testWidgets('Pindahkan ke inside the area lists every Book', (
      tester,
    ) async {
      final kitchen = await store.createBook('Dapur');
      await store.createEntry(bookId: garden.id, text: 'Cabai berbunga.');
      await store.setBooksLocked([garden.id, kitchen.id], locked: true);
      await launch(tester);

      // The Locked Books after the others.
      await openArea(tester);
      await tapAndSettle(tester, find.text('Kebun'));
      await moveFrom(tester, 'Cabai berbunga.');
      expect(targets(tester), ['Perjalanan', 'Kebun', 'Dapur']);
    });

    testWidgets('the Trash gathers Locked Books in one row that opens '
        'through the prompt', (tester) async {
      final kitchen = await store.createBook('Dapur');
      final secret = await store.createEntry(
        bookId: garden.id,
        text: 'Rahasia kecil.',
      );
      final open = await store.createEntry(
        bookId: trips.id,
        text: 'Kereta ke Malang.',
      );
      await store.setBooksLocked([garden.id, kitchen.id], locked: true);
      await store.trashEntries([secret.id, open.id]);
      await store.trashBook(kitchen.id);
      await launch(tester);

      await go(tester, Routes.trashItems);

      expect(find.text('Kereta ke Malang.'), findsOneWidget);
      expect(find.text('2 item dari Book terkunci'), findsOneWidget);
      expect(find.text('Rahasia kecil.'), findsNothing);
      expect(find.text('Dapur'), findsNothing);

      await tapAndSettle(tester, find.text('2 item dari Book terkunci'));

      expect(platform.prompts, ['Buka Book terkunci']);
      expect(find.text('2 item dari Book terkunci'), findsNothing);
      expect(find.text('Rahasia kecil.'), findsOneWidget);
      expect(find.text('Dapur'), findsOneWidget);
      expect(platform.recentsHidden, isTrue);

      // Leaving the Trash locks them again.
      await tapAndSettle(tester, find.byType(BackButton));
      expect(areaOpen(tester), isFalse);
      await go(tester, Routes.trashItems);
      expect(find.text('2 item dari Book terkunci'), findsOneWidget);
      expect(find.text('Rahasia kecil.'), findsNothing);
    });

    testWidgets('a cancelled prompt keeps the Trash row', (tester) async {
      final secret = await store.createEntry(
        bookId: garden.id,
        text: 'Rahasia kecil.',
      );
      await store.setBooksLocked([garden.id], locked: true);
      await store.trashEntries([secret.id]);
      platform.answer = Unlock.cancelled;
      await launch(tester);
      await go(tester, Routes.trashItems);

      await tapAndSettle(tester, find.text('1 item dari Book terkunci'));

      expect(find.text('1 item dari Book terkunci'), findsOneWidget);
      expect(find.text('Rahasia kecil.'), findsNothing);
    });
  });
}
