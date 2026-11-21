import 'dart:math' as math;

import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/search/highlight.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:material_ui/material_ui.dart';

/// The system's monospace font; none is bundled.
const _monospace = 'monospace';

/// Monospace looks larger than the text around it at the same size.
const _monospaceScale = 0.9;

/// How Text styles look.
@immutable
class TextStyleLook {
  const TextStyleLook(this.scheme, {this.boldText = false});

  /// From the theme and the system's Bold text setting around [context].
  factory TextStyleLook.of(BuildContext context) => TextStyleLook(
    Theme.of(context).colorScheme,
    boldText: MediaQuery.boldTextOf(context),
  );

  final ColorScheme scheme;

  /// With the system's Bold text setting on, all text is already bold, so
  /// bold parts take a heavier weight to stand out.
  final bool boldText;

  /// Behind inline code and monospace blocks.
  Color get codeBackground => scheme.surfaceContainerHighest;

  /// The style of text with [styles], in text of [fontSize]; null with none.
  TextStyle? styleOf(Set<InlineStyle> styles, {double? fontSize}) {
    if (styles.isEmpty) return null;
    final code = styles.contains(InlineStyle.code);
    return TextStyle(
      fontWeight: styles.contains(InlineStyle.bold)
          ? (boldText ? FontWeight.w900 : FontWeight.w700)
          : null,
      fontStyle: styles.contains(InlineStyle.italic) ? FontStyle.italic : null,
      decoration: styles.contains(InlineStyle.strikethrough)
          ? TextDecoration.lineThrough
          : null,
      fontFamily: code ? _monospace : null,
      fontSize: code && fontSize != null ? fontSize * _monospaceScale : null,
      backgroundColor: code ? codeBackground : null,
    );
  }

  /// [runs] as one span, in text of [fontSize]. Parts of [matches], ranges in
  /// the text as written, are in [highlight].
  TextSpan span(
    List<StyledRun> runs, {
    double? fontSize,
    List<TextRange> matches = const [],
    TextStyle? highlight,
  }) {
    final children = <TextSpan>[];
    for (final run in runs) {
      final style = styleOf(run.styles, fontSize: fontSize);
      var at = run.start;
      void add(int end, [TextStyle? marked]) {
        if (end <= at) return;
        children.add(
          TextSpan(
            text: run.text.substring(at - run.start, end - run.start),
            style: marked == null ? style : (style?.merge(marked) ?? marked),
          ),
        );
        at = end;
      }

      if (highlight != null) {
        for (final match in matches) {
          final start = math.max(match.start, at);
          final end = math.min(match.end, run.end);
          if (end <= start) continue;
          add(start);
          add(end, highlight);
        }
      }
      add(run.end);
    }
    return TextSpan(children: children);
  }
}

/// An Entry's text as the read view shows it: its blocks, with their Text
/// styles and every part of [matches] highlighted.
///
/// The text that holds the first match gets [firstMatchKey], and
/// [onFirstMatch] learns where the match is in that text as shown.
class EntryText extends StatelessWidget {
  const EntryText(
    this.blocks, {
    this.matches = const [],
    this.firstMatchKey,
    this.onFirstMatch,
    super.key,
  });

  final List<TextBlock> blocks;

  /// Ranges in the text as written, in order.
  final List<TextRange> matches;

  final GlobalKey? firstMatchKey;
  final void Function(TextRange shown)? onFirstMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = TextStyleLook.of(context);
    final base = theme.extension<EntryTextStyles>()!.entryBody;
    final highlight = highlightStyle(scheme);
    final first = matches.firstOrNull;
    var keyed = false;

    Widget text(List<StyledRun> runs, {TextStyle? style}) {
      final textStyle = style ?? base;
      Key? key;
      if (!keyed &&
          first != null &&
          runs.any(
            (run) => run.start <= first.start && first.start < run.end,
          )) {
        keyed = true;
        key = firstMatchKey;
        onFirstMatch?.call(
          TextRange(
            start: shownOffset(runs, first.start),
            end: shownOffset(runs, first.end),
          ),
        );
      }
      return Text.rich(
        look.span(
          runs,
          fontSize: textStyle.fontSize,
          matches: matches,
          highlight: highlight,
        ),
        key: key,
        style: textStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.l,
      children: [
        for (final block in blocks)
          switch (block) {
            ParagraphBlock(:final runs) => text(runs),
            QuoteBlock(:final runs) => DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: scheme.outlineVariant, width: 3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: Space.m),
                child: text(
                  runs,
                  style: base.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            ListBlock(:final items) => Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              children: [
                for (final (i, item) in items.indexed)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: Text(
                          item.marker,
                          textAlign: TextAlign.end,
                          style: base.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i < items.length - 1 ? Space.xs : 0,
                        ),
                        child: text(item.runs),
                      ),
                    ],
                  ),
              ],
            ),
            CodeBlock(:final run) => DecoratedBox(
              decoration: BoxDecoration(
                color: look.codeBackground,
                borderRadius: BorderRadius.circular(Radii.s),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.m,
                  vertical: Space.s,
                ),
                child: text(
                  [run],
                  style: base.copyWith(
                    fontFamily: _monospace,
                    fontSize: base.fontSize! * _monospaceScale,
                  ),
                ),
              ),
            ),
          },
      ],
    );
  }
}
