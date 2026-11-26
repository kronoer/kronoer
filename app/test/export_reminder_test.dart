import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/export/export_reminder.dart';
import 'package:kronoer/src/export/export_screen.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_app_lock_platform.dart';

void main() {
  group('exportReminderAt', () {
    final first = DateTime(2026, 10, 1, 9);
    const two = ExportActivity(createdSince: 2);

    ExportReminder? at(
      DateTime now, {
      DateTime? lastExport,
      ExportActivity activity = two,
      DateTime? later,
    }) => exportReminderAt(
      now,
      lastExport: lastExport,
      activity: ExportActivity(
        firstCreated: activity.firstCreated ?? first,
        createdSince: activity.createdSince,
      ),
      later: later,
    );

    test('30 days after the last Export, with Entries since', () {
      final exported = DateTime(2026, 10, 10, 20);
      expect(
        at(exported.add(const Duration(days: 29)), lastExport: exported),
        isNull,
      );
      expect(
        at(exported.add(const Duration(days: 30)), lastExport: exported),
        const ExportReminder(exported: true, days: 30, newEntryCount: 2),
      );
      expect(
        at(exported.add(const Duration(days: 45)), lastExport: exported),
        const ExportReminder(exported: true, days: 45, newEntryCount: 2),
      );
      // Nothing new since: the Archive is whole.
      expect(
        at(
          exported.add(const Duration(days: 90)),
          lastExport: exported,
          activity: const ExportActivity(),
        ),
        isNull,
      );
    });

    test('without an Export, 30 days from the first Entry', () {
      expect(at(first.add(const Duration(days: 29))), isNull);
      expect(
        at(first.add(const Duration(days: 30))),
        const ExportReminder(exported: false, days: 30, newEntryCount: 2),
      );
      expect(
        exportReminderAt(
          first.add(const Duration(days: 300)),
          lastExport: null,
          activity: const ExportActivity(),
        ),
        isNull,
        reason: 'no Entry',
      );
    });

    test('Later hides it for 7 days', () {
      final now = first.add(const Duration(days: 40));
      expect(at(now, later: now), isNull);
      expect(
        at(now.add(const Duration(days: 6, hours: 23)), later: now),
        isNull,
      );
      expect(at(now.add(const Duration(days: 7)), later: now), isNotNull);
    });
  });

  group('on the Book list', () {
    final written = DateTime(2026, 10, 1, 9);
    late InMemoryStore store;
    late DateTime now;
    late FakeAppLockPlatform platform;

    setUp(() {
      store = InMemoryStore(clock: () => written);
      platform = FakeAppLockPlatform()..screenLock = false;
      now = written.add(const Duration(days: 31));
    });
    tearDown(() => store.dispose());

    Future<void> write(int count) async {
      final book = await store.createBook('Kebun');
      for (var i = 0; i < count; i++) {
        await store.createEntry(bookId: book.id, text: 'Entry $i');
      }
    }

    Future<ProviderContainer> launch(
      WidgetTester tester, {
      DateTime? lastExport,
      DateTime? later,
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
              SavedSettings(lastExport: lastExport, exportReminderLater: later),
            ),
          ],
          child: const KronoerApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookListScreen), findsOneWidget);
      return ProviderScope.containerOf(tester.element(find.byType(KronoerApp)));
    }

    const keep =
        ' Keep a copy so nothing is lost if your phone breaks or goes missing.';

    testWidgets('30 days after the last Export; Export opens the page', (
      tester,
    ) async {
      await write(2);
      await launch(
        tester,
        lastExport: written.subtract(const Duration(days: 2)),
      );

      expect(find.text('33 days without an export'), findsOneWidget);
      expect(
        find.text('2 new Entries since your last export.$keep'),
        findsOneWidget,
      );
      // Above the Books.
      expect(
        tester.getTopLeft(find.text('33 days without an export')).dy,
        lessThan(tester.getTopLeft(find.text('Kebun')).dy),
      );

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.byType(ExportScreen), findsOneWidget);

      // Its way out leads back to the Book list.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BookListScreen), findsOneWidget);
    });

    testWidgets('not before 30 days, nor without new Entries', (tester) async {
      await write(2);
      final exported = written.subtract(const Duration(days: 1));
      now = exported.add(const Duration(days: 29, hours: 23));
      await launch(tester, lastExport: exported);
      expect(find.text('Export'), findsNothing);

      // Every Entry was created before this Export.
      await tester.pumpWidget(const SizedBox());
      now = written.add(const Duration(days: 90));
      await launch(tester, lastExport: written.add(const Duration(hours: 1)));
      expect(find.text('Export'), findsNothing);
    });

    testWidgets('without an Export, 30 days from the first Entry', (
      tester,
    ) async {
      await write(1);
      now = written.add(const Duration(days: 29));
      await launch(tester);
      expect(find.text('No export yet'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      now = written.add(const Duration(days: 30));
      await launch(tester);
      expect(find.text('No export yet'), findsOneWidget);
      expect(
        find.text('It\'s been 30 days since your first Entry.$keep'),
        findsOneWidget,
      );
    });

    testWidgets('Later hides it for 7 days, as saved', (tester) async {
      await write(2);
      final container = await launch(tester);
      expect(find.text('No export yet'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('No export yet'), findsNothing);
      expect(container.read(exportReminderLaterProvider), now);

      final later = now;
      await tester.pumpWidget(const SizedBox());
      now = later.add(const Duration(days: 6));
      await launch(tester, later: later);
      expect(find.text('No export yet'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      now = later.add(const Duration(days: 7));
      await launch(tester, later: later);
      expect(find.text('No export yet'), findsOneWidget);
    });

    testWidgets('the App lock card waits for it', (tester) async {
      platform.screenLock = true;
      await write(3);
      await launch(tester);

      expect(find.text('No export yet'), findsOneWidget);
      expect(find.text('Lock Kronoer with your fingerprint?'), findsNothing);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('No export yet'), findsNothing);
      expect(find.text('Lock Kronoer with your fingerprint?'), findsOneWidget);
    });
  });
}
