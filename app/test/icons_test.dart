import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:vector_graphics/vector_graphics.dart';

const _cobalt = Color(0xFF2050D0);

Widget _host(Widget child, {IconThemeData theme = const IconThemeData()}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: IconTheme(data: theme, child: child),
    ),
  );
}

VectorGraphic _graphic(WidgetTester tester) =>
    tester.widget<VectorGraphic>(find.byType(VectorGraphic));

String _assetName(WidgetTester tester) =>
    (_graphic(tester).loader as AssetBytesLoader).assetName;

void main() {
  testWidgets('KIcon follows the surrounding IconTheme', (tester) async {
    await tester.pumpWidget(
      _host(
        const KIcon(KIcons.pen),
        theme: const IconThemeData(size: 20, color: _cobalt),
      ),
    );

    expect(tester.getSize(find.byType(KIcon)), const Size(20, 20));
    expect(
      _graphic(tester).colorFilter,
      const ColorFilter.mode(_cobalt, BlendMode.srcIn),
    );
    expect(_assetName(tester), 'assets/icons/stroke/pen.svg');
  });

  testWidgets('KIcon applies the IconTheme opacity', (tester) async {
    await tester.pumpWidget(
      _host(
        const KIcon(KIcons.pen),
        theme: const IconThemeData(color: _cobalt, opacity: 0.5),
      ),
    );

    expect(
      _graphic(tester).colorFilter,
      ColorFilter.mode(_cobalt.withValues(alpha: 0.5), BlendMode.srcIn),
    );
  });

  testWidgets('size and color arguments win over the IconTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const KIcon(KIcons.pen, size: 32, color: Color(0xFFA04114)),
        theme: const IconThemeData(size: 20, color: _cobalt),
      ),
    );

    expect(tester.getSize(find.byType(KIcon)), const Size(32, 32));
    expect(
      _graphic(tester).colorFilter,
      const ColorFilter.mode(Color(0xFFA04114), BlendMode.srcIn),
    );
  });

  testWidgets('filled uses the fill drawing', (tester) async {
    await tester.pumpWidget(_host(const KIcon(KIcons.pen, filled: true)));

    expect(_assetName(tester), 'assets/icons/fill/pen.svg');
  });

  testWidgets('semanticLabel is announced, otherwise the icon is silent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(const KIcon(KIcons.pen, semanticLabel: 'Tulis Entry')),
    );
    expect(find.bySemanticsLabel('Tulis Entry'), findsOneWidget);

    await tester.pumpWidget(_host(const KIcon(KIcons.pen)));
    expect(find.bySemanticsLabel('Tulis Entry'), findsNothing);

    semantics.dispose();
  });

  test('every KIcons value has a stroke and a fill file', () {
    for (final icon in KIcons.values) {
      for (final style in ['stroke', 'fill']) {
        expect(
          File('assets/icons/$style/${icon.file}.svg').existsSync(),
          isTrue,
          reason: '${icon.name}: assets/icons/$style/${icon.file}.svg',
        );
      }
    }
  });

  testWidgets('icons are bundled compiled, not as SVG text', (tester) async {
    final bytes = await tester.runAsync(
      () => rootBundle.load('assets/icons/stroke/pen.svg'),
    );

    // An SVG file starts with "<"; the compiled vector_graphics format does not.
    expect(bytes!.getUint8(0), isNot('<'.codeUnitAt(0)));
  });
}
