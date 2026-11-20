import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Each piece of text under [of] with the weight it is drawn in, after each
/// span inherits from the spans around it.
List<(String, FontWeight?)> textWeights(WidgetTester tester, Finder of) => [
  for (final rich in tester.widgetList<RichText>(
    find.descendant(of: of, matching: find.byType(RichText)),
  ))
    ...spanWeights(rich.text),
];

/// Turns on the system's Bold text setting, which the app reads through
/// [MediaQueryData.boldText].
void turnOnBoldText(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(boldText: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

List<(String, FontWeight?)> spanWeights(InlineSpan span, [TextStyle? parent]) {
  final style = parent?.merge(span.style) ?? span.style;
  return [
    if (span case TextSpan(:final text?) when text.isNotEmpty)
      (text, style?.fontWeight),
    if (span case TextSpan(:final children?))
      for (final child in children) ...spanWeights(child, style),
  ];
}
