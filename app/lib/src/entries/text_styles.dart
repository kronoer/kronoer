import 'package:flutter/foundation.dart';

// Text styles: marks typed in an Entry's text that change how parts of it
// look when shown. The text keeps the marks as written; only showing it reads
// them. The rules are in `spec/entry-format.md`.

/// A style that a pair of marks gives the text between them.
enum InlineStyle { bold, italic, strikethrough, code }

const _inlineMarks = {
  '*': InlineStyle.bold,
  '_': InlineStyle.italic,
  '~': InlineStyle.strikethrough,
  '`': InlineStyle.code,
};

/// A piece of shown text with one set of styles, and where it sits in the
/// text as written, so ranges found in that text (search matches) can be laid
/// over it.
@immutable
class StyledRun {
  const StyledRun(this.text, this.start, [this.styles = const {}]);

  final String text;

  /// Where [text] starts in the text as written.
  final int start;

  final Set<InlineStyle> styles;

  int get end => start + text.length;

  @override
  bool operator ==(Object other) =>
      other is StyledRun &&
      other.text == text &&
      other.start == start &&
      setEquals(other.styles, styles);

  @override
  int get hashCode => Object.hash(text, start, Object.hashAllUnordered(styles));

  @override
  String toString() =>
      'StyledRun(${[text, start, ...styles.map((s) => s.name)].join(', ')})';
}

/// One block of an Entry's text, in the order shown.
@immutable
sealed class TextBlock {
  const TextBlock();
}

/// Lines with no line mark, up to a blank line or another kind of block. Its
/// lines are joined by runs of `\n`.
final class ParagraphBlock extends TextBlock {
  const ParagraphBlock(this.runs);

  final List<StyledRun> runs;

  @override
  bool operator ==(Object other) =>
      other is ParagraphBlock && listEquals(other.runs, runs);

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'ParagraphBlock($runs)';
}

/// Lines starting with `> `, joined by runs of `\n`, without their marks.
final class QuoteBlock extends TextBlock {
  const QuoteBlock(this.runs);

  final List<StyledRun> runs;

  @override
  bool operator ==(Object other) =>
      other is QuoteBlock && listEquals(other.runs, runs);

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'QuoteBlock($runs)';
}

/// Consecutive list items.
final class ListBlock extends TextBlock {
  const ListBlock(this.items);

  final List<ListItem> items;

  @override
  bool operator ==(Object other) =>
      other is ListBlock && listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);

  @override
  String toString() => 'ListBlock($items)';
}

/// One list item: [marker] is [bullet] for `- ` and `* `, or the number as
/// typed followed by a period, as in `12.`.
@immutable
class ListItem {
  const ListItem(this.marker, this.runs);

  static const bullet = '•';

  final String marker;
  final List<StyledRun> runs;

  @override
  bool operator ==(Object other) =>
      other is ListItem &&
      other.marker == marker &&
      listEquals(other.runs, runs);

  @override
  int get hashCode => Object.hash(marker, Object.hashAll(runs));

  @override
  String toString() => 'ListItem($marker, $runs)';
}

/// The text between a pair of ```` ``` ````, as written: nothing in it is
/// styled.
final class CodeBlock extends TextBlock {
  const CodeBlock(this.run);

  final StyledRun run;

  @override
  bool operator ==(Object other) => other is CodeBlock && other.run == run;

  @override
  int get hashCode => run.hashCode;

  @override
  String toString() => 'CodeBlock($run)';
}

final _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _numbered = RegExp(r'^(\d+)\. ');

bool _isWord(String character) => _wordCharacter.hasMatch(character);

bool _isSpace(String character) => character.trim().isEmpty;

