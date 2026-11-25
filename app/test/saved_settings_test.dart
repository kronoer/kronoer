import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/launch.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/reminder/writing_reminder.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/update/update_check.dart';
import 'package:kronoer/src/welcome/welcome_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'core_test_store.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  late TestStore store;
  late SharedPreferencesAsync preferences;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    store = await TestStore.open();
  });

  tearDown(() => store.close());

  /// Starts the app the way `main.dart` does, from what is saved and what the
  /// store holds. Starting it again is a restart: nothing in memory is kept.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    final overrides = (await tester.runAsync(() async {
      final saved = await SavedSettings.load(preferences);
      return launchOverrides(
        store: store.store,
        preferences: preferences,
        saved: saved,
      );
    }))!;
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const KronoerApp()),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await settleCore(tester);
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settle(tester);
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  Future<void> addBook(WidgetTester tester, String name) async {
    await tester.runAsync(() => store.repository.createBook(name));
  }

  void onDevice(WidgetTester tester, Locale locale) {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }

  testWidgets('theme and language survive a restart, from the first frame', (
    tester,
  ) async {
    onDevice(tester, const Locale('id'));
    await addBook(tester, 'Kebun');
    await launch(tester);
    await settle(tester);

    await tapAndSettle(tester, _kIcon(KIcons.settings));
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tapAndSettle(tester, find.text('Tema'));
    await tapAndSettle(tester, find.text('Gelap'));
    // A choice page stays open after a pick.
    await tapAndSettle(tester, find.byType(BackButton));
    await tapAndSettle(tester, find.text('Bahasa'));
    await tapAndSettle(tester, find.text('English'));

    await launch(tester);
    // The very first frame, before anything else loads.
    expect(app(tester).themeMode, ThemeMode.dark);
    expect(app(tester).locale, const Locale('en'));

    await settle(tester);
    expect(find.byType(BookListScreen), findsOneWidget);
    expect(find.text('New Book'), findsOneWidget);
  });

  testWidgets('a first launch shows Welcome and saves nothing', (tester) async {
    onDevice(tester, const Locale('id'));
    await launch(tester);
    await settle(tester);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(app(tester).themeMode, ThemeMode.system);
    expect(app(tester).locale, isNull);
    expect(await preferences.getBool('has_started'), isNull);
  });

  testWidgets('starting from Welcome is saved', (tester) async {
    onDevice(tester, const Locale('id'));
    await launch(tester);
    await settle(tester);

    await tapAndSettle(tester, find.text('Yuk, mulai cerita'));
    expect(
      await tester.runAsync(() => preferences.getBool('has_started')),
      isTrue,
    );
  });

  testWidgets('an install from before the flag, with Books, has started', (
    tester,
  ) async {
    onDevice(tester, const Locale('id'));
    await addBook(tester, 'Kebun');
    await launch(tester);
    await settle(tester);

    expect(find.byType(BookListScreen), findsOneWidget);
    expect(await preferences.getBool('has_started'), isTrue);
  });

  testWidgets('after the last Book is deleted, a restart shows the empty '
      'Book list, not Welcome', (tester) async {
    onDevice(tester, const Locale('id'));
    await launch(tester);
    await settle(tester);
    await tapAndSettle(tester, find.text('Yuk, mulai cerita'));

    final books = (await tester.runAsync(store.store.listBooks))!;
    for (final book in books) {
      await tester.runAsync(
        () => store.repository.deleteForever(bookIds: [book.id]),
      );
    }

    await launch(tester);
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(BookListScreen), findsOneWidget);
    expect(find.text('Belum ada Book'), findsOneWidget);
  });

  group('loading', () {
    test('nothing saved gives the defaults', () async {
      final saved = await SavedSettings.load(preferences);

      expect(saved.themeMode, ThemeMode.system);
      expect(saved.language, LanguageChoice.device);
      expect(saved.hasStarted, isNull);
      expect(saved.writingReminder, const WritingReminder());
      expect(saved.writingReminder.time, const TimeOfDay(hour: 20, minute: 0));
      expect(saved.lastEntryCreated, isNull);
      expect(saved.appLock, const AppLockSettings());
      expect(saved.appLock.lockAgain, LockAgain.oneMinute);
      expect(saved.appLock.suggested, isFalse);
      expect(saved.updateCheck, const UpdateCheck());
      expect(saved.updateCheck.on, isTrue);
    });

    test('unknown or wrongly typed values give the defaults', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'theme_mode': 'purple',
            'language': 3,
            'has_started': 'yes',
            'writing_reminder': 'on',
            'writing_reminder_time': 24 * 60,
            'writing_reminder_skip': 1,
            'last_entry_created': 'today',
            'app_lock': 'yes',
            'lock_again': 'never',
            'app_lock_suggested': 'yes',
            'update_check': 'no',
            'update_checked': 'yesterday',
            'update_found': 'next',
            'update_later': 2,
          });
      final saved = await SavedSettings.load(SharedPreferencesAsync());

      expect(saved.themeMode, ThemeMode.system);
      expect(saved.language, LanguageChoice.device);
      expect(saved.hasStarted, isNull);
      expect(saved.writingReminder, const WritingReminder());
      expect(saved.lastEntryCreated, isNull);
      expect(saved.appLock, const AppLockSettings());
      expect(saved.updateCheck, const UpdateCheck());
    });

    test('saved values are read back', () async {
      await saveThemeMode(preferences, ThemeMode.light);
      await saveLanguage(preferences, LanguageChoice.indonesian);
      await saveHasStarted(preferences);
      await saveWritingReminder(
        preferences,
        const WritingReminder(
          on: true,
          time: TimeOfDay(hour: 6, minute: 45),
          skipIfWritten: true,
          // Not saved.
          blocked: true,
        ),
      );
      final created = DateTime(2026, 11, 23, 15, 4);
      await saveLastEntryCreated(preferences, created);
      await saveAppLock(
        preferences,
        const AppLockSettings(
          on: true,
          lockAgain: LockAgain.fiveMinutes,
          suggested: true,
        ),
      );
      final checked = DateTime(2026, 11, 25, 8, 30);
      await saveUpdateCheck(
        preferences,
        UpdateCheck(
          on: false,
          checked: checked,
          found: const Version(0, 2, 0),
          later: const Version(0, 1, 1),
        ),
      );
      final saved = await SavedSettings.load(preferences);

      expect(saved.themeMode, ThemeMode.light);
      expect(saved.language, LanguageChoice.indonesian);
      expect(saved.hasStarted, isTrue);
      expect(
        saved.writingReminder,
        const WritingReminder(
          on: true,
          time: TimeOfDay(hour: 6, minute: 45),
          skipIfWritten: true,
        ),
      );
      expect(saved.lastEntryCreated, created);
      expect(
        saved.appLock,
        const AppLockSettings(
          on: true,
          lockAgain: LockAgain.fiveMinutes,
          suggested: true,
        ),
      );
      expect(
        saved.updateCheck,
        UpdateCheck(
          on: false,
          checked: checked,
          found: const Version(0, 2, 0),
          later: const Version(0, 1, 1),
        ),
      );
    });
  });
}
