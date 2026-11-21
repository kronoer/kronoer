import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/rust/api/store.dart' as core;
import 'package:kronoer/src/search/search.dart';
import 'package:material_ui/material_ui.dart';

/// How a matching word looks, in a result and in the read view.
TextStyle highlightStyle(ColorScheme scheme) => TextStyle(
  backgroundColor: scheme.primaryContainer,
  color: scheme.onPrimaryContainer,
);

/// A snippet as one line of text, like an Entry card's, with its Text styles
/// in [look] and each match in [highlight]. The markers around the matches
/// are never shown; a pair of marks the snippet cuts in half shows as written.
TextSpan snippetSpan(
  String snippet,
  TextStyle highlight,
  TextStyleLook look, {
  double? fontSize,
}) {
  final text = StringBuffer();
  final matches = <TextRange>[];
  int? start;
  for (final character in snippet.split('')) {
    if (character == matchStart) {
      start = text.length;
    } else if (character == matchEnd) {
      if (start != null) matches.add(TextRange(start: start, end: text.length));
      start = null;
    } else {
      text.write(character);
    }
  }
  if (start != null) matches.add(TextRange(start: start, end: text.length));

  return look.span(
    previewRuns(text.toString()),
    fontSize: fontSize,
    matches: matches,
    highlight: highlight,
  );
}

/// Where a search for [query] matches [text], by the core's own rules, so the
/// read view marks exactly the words the search found. Empty when not every
/// word of [query] matches.
List<TextRange> matchesIn(String text, String query) => [
  for (final range in core.matchRanges(text: text, query: query))
    TextRange(start: range.start, end: range.end),
];
