import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/storage/storage_error_app.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the store error screen says nothing was deleted', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const StorageErrorApp());
    await tester.pumpAndSettle();

    expect(find.text('Kronoer tidak bisa dibuka'), findsOneWidget);
    expect(find.textContaining('tidak ada yang dihapus'), findsOneWidget);
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
}
