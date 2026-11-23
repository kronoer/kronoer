import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/reminder/reminder_platform.dart';
import 'package:kronoer/src/reminder/writing_reminder.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

/// A device that records what is scheduled and answers as told.
class FakeReminderPlatform implements ReminderPlatform {
  bool allowed = true;

  /// What asking to notify answers; asking also allows when true.
  bool grants = true;
  int asked = 0;
  int settingsOpened = 0;
  ReminderSchedule? scheduled;
  VoidCallback? opened;

  @override
  Future<bool> notificationsAllowed() async => allowed;

  @override
  Future<bool> requestPermission() async {
    asked++;
    if (grants) allowed = true;
    return grants;
  }

  @override
  Future<void> schedule(ReminderSchedule schedule) async =>
      scheduled = schedule;

  @override
  Future<void> cancel() async => scheduled = null;

  @override
  Future<void> openNotificationSettings() async => settingsOpened++;

  @override
  void onOpened(VoidCallback opened) => this.opened = opened;
}

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eight = TimeOfDay(hour: 20, minute: 0);

  group('the next reminder', () {
    test('is today when the time is still ahead', () {
      expect(
        nextReminder(now: DateTime(2026, 11, 23, 9), time: eight),
        DateTime(2026, 11, 23, 20),
      );
    });

    test('is tomorrow when the time is past or now', () {
      expect(
        nextReminder(now: DateTime(2026, 11, 23, 21), time: eight),
        DateTime(2026, 11, 24, 20),
      );
      expect(
        nextReminder(now: DateTime(2026, 11, 23, 20), time: eight),
        DateTime(2026, 11, 24, 20),
      );
    });

    test('crosses months and years by the calendar', () {
      expect(
        nextReminder(now: DateTime(2026, 12, 31, 22), time: eight),
        DateTime(2027, 1, 1, 20),
      );
    });

    test('is tomorrow when today is skipped', () {
      expect(
        nextReminder(
          now: DateTime(2026, 11, 23, 9),
          time: eight,
          skipped: DateTime(2026, 11, 23),
        ),
        DateTime(2026, 11, 24, 20),
      );
    });

    test('a skipped day that is gone does not matter', () {
      expect(
        nextReminder(
          now: DateTime(2026, 11, 23, 9),
          time: eight,
          skipped: DateTime(2026, 11, 22),
        ),
        DateTime(2026, 11, 23, 20),
      );
    });
  });

  group('skipping', () {
    final now = DateTime(2026, 11, 23, 15);

    test('skips today once an Entry was created today', () {
      expect(
        skippedDay(
          now: now,
          lastEntryCreated: DateTime(2026, 11, 23, 0, 5),
          skipIfWritten: true,
        ),
        DateTime(2026, 11, 23),
      );
    });

    test('skips nothing when it is off', () {
      expect(
        skippedDay(
          now: now,
          lastEntryCreated: DateTime(2026, 11, 23, 8),
          skipIfWritten: false,
        ),
        isNull,
      );
    });

    test('an Entry created yesterday, or none, skips nothing', () {
      expect(
        skippedDay(
          now: now,
          lastEntryCreated: DateTime(2026, 11, 22, 23, 59),
          skipIfWritten: true,
        ),
        isNull,
      );
      expect(
        skippedDay(now: now, lastEntryCreated: null, skipIfWritten: true),
        isNull,
      );
    });
  });

  group('the notifier', () {
    late FakeReminderPlatform platform;
    late DateTime now;

    ProviderContainer container({
      WritingReminder reminder = const WritingReminder(),
      DateTime? lastEntryCreated,
    }) {
      final container = ProviderContainer(
        overrides: [
          reminderPlatformProvider.overrideWithValue(platform),
          clockProvider.overrideWithValue(() => now),
          savedSettingsProvider.overrideWithValue(
            SavedSettings(
              language: LanguageChoice.indonesian,
              writingReminder: reminder,
              lastEntryCreated: lastEntryCreated,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      platform = FakeReminderPlatform();
      now = DateTime(2026, 11, 23, 9);
    });

    test('turning it on asks, then schedules today at 20.00', () async {
      final c = container();
      final notifier = c.read(writingReminderProvider.notifier);

      expect(await notifier.turnOn(), isTrue);

      expect(platform.asked, 1);
      expect(c.read(writingReminderProvider).on, isTrue);
      expect(platform.scheduled?.first, DateTime(2026, 11, 23, 20));
      expect(platform.scheduled?.time, eight);
      expect(platform.scheduled?.skipped, isNull);
      expect(platform.scheduled?.text, 'Apa yang terjadi hari ini?');
    });

    test('denied, it stays off and says where to allow it', () async {
      platform
        ..allowed = false
        ..grants = false;
      final c = container();

      expect(await c.read(writingReminderProvider.notifier).turnOn(), isFalse);

      final reminder = c.read(writingReminderProvider);
      expect(reminder.on, isFalse);
      expect(reminder.blocked, isTrue);
      expect(platform.scheduled, isNull);
    });

    test('a time already past today comes first tomorrow', () async {
      final c = container(reminder: const WritingReminder(on: true));
      await c
          .read(writingReminderProvider.notifier)
          .setTime(const TimeOfDay(hour: 8, minute: 30));
      expect(platform.scheduled?.first, DateTime(2026, 11, 24, 8, 30));
    });

    test('an Entry created today drops today when skipping', () async {
      final c = container(
        reminder: const WritingReminder(on: true, skipIfWritten: true),
      );
      final notifier = c.read(writingReminderProvider.notifier);
      await notifier.sync();
      expect(platform.scheduled?.first, DateTime(2026, 11, 23, 20));

      now = DateTime(2026, 11, 23, 15);
      await notifier.entryCreated();

      expect(platform.scheduled?.first, DateTime(2026, 11, 24, 20));
      expect(platform.scheduled?.skipped, DateTime(2026, 11, 23));
    });

    test('opening the app on a day already written keeps it skipped', () async {
      final c = container(
        reminder: const WritingReminder(on: true, skipIfWritten: true),
        lastEntryCreated: DateTime(2026, 11, 23, 7),
      );
      await c.read(writingReminderProvider.notifier).sync();
      expect(platform.scheduled?.first, DateTime(2026, 11, 24, 20));
    });

    test('without skipping, an Entry changes nothing', () async {
      final c = container(reminder: const WritingReminder(on: true));
      final notifier = c.read(writingReminderProvider.notifier);
      await notifier.sync();
      await notifier.entryCreated();
      expect(platform.scheduled?.first, DateTime(2026, 11, 23, 20));
    });

    test('a language change reschedules it in that language', () async {
      final c = container(reminder: const WritingReminder(on: true));
      await c.read(writingReminderProvider.notifier).sync();

      c.read(languageProvider.notifier).pick(LanguageChoice.english);
      await pumpEventQueue();

      expect(platform.scheduled?.text, 'What happened today?');
    });

    test('turning it off cancels it', () async {
      final c = container(reminder: const WritingReminder(on: true));
      final notifier = c.read(writingReminderProvider.notifier);
      await notifier.sync();
      await notifier.turnOff();
      expect(platform.scheduled, isNull);
      expect(c.read(writingReminderProvider).on, isFalse);
    });

    test('notifications turned off on the device show as blocked', () async {
      final c = container(reminder: const WritingReminder(on: true));
      platform.allowed = false;
      await c.read(writingReminderProvider.notifier).sync();
      expect(c.read(writingReminderProvider).blocked, isTrue);

      platform.allowed = true;
      await c.read(writingReminderProvider.notifier).sync();
      expect(c.read(writingReminderProvider).blocked, isFalse);
    });
  });

  group('Settings', () {
    late InMemoryStore store;
    late FakeReminderPlatform platform;

    setUp(() {
      store = InMemoryStore();
      platform = FakeReminderPlatform();
    });
    tearDown(() => store.dispose());

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openSettings(
      WidgetTester tester, {
      WritingReminder reminder = const WritingReminder(),
    }) async {
      tester.platformDispatcher.localesTestValue = [const Locale('id')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryStoreProvider.overrideWithValue(store),
            hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
            reminderPlatformProvider.overrideWithValue(platform),
            savedSettingsProvider.overrideWithValue(
              SavedSettings(writingReminder: reminder),
            ),
          ],
          child: const KronoerApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, _kIcon(KIcons.settings));
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Lewati kalau sudah menulis'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
    }

    ListTile row(WidgetTester tester, String title) => tester.widget<ListTile>(
      find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    );

    Switch switchOf(WidgetTester tester, String title) => tester.widget<Switch>(
      find.descendant(
        of: find.widgetWithText(ListTile, title),
        matching: find.byType(Switch),
      ),
    );

    testWidgets('has the reminder, its time, and skipping, off at first', (
      tester,
    ) async {
      await openSettings(tester);

      expect(find.text('Pengingat'), findsOneWidget);
      expect(
        find.text('Notifikasi harian untuk mulai menulis'),
        findsOneWidget,
      );
      expect(
        find.text('20.00 · bisa terlambat beberapa menit'),
        findsOneWidget,
      );
      expect(
        find.text('Tidak muncul di hari kamu sudah menulis Entry'),
        findsOneWidget,
      );
      expect(switchOf(tester, 'Pengingat menulis').value, isFalse);
      expect(row(tester, 'Jam').enabled, isFalse);
      expect(row(tester, 'Lewati kalau sudah menulis').enabled, isFalse);
      expect(switchOf(tester, 'Lewati kalau sudah menulis').value, isFalse);
    });

    testWidgets('turning it on enables the time and skipping', (tester) async {
      await openSettings(tester);

      await tapAndSettle(tester, find.text('Pengingat menulis'));

      expect(platform.asked, 1);
      expect(switchOf(tester, 'Pengingat menulis').value, isTrue);
      expect(row(tester, 'Jam').enabled, isTrue);
      expect(row(tester, 'Lewati kalau sudah menulis').enabled, isTrue);
      expect(platform.scheduled, isNotNull);

      await tapAndSettle(tester, find.text('Lewati kalau sudah menulis'));
      expect(switchOf(tester, 'Lewati kalau sudah menulis').value, isTrue);
    });

    testWidgets('denied, the switch goes back off and points to the device', (
      tester,
    ) async {
      platform
        ..allowed = false
        ..grants = false;
      await openSettings(tester);

      await tapAndSettle(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Pengingat menulis'),
          matching: find.byType(Switch),
        ),
      );

      expect(switchOf(tester, 'Pengingat menulis').value, isFalse);
      expect(
        find.text('Izinkan notifikasi Kronoer di pengaturan perangkat'),
        findsOneWidget,
      );
      expect(row(tester, 'Jam').enabled, isFalse);

      await tapAndSettle(tester, find.text('Buka pengaturan'));
      expect(platform.settingsOpened, 1);
    });

    testWidgets('the time opens a picker, and the picked time shows', (
      tester,
    ) async {
      await openSettings(tester, reminder: const WritingReminder(on: true));

      await tapAndSettle(tester, find.text('Jam'));
      expect(find.text('Jam pengingat'), findsOneWidget);

      // Typed rather than dialed.
      await tapAndSettle(tester, find.byIcon(Icons.keyboard_outlined));
      final fields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '21');
      await tester.enterText(fields.at(1), '30');
      await tapAndSettle(tester, find.text('OKE'));

      expect(
        find.text('21.30 · bisa terlambat beberapa menit'),
        findsOneWidget,
      );
      expect(platform.scheduled?.time, const TimeOfDay(hour: 21, minute: 30));
    });
  });
}
