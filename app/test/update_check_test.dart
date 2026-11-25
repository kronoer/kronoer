import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/preview.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/update/update_check.dart';
import 'package:kronoer/src/update/update_platform.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'fake_app_lock_platform.dart';
import 'fake_update_platform.dart';

const _installed = '0.1.0';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Version', () {
    test('reads a tag or a version, and nothing else', () {
      expect(Version.tryParse('v0.2.0'), const Version(0, 2, 0));
      expect(Version.tryParse('1.10.3'), const Version(1, 10, 3));
      for (final text in ['', 'v0.2', '0.2.0-rc.1', 'v01.2.0', 'latest']) {
        expect(Version.tryParse(text), isNull, reason: text);
      }
    });

    test('compares part by part', () {
      expect(const Version(0, 10, 0) > const Version(0, 9, 9), isTrue);
      expect(const Version(1, 0, 0) > const Version(0, 99, 99), isTrue);
      expect(const Version(0, 1, 1) > const Version(0, 1, 1), isFalse);
    });
  });

  test('newestPreview takes published, tagged pre-releases only', () {
    expect(
      newestPreview([
        {'tag_name': 'v0.9.0', 'draft': true, 'prerelease': true},
        {'tag_name': 'v1.0.0', 'draft': false, 'prerelease': false},
        {'tag_name': 'nightly', 'draft': false, 'prerelease': true},
        ...releases(['v0.2.0', 'v0.10.0', 'v0.3.0']),
        'not a release',
      ]),
      const Version(0, 10, 0),
    );
    expect(newestPreview(<Object?>[]), isNull);
    expect(newestPreview({'message': 'Not Found'}), isNull);
  });

  test('a check is due a day after the last, or when the clock went back', () {
    final last = DateTime(2026, 11, 25, 9);
    expect(updateCheckDue(last, null), isTrue);
    expect(updateCheckDue(last.add(const Duration(hours: 23)), last), isFalse);
    expect(updateCheckDue(last.add(const Duration(days: 1)), last), isTrue);
    expect(
      updateCheckDue(last.subtract(const Duration(minutes: 1)), last),
      isTrue,
    );
  });

  test('updateToOffer: newer than installed and than Nanti, while on', () {
    const installed = Version(0, 1, 0);
    const next = Version(0, 2, 0);
    Version? offer(UpdateCheck check) =>
        updateToOffer(check, installed: installed);

    expect(offer(const UpdateCheck(found: next)), next);
    expect(offer(const UpdateCheck(found: installed)), isNull);
    expect(offer(const UpdateCheck(on: false, found: next)), isNull);
    expect(offer(const UpdateCheck(found: next, later: next)), isNull);
    expect(
      offer(const UpdateCheck(found: Version(0, 3, 0), later: next)),
      const Version(0, 3, 0),
    );
    expect(
      updateToOffer(const UpdateCheck(found: next), installed: null),
      isNull,
    );
  });

  group('the check', () {
    late FakeUpdatePlatform platform;
    late DateTime now;
    final start = DateTime(2026, 11, 25, 9);

    setUp(() {
      platform = FakeUpdatePlatform()..answer = releases(['v0.2.0']);
      now = start;
    });

    ProviderContainer make({
      bool preview = true,
      UpdateCheck saved = const UpdateCheck(),
    }) => ProviderContainer.test(
      overrides: [
        isPreviewProvider.overrideWithValue(preview),
        updatePlatformProvider.overrideWithValue(platform),
        clockProvider.overrideWithValue(() => now),
        savedSettingsProvider.overrideWithValue(
          SavedSettings(updateCheck: saved),
        ),
        packageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'Kronoer',
            packageName: 'app.kronoer.preview',
            version: _installed,
            buildNumber: '2001',
          ),
        ),
      ],
    );

    Future<ProviderContainer> opened({
      bool preview = true,
      UpdateCheck saved = const UpdateCheck(),
    }) async {
      final container = make(preview: preview, saved: saved);
      container.read(updateCheckProvider);
      await pumpEventQueue();
      return container;
    }

    test('asks once when the app opens, and at most once a day', () async {
      final container = await opened();
      expect(platform.fetched, 1);
      expect(platform.userAgent, 'KronoerPreview/$_installed');
      expect(container.read(updateCheckProvider).found, const Version(0, 2, 0));
      expect(container.read(updateCheckProvider).checked, start);
      expect(container.read(updateOfferProvider), const Version(0, 2, 0));

      final notifier = container.read(updateCheckProvider.notifier);
      now = start.add(const Duration(hours: 23, minutes: 59));
      await notifier.checkIfDue();
      expect(platform.fetched, 1);

      now = start.add(const Duration(days: 1));
      platform.answer = releases(['v0.3.0', 'v0.2.0']);
      await notifier.checkIfDue();
      expect(platform.fetched, 2);
      expect(container.read(updateOfferProvider), const Version(0, 3, 0));
    });

    test('a saved check from today waits for tomorrow', () async {
      await opened(
        saved: UpdateCheck(checked: start.subtract(const Duration(hours: 2))),
      );
      expect(platform.fetched, 0);
    });

    test('a failed check shows nothing and waits for the next day', () async {
      platform.error = const SocketException('No connection');
      final container = await opened();
      expect(platform.fetched, 1);
      expect(container.read(updateCheckProvider).checked, start);
      expect(container.read(updateCheckProvider).found, isNull);
      expect(container.read(updateOfferProvider), isNull);

      final notifier = container.read(updateCheckProvider.notifier);
      platform.error = null;
      now = start.add(const Duration(hours: 12));
      await notifier.checkIfDue();
      expect(platform.fetched, 1);

      now = start.add(const Duration(days: 1));
      await notifier.checkIfDue();
      expect(platform.fetched, 2);
      expect(container.read(updateOfferProvider), const Version(0, 2, 0));
    });

    test('an answer that is not a list of releases finds nothing', () async {
      platform.answer = {'message': 'API rate limit exceeded'};
      final container = await opened(
        saved: const UpdateCheck(found: Version(0, 2, 0)),
      );
      expect(platform.fetched, 1);
      // What it found before stays.
      expect(container.read(updateCheckProvider).found, const Version(0, 2, 0));
    });

    test('the stable app never asks, nor offers', () async {
      final container = await opened(
        preview: false,
        saved: const UpdateCheck(found: Version(0, 2, 0)),
      );
      await container.read(updateCheckProvider.notifier).checkIfDue();
      expect(platform.fetched, 0);
      expect(container.read(updateOfferProvider), isNull);
    });

    test('off, it does not ask; on again, it asks when due', () async {
      final container = await opened(saved: const UpdateCheck(on: false));
      expect(platform.fetched, 0);

      container.read(updateCheckProvider.notifier).setOn(true);
      await pumpEventQueue();
      expect(platform.fetched, 1);
      expect(container.read(updateOfferProvider), const Version(0, 2, 0));

      container.read(updateCheckProvider.notifier).setOn(false);
      expect(container.read(updateOfferProvider), isNull);
    });
  });

  group('on the Book list', () {
    final written = DateTime(2026, 10, 1, 9);
    late InMemoryStore store;
    late DateTime now;
    late FakeAppLockPlatform lock;
    late FakeUpdatePlatform platform;

    setUp(() {
      store = InMemoryStore(clock: () => written);
      lock = FakeAppLockPlatform()..screenLock = false;
      platform = FakeUpdatePlatform()..answer = releases(['v0.2.0']);
      now = written.add(const Duration(days: 1));
      PackageInfo.setMockInitialValues(
        appName: 'Kronoer',
        packageName: 'app.kronoer.preview',
        version: _installed,
        buildNumber: '2001',
        buildSignature: '',
      );
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
      bool preview = true,
    }) async {
      tester.platformDispatcher.localesTestValue = [const Locale('id')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryStoreProvider.overrideWithValue(store),
            hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
            appLockPlatformProvider.overrideWithValue(lock),
            clockProvider.overrideWithValue(() => now),
            isPreviewProvider.overrideWithValue(preview),
            updatePlatformProvider.overrideWithValue(platform),
          ],
          child: const KronoerApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookListScreen), findsOneWidget);
      return ProviderScope.containerOf(tester.element(find.byType(KronoerApp)));
    }

    const title = 'Kronoer Preview 0.2.0 tersedia';

    testWidgets('Unduh opens the release page; Nanti waits for a newer one', (
      tester,
    ) async {
      await write(1);
      final container = await launch(tester);

      expect(find.text(title), findsOneWidget);
      expect(
        find.text(
          'Unduh dari GitHub, lalu pasang di atas yang sekarang. '
          'Tulisanmu tetap ada.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Unduh'));
      await tester.pumpAndSettle();
      expect(platform.opened, [
        Uri.parse('https://github.com/kronoer/kronoer/releases/tag/v0.2.0'),
      ]);
      // Still there until it is installed or put off.
      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text('Nanti'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
      expect(container.read(updateCheckProvider).later, const Version(0, 2, 0));

      // The next day, the same version stays hidden; a newer one does not.
      now = now.add(const Duration(days: 1));
      await container.read(updateCheckProvider.notifier).checkIfDue();
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);

      now = now.add(const Duration(days: 1));
      platform.answer = releases(['v0.3.0']);
      await container.read(updateCheckProvider.notifier).checkIfDue();
      await tester.pumpAndSettle();
      expect(find.text('Kronoer Preview 0.3.0 tersedia'), findsOneWidget);
    });

    testWidgets('without a browser, Unduh says so', (tester) async {
      platform.browser = false;
      await write(1);
      await launch(tester);

      await tester.tap(find.text('Unduh'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tidak ada browser untuk membuka GitHub'),
        findsOneWidget,
      );
    });

    testWidgets(
      'one banner at a time: Export, then the update, then App lock',
      (tester) async {
        lock.screenLock = true;
        await write(3);
        now = written.add(const Duration(days: 31));
        await launch(tester);

        expect(find.text('Belum pernah ekspor'), findsOneWidget);
        expect(find.text(title), findsNothing);
        expect(find.text('Kunci Kronoer pakai sidik jari?'), findsNothing);

        await tester.tap(find.text('Nanti'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text('Kunci Kronoer pakai sidik jari?'), findsNothing);

        await tester.tap(find.text('Nanti'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing);
        expect(find.text('Kunci Kronoer pakai sidik jari?'), findsOneWidget);
      },
    );

    testWidgets('Cek versi baru in Settings turns the check and banner off', (
      tester,
    ) async {
      await write(1);
      final container = await launch(tester);
      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Cek versi baru'), 100);
      // Built is not enough: bring it out from under the navigation bar.
      await tester.ensureVisible(find.text('Cek versi baru'));
      await tester.pumpAndSettle();
      expect(find.text('Sekali sehari, ke GitHub'), findsOneWidget);
      await tester.tap(find.text('Cek versi baru'));
      await tester.pumpAndSettle();
      expect(container.read(updateCheckProvider).on, isFalse);

      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
    });

    testWidgets('the stable app has neither the banner nor the switch', (
      tester,
    ) async {
      await write(1);
      await launch(tester, preview: false);
      expect(platform.fetched, 0);
      expect(find.text(title), findsNothing);

      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Tentang Kronoer'), 100);
      // Built is not enough: bring it out from under the navigation bar.
      await tester.ensureVisible(find.text('Tentang Kronoer'));
      await tester.pumpAndSettle();
      expect(find.text('Cek versi baru'), findsNothing);
    });
  });
}