/// The blocks of [text], an Entry's text as written.
List<TextBlock> parseTextStyles(String text) {
  final blocks = <TextBlock>[];
  var from = 0;
  var search = 0;
  while (true) {
    final open = text.indexOf('```', search);
    final close = open < 0 ? -1 : text.indexOf('```', open + 3);
    if (close < 0) break;

    // One newline right inside each fence belongs to the fence.
    var start = open + 3;
    var end = close;
    if (start < end && text[start] == '\n') start++;
    if (end > start && text[end - 1] == '\n') end--;
    if (text.substring(start, end).trim().isEmpty) {
      // An empty pair is text as written.
      search = close + 3;
      continue;
    }

    _addLines(text, from, open, blocks);
    blocks.add(CodeBlock(StyledRun(text.substring(start, end), start)));
    from = search = close + 3;
  }
  _addLines(text, from, text.length, blocks);
  return blocks;
}

/// Adds the blocks of the lines in `text[from..to)`.
void _addLines(String text, int from, int to, List<TextBlock> blocks) {
  // Each line with where it starts, and where its shown text starts.
  final paragraph = <(int, (int, String))>[];
  final quote = <(int, (int, String))>[];
  final items = <ListItem>[];

  // Lines are joined by the line break that ends the line before.
  List<StyledRun> joined(List<(int, (int, String))> lines) => [
    for (final (i, (lineStart, (start, line))) in lines.indexed) ...[
      if (i > 0) StyledRun('\n', lineStart - 1),
      ...parseInline(line, start: start),
    ],
  ];

  void endParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(ParagraphBlock(joined(paragraph)));
    paragraph.clear();
  }

  void endQuote() {
    if (quote.isEmpty) return;
    blocks.add(QuoteBlock(joined(quote)));
    quote.clear();
  }

  void endList() {
    if (items.isEmpty) return;
    blocks.add(ListBlock([...items]));
    items.clear();
  }

  /// `text[start..end)` without the spaces around it, with where it starts.
  (int, String) trimmed(int start, int end) {
    final part = text.substring(start, end);
    final inner = part.trim();
    return (start + part.indexOf(inner), inner);
  }

  var start = from;
  while (start <= to) {
    var end = text.indexOf('\n', start);
    if (end < 0 || end > to) end = to;
    final line = text.substring(start, end);

    if (line.trim().isEmpty) {
      endParagraph();
      endQuote();
      endList();
    } else if (line.startsWith('> ')) {
      endParagraph();
      endList();
      quote.add((start, trimmed(start + 2, end)));
    } else if (line.startsWith('- ') || line.startsWith('* ')) {
      endParagraph();
      endQuote();
      final (at, content) = trimmed(start + 2, end);
      items.add(ListItem(ListItem.bullet, parseInline(content, start: at)));
    } else if (_numbered.firstMatch(line) case final number?) {
      endParagraph();
      endQuote();
      final (at, content) = trimmed(start + number.end, end);
      items.add(ListItem('${number[1]}.', parseInline(content, start: at)));
    } else {
      endQuote();
      endList();
      paragraph.add((start, trimmed(start, end)));
    }
    start = end + 1;
  }
  endParagraph();
  endQuote();
  endList();
}

/// The inline styles of [text], one line that starts at [start] in the text
/// as written. Every run also has [styles].
List<StyledRun> parseInline(
  String text, {
  int start = 0,
  Set<InlineStyle> styles = const {},
}) {
  final runs = <StyledRun>[];
  var plainFrom = 0;
  void addPlain(int to) {
    if (to > plainFrom) {
      runs.add(
        StyledRun(text.substring(plainFrom, to), start + plainFrom, styles),
      );
    }
  }

  var i = 0;
  while (i < text.length) {
    final style = _inlineMarks[text[i]];
    final close = style == null ? -1 : _closingMark(text, i);
    if (close < 0) {
      i++;
      continue;
    }
    addPlain(i);
    final inner = text.substring(i + 1, close);
    final innerStyles = {...styles, style!};
    if (style == InlineStyle.code) {
      runs.add(StyledRun(inner, start + i + 1, innerStyles));
    } else {
      runs.addAll(
        parseInline(inner, start: start + i + 1, styles: innerStyles),
      );
    }
    i = plainFrom = close + 1;
  }
  addPlain(text.length);
  return runs;
}

