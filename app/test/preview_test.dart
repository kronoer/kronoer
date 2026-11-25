import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/preview.dart';
import 'package:kronoer/src/settings/about_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/update/update_platform.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'fake_update_platform.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

void main() {
  late InMemoryStore store;

  setUp(() {
    store = InMemoryStore();
    PackageInfo.setMockInitialValues(
      appName: 'Kronoer',
      packageName: 'app.kronoer.preview',
      version: '0.1.0',
      buildNumber: '2001',
      buildSignature: '',
    );
  });
  tearDown(() => store.dispose());

  Future<void> pumpApp(
    WidgetTester tester, {
    required bool preview,
    bool started = false,
  }) async {
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isPreviewProvider.overrideWithValue(preview),
          updatePlatformProvider.overrideWithValue(FakeUpdatePlatform()),
          inMemoryStoreProvider.overrideWithValue(store),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(started)),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Welcome in Preview has the label', (tester) async {
    await pumpApp(tester, preview: true);

    expect(find.text('Preview'), findsOneWidget);
    expect(find.bySemanticsLabel(previewName), findsOneWidget);
  });

  testWidgets('Welcome in the stable app has no label', (tester) async {
    await pumpApp(tester, preview: false);

    expect(find.text('Preview'), findsNothing);
    expect(find.bySemanticsLabel('Kronoer'), findsOneWidget);
  });

  testWidgets('the Book list in Preview has the label', (tester) async {
    await store.createBook('Buku Saya');
    await pumpApp(tester, preview: true, started: true);

    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('About in Preview names it, without the build number', (
    tester,
  ) async {
    await pumpApp(tester, preview: true, started: true);
    await tester.tap(_kIcon(KIcons.settings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tentang Kronoer'), 100);
    // Built is not enough: bring it out from under the navigation bar.
    await tester.ensureVisible(find.text('Tentang Kronoer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentang Kronoer'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Kronoer Preview 0.1.0'), findsOneWidget);
    expect(find.textContaining('2001'), findsNothing);
  });
}
