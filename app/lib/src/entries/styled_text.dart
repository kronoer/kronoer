import 'package:kronoer/src/entries/text_styles.dart';
import 'package:material_ui/material_ui.dart';

/// How Text styles look: turns [StyledRun]s into spans, with search matches
/// laid over them.
class TextStyleSpans {
  const TextStyleSpans(this.scheme, {this.boldText = false});

  /// For the theme and Bold text setting around [context].
  factory TextStyleSpans.of(BuildContext context) => TextStyleSpans(
    Theme.of(context).colorScheme,
    boldText: MediaQuery.boldTextOf(context),
  );

  final ColorScheme scheme;

  /// Whether the system's Bold text setting is on. All text is bold then, so
  /// bold parts are bolder still.
  final bool boldText;

  /// The faint background of monospace text.
  Color get codeBackground => scheme.surfaceContainerHighest;

  /// Monospace text, a little smaller than text of [fontSize] so it looks
  /// as big.
  TextStyle monospace({double? fontSize}) => TextStyle(
    fontFamily: 'monospace',
    fontSize: fontSize == null ? null : fontSize * 0.88,
  );

  TextStyle _style(Set<InlineStyle> styles, double? fontSize) =>
      TextStyle(
        fontWeight: styles.contains(InlineStyle.bold)
            ? (boldText ? FontWeight.w900 : FontWeight.w700)
            : null,
        fontStyle: styles.contains(InlineStyle.italic)
            ? FontStyle.italic
            : null,
        decoration: styles.contains(InlineStyle.strikethrough)
            ? TextDecoration.lineThrough
            : null,
      ).merge(
        styles.contains(InlineStyle.code)
            ? monospace(fontSize: fontSize)
                  .copyWith(backgroundColor: codeBackground)
            : null,
      );

  /// [runs] as one span. [fontSize] is the size of the text around them, for
  /// monospace parts. Each part of a run inside one of [matches], ranges in
  /// the text as written, is in [highlight].
  TextSpan span(
    List<StyledRun> runs, {
    double? fontSize,
    List<TextRange> matches = const [],
    TextStyle? highlight,
  }) {
    final children = <TextSpan>[];
    for (final run in runs) {
      final style = run.styles.isEmpty ? null : _style(run.styles, fontSize);
      var at = run.start;
      for (final match in matches) {
        if (highlight == null) break;
        final start = match.start.clamp(run.start, run.end);
        final end = match.end.clamp(run.start, run.end);
        if (end <= start || start < at) continue;
        if (start > at) {
          children.add(TextSpan(text: _part(run, at, start), style: style));
        }
        children.add(
          TextSpan(
            text: _part(run, start, end),
            style: style?.merge(highlight) ?? highlight,
          ),
        );
        at = end;
      }
      if (at < run.end) {
        children.add(TextSpan(text: _part(run, at, run.end), style: style));
      }
    }
    return TextSpan(children: children);
  }

  static String _part(StyledRun run, int start, int end) =>
      run.text.substring(start - run.start, end - run.start);
}
