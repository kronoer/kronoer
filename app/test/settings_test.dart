import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/licenses.dart';
import 'package:kronoer/src/rust/api/version.dart';
import 'package:kronoer/src/settings/about_screen.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  late InMemoryStore store;

  setUpAll(registerLicenses);
  setUp(() {
    store = InMemoryStore();
    PackageInfo.setMockInitialValues(
      appName: 'Kronoer',
      packageName: 'app.kronoer',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() => store.dispose());

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(
    WidgetTester tester, {
    Locale locale = const Locale('id'),
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tapAndSettle(tester, _kIcon(KIcons.settings));
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  Brightness brightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

  /// [title] in the app bar, not on the tab of the same name.
  Finder appBarTitle(String title) =>
      find.descendant(of: find.byType(AppBar), matching: find.text(title));

  ListTile row(WidgetTester tester, String title) => tester.widget<ListTile>(
    find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
  );

  group('Settings', () {
    testWidgets('has the four sections', (tester) async {
      await openSettings(tester);

      for (final section in ['Keamanan', 'Tampilan', 'Data', 'Tentang']) {
        await tester.scrollUntilVisible(find.text(section), 100);
        expect(find.text(section), findsOneWidget);
      }
    });

    testWidgets('security and data rows are disabled', (tester) async {
      await openSettings(tester);

      for (final title in ['Kunci aplikasi', 'Kunci lagi', 'Ekspor', 'Impor']) {
        await tester.scrollUntilVisible(find.text(title), 100);
        expect(row(tester, title).enabled, isFalse, reason: title);
      }
      for (final title in ['Tema', 'Bahasa', 'Tentang Kronoer']) {
        await tester.scrollUntilVisible(find.text(title), 100);
        expect(row(tester, title).enabled, isTrue, reason: title);
      }
    });
  });

  group('theme', () {
    testWidgets('follows the system until one is picked', (tester) async {
      await openSettings(tester);
      expect(find.text('Ikuti sistem'), findsOneWidget);
      expect(brightness(tester), Brightness.light);
    });

    testWidgets('Gelap turns the app dark at once; the page stays open', (
      tester,
    ) async {
      await openSettings(tester);

      await tapAndSettle(tester, find.text('Tema'));
      expect(find.byType(ThemeScreen), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));

      await tapAndSettle(tester, find.text('Gelap'));

      expect(find.byType(ThemeScreen), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>))
            .groupValue,
        ThemeMode.dark,
      );
      expect(brightness(tester), Brightness.dark);

      await tapAndSettle(tester, find.byType(BackButton));
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Gelap'), findsOneWidget);
    });

    testWidgets('Terang keeps it light on a dark device', (tester) async {
      await openSettings(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);

      await tapAndSettle(tester, find.text('Tema'));
      await tapAndSettle(tester, find.text('Terang'));

      expect(brightness(tester), Brightness.light);
    });
  });

  group('language', () {
    testWidgets('English changes the app at once', (tester) async {
      await openSettings(tester);

      await tapAndSettle(tester, find.text('Bahasa'));
      expect(find.byType(LanguageScreen), findsOneWidget);
      // "Ikuti perangkat", with the device's language under it.
      expect(find.text('Ikuti perangkat'), findsOneWidget);
      expect(find.text('Bahasa Indonesia'), findsNWidgets(2));

      await tapAndSettle(tester, find.text('English'));

      // The page stays open, already in English.
      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Follow device'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(appBarTitle('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);

      // Settings is a tab: back goes to the Book tab.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.text('New Book'), findsOneWidget);
    });

    testWidgets('Bahasa Indonesia on an English device', (tester) async {
      await openSettings(tester, locale: const Locale('en'));
      expect(appBarTitle('Settings'), findsOneWidget);

      await tapAndSettle(tester, find.text('Language'));
      await tapAndSettle(tester, find.text('Bahasa Indonesia'));

      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.text('Ikuti perangkat'), findsOneWidget);

      await tapAndSettle(tester, find.byType(BackButton));
      expect(appBarTitle('Pengaturan'), findsOneWidget);
    });
  });

  group('About', () {
    testWidgets('shows the version, the core, and the privacy note', (
      tester,
    ) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Tentang Kronoer'), 100);

      await tapAndSettle(tester, find.text('Tentang Kronoer'));

      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text('Versi 0.1.0 (1)'), findsOneWidget);
      expect(find.text('core ${coreVersion()}'), findsOneWidget);
      expect(find.text('Data kamu hanya ada di perangkat ini'), findsOneWidget);
    });

    testWidgets('the licenses page lists Keyline and no fonts', (tester) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Tentang Kronoer'), 100);
      await tapAndSettle(tester, find.text('Tentang Kronoer'));

      await tester.scrollUntilVisible(find.text('Lisensi open source'), 100);
      await tester.tap(find.text('Lisensi open source'));
      // The license page reads the license texts outside the fake clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LicensesScreen), findsOneWidget);
      final list = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Keyline Icons'),
        200,
        scrollable: list,
      );
      expect(find.text('Keyline Icons'), findsOneWidget);

      // Text uses the system font: no font is bundled, so none is listed
      // anywhere on the page, top to bottom.
      const fonts = ['Literata', 'Marck Script', 'Plus Jakarta Sans'];
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(0);
      await tester.pump();
      while (true) {
        for (final font in fonts) {
          expect(find.text(font), findsNothing, reason: font);
        }
        if (position.pixels >= position.maxScrollExtent) break;
        position.jumpTo(position.pixels + 300);
        await tester.pump();
      }
    });
  });
}
