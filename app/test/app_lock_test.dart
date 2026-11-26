import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/lock/lock_screen.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
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
  late DateTime now;

  setUp(() {
    store = InMemoryStore();
    platform = FakeAppLockPlatform();
    now = DateTime(2026, 11, 23, 10);
  });
  tearDown(() => store.dispose());

  Future<void> launch(
    WidgetTester tester, {
    AppLockSettings appLock = const AppLockSettings(),
  }) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
          appLockPlatformProvider.overrideWithValue(platform),
          clockProvider.overrideWithValue(() => now),
          savedSettingsProvider.overrideWithValue(
            SavedSettings(appLock: appLock),
          ),
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

  Future<void> openSettings(WidgetTester tester) =>
      tapAndSettle(tester, _kIcon(KIcons.settings));

  /// Kronoer goes to the background, as on Home.
  Future<void> leave(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  /// Kronoer comes back to the front.
  Future<void> comeBack(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  Switch appLockSwitch(WidgetTester tester) => tester.widget<Switch>(
    find.descendant(
      of: find.widgetWithText(ListTile, 'App lock'),
      matching: find.byType(Switch),
    ),
  );

  ListTile row(WidgetTester tester, String title) => tester.widget<ListTile>(
    find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
  );

  final lockScreen = find.byType(LockScreen);

  bool locked(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(KronoerApp)))
          .read(appLockProvider)
          .locked;

  group('Settings', () {
    testWidgets('turning App lock on asks for the device lock once', (
      tester,
    ) async {
      await launch(tester);
      await openSettings(tester);
      expect(appLockSwitch(tester).value, isFalse);
      expect(row(tester, 'Lock again').enabled, isFalse);

      await tapAndSettle(tester, find.text('App lock'));

      expect(platform.prompts, ['Turn on App lock']);
      expect(appLockSwitch(tester).value, isTrue);
      expect(row(tester, 'Lock again').enabled, isTrue);
      expect(find.text('After 1 minute in the background'), findsOneWidget);
      expect(platform.recentsHidden, isTrue);
      // Just given: no lock screen.
      expect(lockScreen, findsNothing);
    });

    testWidgets('a closed prompt leaves App lock off', (tester) async {
      platform.answer = Unlock.cancelled;
      await launch(tester);
      await openSettings(tester);

      await tapAndSettle(tester, find.text('App lock'));

      expect(platform.prompts, hasLength(1));
      expect(appLockSwitch(tester).value, isFalse);
    });

    testWidgets('turning it off asks too', (tester) async {
      await launch(tester, appLock: const AppLockSettings(on: true));
      expect(lockScreen, findsNothing, reason: 'unlocked on launch');
      await openSettings(tester);
      platform.prompts.clear();

      platform.answer = Unlock.cancelled;
      await tapAndSettle(tester, find.text('App lock'));
      expect(appLockSwitch(tester).value, isTrue);

      platform.answer = Unlock.unlocked;
      await tapAndSettle(tester, find.text('App lock'));
      expect(platform.prompts, ['Turn off App lock', 'Turn off App lock']);
      expect(appLockSwitch(tester).value, isFalse);
      expect(platform.recentsHidden, isFalse);
    });

    testWidgets('without a screen lock, says where to set one', (tester) async {
      platform.screenLock = false;
      await launch(tester);
      await openSettings(tester);

      expect(appLockSwitch(tester).onChanged, isNull);
      expect(row(tester, 'App lock').enabled, isFalse);
      expect(
        find.text('Set a screen lock on this phone first to use App lock'),
        findsOneWidget,
      );

      await tapAndSettle(tester, find.text('Open settings'));
      expect(platform.securityOpened, 1);

      // Set meanwhile: the box goes when Kronoer is back.
      platform.screenLock = true;
      await leave(tester);
      await comeBack(tester);
      expect(appLockSwitch(tester).onChanged, isNotNull);
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('on Android 8 to 12, says screenshots are blocked too', (
      tester,
    ) async {
      platform.blocks = true;
      await launch(tester);
      await openSettings(tester);

      expect(
        find.text(
          'On this Android version, screenshots of Kronoer are blocked too '
          'while the lock is on',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Lock again offers Immediately, 1 and 5 minutes, without asking',
      (tester) async {
        await launch(tester, appLock: const AppLockSettings(on: true));
        await openSettings(tester);
        platform.prompts.clear();

        await tapAndSettle(tester, find.text('Lock again'));
        expect(find.byType(LockAgainScreen), findsOneWidget);
        expect(
          find.textContaining('longer than this'),
          findsOneWidget,
          reason: 'the note',
        );
        expect(find.byType(Radio<LockAgain>), findsNWidgets(3));

        await tapAndSettle(tester, find.text('Immediately'));
        await tapAndSettle(tester, find.byType(BackButton));

        expect(find.text('Every time you leave Kronoer'), findsOneWidget);
        expect(platform.prompts, isEmpty);
      },
    );
  });

  group('lock screen', () {
    testWidgets('covers the app on launch and asks by itself', (tester) async {
      platform.answer = Unlock.cancelled;
      await launch(tester, appLock: const AppLockSettings(on: true));

      expect(lockScreen, findsOneWidget);
      expect(find.text('Kronoer is locked'), findsOneWidget);
      expect(find.byType(BookListScreen), findsNothing);
      expect(platform.prompts, ['Unlock Kronoer']);

      // Closed: it waits for the button.
      await tester.pumpAndSettle();
      expect(platform.prompts, hasLength(1));

      platform.answer = Unlock.unlocked;
      await tapAndSettle(tester, find.text('Unlock'));

      expect(platform.prompts, hasLength(2));
      expect(lockScreen, findsNothing);
      expect(find.byType(BookListScreen), findsOneWidget);
    });

    testWidgets('a moment away keeps it open; longer than 1 minute locks', (
      tester,
    ) async {
      await launch(tester, appLock: const AppLockSettings(on: true));
      expect(lockScreen, findsNothing);
      platform.prompts.clear();

      await leave(tester);
      now = now.add(const Duration(seconds: 59));
      await comeBack(tester);
      expect(lockScreen, findsNothing);
      expect(platform.prompts, isEmpty);

      platform.answer = Unlock.cancelled;
      await leave(tester);
      now = now.add(const Duration(minutes: 1));
      await comeBack(tester);
      expect(lockScreen, findsOneWidget);
      expect(platform.prompts, ['Unlock Kronoer']);
    });

    testWidgets('locks while away when the device keeps timers running', (
      tester,
    ) async {
      await launch(tester, appLock: const AppLockSettings(on: true));

      platform.answer = Unlock.cancelled;
      await leave(tester);
      await tester.pump(const Duration(minutes: 1));

      // No frames while away: locked already, drawn on the way back.
      expect(locked(tester), isTrue);
      await comeBack(tester);
      expect(lockScreen, findsOneWidget);
    });

    testWidgets('Immediately locks on leaving', (tester) async {
      await launch(
        tester,
        appLock: const AppLockSettings(
          on: true,
          lockAgain: LockAgain.immediately,
        ),
      );

      platform.answer = Unlock.cancelled;
      await leave(tester);
      expect(locked(tester), isTrue);
      await comeBack(tester);
      expect(lockScreen, findsOneWidget);
    });

    testWidgets('a clock turned back counts as away', (tester) async {
      await launch(tester, appLock: const AppLockSettings(on: true));
      platform.answer = Unlock.cancelled;

      await leave(tester);
      now = now.subtract(const Duration(hours: 1));
      await comeBack(tester);

      expect(lockScreen, findsOneWidget);
    });

    testWidgets('an own trip, such as the photo picker, is not time away', (
      tester,
    ) async {
      await launch(tester, appLock: const AppLockSettings(on: true));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KronoerApp)),
      );
      final picked = Completer<void>();
      final trip = container
          .read(appLockProvider.notifier)
          .ownTrip(() => picked.future);

      await leave(tester);
      now = now.add(const Duration(minutes: 10));
      await comeBack(tester);
      picked.complete();
      await trip;
      await tester.pumpAndSettle();

      expect(lockScreen, findsNothing);
    });

    testWidgets('back does nothing while locked', (tester) async {
      platform.answer = Unlock.cancelled;
      await launch(tester, appLock: const AppLockSettings(on: true));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KronoerApp)),
      );
      final router = container.read(routerProvider);
      router.go(Routes.theme);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, Routes.theme);
      expect(lockScreen, findsOneWidget);
    });

    testWidgets('unlocking returns to the screen that was open', (
      tester,
    ) async {
      await launch(tester, appLock: const AppLockSettings(on: true));
      await openSettings(tester);
      await tapAndSettle(tester, find.text('Theme'));

      platform.answer = Unlock.cancelled;
      await leave(tester);
      now = now.add(const Duration(minutes: 2));
      await comeBack(tester);
      expect(lockScreen, findsOneWidget);
      expect(find.byType(ThemeScreen), findsNothing);

      platform.answer = Unlock.unlocked;
      await tapAndSettle(tester, find.text('Unlock'));
      expect(find.byType(ThemeScreen), findsOneWidget);
    });
  });

  group('screen lock removed', () {
    testWidgets('App lock turns itself off and says so once', (tester) async {
      platform.screenLock = false;
      await launch(tester, appLock: const AppLockSettings(on: true));

      expect(lockScreen, findsNothing);
      expect(find.text('App lock turned off'), findsOneWidget);
      expect(platform.recentsHidden, isFalse);

      await tapAndSettle(tester, find.text('Settings').last);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(appLockSwitch(tester).value, isFalse);

      await leave(tester);
      await comeBack(tester);
      expect(find.text('App lock turned off'), findsNothing);
    });
  });

  group('suggestion on the Book list', () {
    const title = 'Lock Kronoer with your fingerprint?';
    final card = find.text(title);

    /// [count] Entries, spread over two Books; returns the first Book.
    Future<Book> write(int count) async {
      final books = [
        await store.createBook('Kebun'),
        await store.createBook('Dapur'),
      ];
      for (var i = 0; i < count; i++) {
        await store.createEntry(bookId: books[i % 2].id, text: 'Entry $i');
      }
      return books.first;
    }

    AppLockState lock(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(KronoerApp)))
            .read(appLockProvider);

    testWidgets('shows after the third Entry, across Books', (tester) async {
      final book = await write(2);
      await launch(tester);
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(card, findsNothing);

      await store.createEntry(bookId: book.id, text: 'Yang ketiga');
      await tester.pumpAndSettle();

      expect(card, findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
      // Above the Books.
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(find.text('Kebun')).dy),
      );
    });

    testWidgets('"Turn on" turns App lock on through the prompt', (
      tester,
    ) async {
      await write(3);
      await launch(tester);

      await tapAndSettle(tester, find.text('Turn on'));

      expect(platform.prompts, ['Turn on App lock']);
      expect(lock(tester).on, isTrue);
      expect(platform.recentsHidden, isTrue);
      // Not locked now: the user just gave the lock.
      expect(lockScreen, findsNothing);
      expect(card, findsNothing);

      await openSettings(tester);
      expect(appLockSwitch(tester).value, isTrue);
    });

    testWidgets('a cancelled prompt leaves the card', (tester) async {
      await write(3);
      platform.answer = Unlock.cancelled;
      await launch(tester);

      await tapAndSettle(tester, find.text('Turn on'));

      expect(platform.prompts, hasLength(1));
      expect(lock(tester).on, isFalse);
      expect(card, findsOneWidget);
    });

    testWidgets('Not now closes it for good', (tester) async {
      await write(3);
      await launch(tester);

      await tapAndSettle(tester, find.text('Not now'));

      expect(card, findsNothing);
      expect(platform.prompts, isEmpty);
      expect(lock(tester).on, isFalse);
      expect(lock(tester).suggested, isTrue);

      // As saved: a restart does not bring it back.
      await tester.pumpWidget(const SizedBox());
      await launch(tester, appLock: const AppLockSettings(suggested: true));
      expect(card, findsNothing);
    });

    testWidgets('not shown without a screen lock', (tester) async {
      await write(3);
      platform.screenLock = false;
      await launch(tester);

      expect(find.byType(BookListScreen), findsOneWidget);
      expect(card, findsNothing);
    });

    testWidgets('not shown while App lock is on', (tester) async {
      await write(3);
      // Unlocked by the prompt on launch.
      await launch(tester, appLock: const AppLockSettings(on: true));

      expect(lockScreen, findsNothing);
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(card, findsNothing);
    });

    testWidgets('not shown again after App lock is turned on in Settings '
        'and off again', (tester) async {
      await write(3);
      await launch(tester);
      expect(card, findsOneWidget);

      await openSettings(tester);
      await tapAndSettle(tester, find.text('App lock'));
      await tapAndSettle(tester, find.text('App lock'));
      expect(lock(tester).on, isFalse);

      await tapAndSettle(tester, _kIcon(KIcons.book));
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(card, findsNothing);
    });
  });
}
