import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/storage/storage_error_app.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the store error screen says nothing was deleted', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const StorageErrorApp());
    await tester.pumpAndSettle();

    expect(find.text('Kronoer can\'t open'), findsOneWidget);
    expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    expect(find.byType(ButtonStyleButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('it falls back to English', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const StorageErrorApp());
    await tester.pumpAndSettle();

    expect(find.text("Kronoer can't open"), findsOneWidget);
  });

  testWidgets('it follows the saved theme and language', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      const StorageErrorApp(
        settings: SavedSettings(
          themeMode: ThemeMode.dark,
          language: LanguageChoice.indonesian,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kronoer tidak bisa dibuka'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
  });
}
