// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';
import 'dart:ui';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kronoer/main.dart';
import 'package:kronoer/src/rust/api/version.dart';
import 'package:kronoer/src/rust/frb_generated.dart';

String _hostLibraryPath() {
  final name = Platform.isWindows
      ? 'kronoer_bridge.dll'
      : Platform.isMacOS
      ? 'libkronoer_bridge.dylib'
      : 'libkronoer_bridge.so';
  return '../target/debug/$name';
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_hostLibraryPath()),
    );
  });

  testWidgets('shows the core versions of the rust', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const KronoerApp());
    await tester.pumpAndSettle();

    expect(find.text('Kronoer'), findsOneWidget);
    expect(find.text('core ${coreVersion()}'), findsOneWidget);
  });

  testWidgets('falls back to English on a non-Indonesian device', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const KronoerApp());
    await tester.pumpAndSettle();

    expect(find.text('A private place to write things down.'), findsOneWidget);
  });

  testWidgets('uses Indonesian on an Indonesian device', (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const KronoerApp());
    await tester.pumpAndSettle();

    expect(find.text('Tempat pribadi untuk mencatat.'), findsOneWidget);
  });
}
