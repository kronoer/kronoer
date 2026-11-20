import 'package:kronoer/src/rust/api/store.dart' as core;
import 'package:kronoer/src/search/search.dart';
import 'package:material_ui/material_ui.dart';

/// How a matching word looks, in a result and in the read view.
TextStyle highlightStyle(ColorScheme scheme) => TextStyle(
  backgroundColor: scheme.primaryContainer,
  color: scheme.onPrimaryContainer,
);

/// A snippet as one line of text with each match in [highlight]. The markers
/// around the matches are never shown.
TextSpan snippetSpan(String snippet, TextStyle highlight) {
  final text = snippet.replaceAll(RegExp(r'\s+'), ' ').trim();
  final children = <TextSpan>[];
  var rest = text;
  while (rest.isNotEmpty) {
    final start = rest.indexOf(matchStart);
    if (start < 0) {
      children.add(TextSpan(text: rest.replaceAll(matchEnd, '')));
      break;
    }
    if (start > 0) children.add(TextSpan(text: rest.substring(0, start)));
    final end = rest.indexOf(matchEnd, start);
    final stop = end < 0 ? rest.length : end;
    children.add(
      TextSpan(text: rest.substring(start + 1, stop), style: highlight),
    );
    rest = stop < rest.length ? rest.substring(stop + 1) : '';
  }
  return TextSpan(children: children);
}

/// Where a search for [query] matches [text], by the core's own rules, so the
/// read view marks exactly the words the search found. Empty when not every
/// word of [query] matches.
List<TextRange> matchesIn(String text, String query) => [
  for (final range in core.matchRanges(text: text, query: query))
    TextRange(start: range.start, end: range.end),
];

/// [text], which starts at [offset] in the text [matches] refer to, with every
/// match in [highlight].
TextSpan highlightedSpan(
  String text,
  List<TextRange> matches,
  TextStyle highlight, {
  int offset = 0,
}) {
  final children = <TextSpan>[];
  var at = 0;
  for (final match in matches) {
    final start = (match.start - offset).clamp(0, text.length);
    final end = (match.end - offset).clamp(0, text.length);
    if (end <= start) continue;
    if (start > at) children.add(TextSpan(text: text.substring(at, start)));
    children.add(TextSpan(text: text.substring(start, end), style: highlight));
    at = end;
  }
  if (at < text.length) children.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: children);
}