/// Where the mark that closes the one at [open] is, or -1 when the mark at
/// [open] opens nothing.
///
/// An opening mark is at the start or after a space or punctuation, and is
/// followed by a character that is not a space. A closing mark follows a
/// character that is not a space, and is at the end or before a space or
/// punctuation.
int _closingMark(String text, int open) {
  final mark = text[open];
  if (open > 0 && _isWord(text[open - 1])) return -1;
  if (open + 1 >= text.length || _isSpace(text[open + 1])) return -1;
  for (var j = open + 2; j < text.length; j++) {
    if (text[j] != mark || _isSpace(text[j - 1])) continue;
    if (j + 1 < text.length && _isWord(text[j + 1])) continue;
    return j;
  }
  return -1;
}

/// [text] as one line of styled runs, for a card or a search snippet: list
/// items keep their bullet or number, line marks go, and every run of spaces
/// and line breaks is one space.
///
/// Every shown character keeps its place in [text], so ranges found in it
/// (search matches) can be laid over the runs: a bullet sits over the mark it
/// replaces, and a space over the first character of the spaces it replaces.
List<StyledRun> previewRuns(String text) {
  final preview = <StyledRun>[];
  void addPiece(String shown, int start, Set<InlineStyle> styles) {
    if (shown == ' ' && (preview.isEmpty || preview.last.text.endsWith(' '))) {
      return;
    }
    // Pieces that follow each other in [text] stay one run.
    final last = preview.lastOrNull;
    if (last != null && last.end == start && setEquals(last.styles, styles)) {
      preview[preview.length - 1] = StyledRun(
        last.text + shown,
        last.start,
        styles,
      );
    } else {
      preview.add(StyledRun(shown, start, styles));
    }
  }

  void add(StyledRun run) {
    var from = 0;
    for (final space in RegExp(r'\s+').allMatches(run.text)) {
      if (space.start > from) {
        addPiece(
          run.text.substring(from, space.start),
          run.start + from,
          run.styles,
        );
      }
      addPiece(' ', run.start + space.start, run.styles);
      from = space.end;
    }
    if (from < run.text.length) {
      addPiece(run.text.substring(from), run.start + from, run.styles);
    }
  }

  // A space between blocks and list items sits over the line break that
  // ends the line holding [at].
  void spaceAfter(int at) {
    final end = text.indexOf('\n', at);
    add(StyledRun(' ', end < 0 ? text.length : end));
  }

  for (final block in parseTextStyles(text)) {
    switch (block) {
      case ParagraphBlock(:final runs) || QuoteBlock(:final runs):
        runs.forEach(add);
        if (runs.isNotEmpty) spaceAfter(runs.last.end);
      case ListBlock(:final items):
        for (final item in items) {
          if (item.runs.isEmpty) continue;
          // The bullet or number sits over the mark it stands for, which
          // starts its line and is as long.
          final line = text.lastIndexOf('\n', item.runs.first.start - 1) + 1;
          add(StyledRun('${item.marker} ', line));
          item.runs.forEach(add);
          spaceAfter(item.runs.last.end);
        }
      case CodeBlock(:final run):
        add(StyledRun(run.text, run.start, const {InlineStyle.code}));
        spaceAfter(run.end);
    }
  }

  if (preview.lastOrNull case final last?) {
    preview.removeLast();
    final shown = last.text.trimRight();
    if (shown.isNotEmpty) {
      preview.add(StyledRun(shown, last.start, last.styles));
    }
  }
  return preview;
}

/// Where [offset], a place in the text as written, falls in the text [runs]
/// show. A place inside a mark falls where the next shown text starts.
int shownOffset(List<StyledRun> runs, int offset) {
  var shown = 0;
  for (final run in runs) {
    if (offset <= run.start) return shown;
    if (offset < run.end) return shown + offset - run.start;
    shown += run.text.length;
  }
  return shown;
}
