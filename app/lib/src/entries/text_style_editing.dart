import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:material_ui/material_ui.dart';

// Text styles while writing: the editor shows the text as written, marks and
// all, styled by the same parser as the read view, and the selection menu
// adds or removes marks. The rules are in `spec/entry-format.md`.

/// A style that marks at the start of a line give it.
enum LineStyle { bullet, numbered, quote }

const _inlineMark = {
  InlineStyle.bold: '*',
  InlineStyle.italic: '_',
  InlineStyle.strikethrough: '~',
  InlineStyle.code: '`',
};

const _fence = '```';

final _bulletMark = RegExp(r'^[-*] ');
final _numberMark = RegExp(r'^(\d+)\. ');
final _quoteMark = RegExp(r'^> ');
final _anyLineMark = RegExp(r'^(?:[-*] |\d+\. |> )');
final _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

RegExp _markOf(LineStyle style) => switch (style) {
  LineStyle.bullet => _bulletMark,
  LineStyle.numbered => _numberMark,
  LineStyle.quote => _quoteMark,
};

bool _isWord(String character) => _wordCharacter.hasMatch(character);

bool _isSpace(String character) => character.trim().isEmpty;

/// Shows an Entry's text as written with its Text styles, the marks dimmed.
class StyledTextController extends TextEditingController {
  StyledTextController({super.text});

  String? _parsed;
  var _runs = <(StyledRun, bool)>[];

  /// The shown runs of [text], each with whether it is in a quote.
  List<(StyledRun, bool)> _runsOf(String text) {
    if (_parsed == text) return _runs;
    _parsed = text;
    return _runs = [
      for (final block in parseTextStyles(text))
        ...switch (block) {
          ParagraphBlock(:final runs) => [for (final run in runs) (run, false)],
          QuoteBlock(:final runs) => [for (final run in runs) (run, true)],
          ListBlock(:final items) => [
            for (final item in items)
              for (final run in item.runs) (run, false),
          ],
          CodeBlock(:final run) => [
            (StyledRun(run.text, run.start, const {InlineStyle.code}), false),
          ],
        },
    ];
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final look = TextStyleLook.of(context);
    final scheme = look.scheme;
    final fontSize = style?.fontSize;
    final mark = TextStyle(color: scheme.outline);
    final quote = TextStyle(color: scheme.onSurfaceVariant);

    // Every character, in pieces of one style: the shown text in its
    // styles, and everything else (the marks) dimmed.
    final pieces = <(int, int, TextStyle?)>[];
    var at = 0;
    void piece(int end, TextStyle? style) {
      if (end <= at) return;
      pieces.add((at, end, style));
      at = end;
    }

    for (final (run, inQuote) in _runsOf(text)) {
      piece(run.start, mark);
      final styled = look.styleOf(run.styles, fontSize: fontSize);
      piece(run.end, inQuote ? quote.merge(styled) : styled);
    }
    piece(text.length, mark);

    // The word being composed is underlined, as in any text field.
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final children = <TextSpan>[];
    for (final (start, end, style) in pieces) {
      final cuts = {
        start,
        if (composing.start > start && composing.start < end) composing.start,
        if (composing.end > start && composing.end < end) composing.end,
        end,
      }.toList();
      for (var i = 0; i + 1 < cuts.length; i++) {
        final (from, to) = (cuts[i], cuts[i + 1]);
        final composed = from >= composing.start && to <= composing.end;
        children.add(
          TextSpan(
            text: text.substring(from, to),
            style: composed
                ? (style ?? const TextStyle()).copyWith(
                    decoration: TextDecoration.combine([
                      ?style?.decoration,
                      TextDecoration.underline,
                    ]),
                  )
                : style,
          ),
        );
      }
    }
    return TextSpan(style: style, children: children);
  }
}

/// Builds a new text from an old one, edit by edit, in order.
class _Edits {
  _Edits(this.text);

  final String text;
  final _out = StringBuffer();
  var _from = 0;

  /// Copies the old text up to [at]; returns where [at] lands in the new
  /// text.
  int copyTo(int at) {
    _out.write(text.substring(_from, at));
    _from = at;
    return _out.length;
  }

  void insert(int at, String inserted) {
    copyTo(at);
    _out.write(inserted);
  }

  void delete(int at, int length) => replace(at, length, '');

  void replace(int at, int length, String inserted) {
    copyTo(at);
    _out.write(inserted);
    _from = at + length;
  }

  String finish() {
    copyTo(text.length);
    return _out.toString();
  }
}

/// The lines [selection] touches, as (start, end) without their line breaks.
/// A selection that ends at the start of a line does not touch that line.
List<(int, int)> _linesTouched(String text, TextSelection selection) {
  final start = selection.start;
  var end = selection.end;
  if (end > start && text[end - 1] == '\n') end--;
  final lines = <(int, int)>[];
  var lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
  while (true) {
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd < 0) lineEnd = text.length;
    lines.add((lineStart, lineEnd));
    if (lineEnd >= end || lineEnd == text.length) break;
    lineStart = lineEnd + 1;
  }
  return lines;
}

/// Where the line before the one starting at [lineStart] starts.
int _previousLine(String text, int lineStart) =>
    lineStart < 2 ? 0 : text.lastIndexOf('\n', lineStart - 2) + 1;

/// Puts [style]'s marks around the selected text, or takes them away when
/// the selection already has it. A pair never crosses a line, so each line
/// gets its own; a part of a word takes the whole word, or the marks would
/// not count.
TextEditingValue toggleInlineStyle(TextEditingValue value, InlineStyle style) {
  final text = value.text;
  final parts = _inlineParts(value);
  if (parts.isEmpty) return value;
  final mark = _inlineMark[style]!;
  final remove = parts.every((part) => part.wrapped(text, style) != null);

  final edits = _Edits(text);
  int? selectionStart;
  var selectionEnd = 0;
  for (final part in parts) {
    final (start, end) = (part.start, part.end);
    final wrapped = part.wrapped(text, style);
    final int shownStart;
    if (remove) {
      final (open, close) = wrapped!;
      edits.delete(open, 1);
      // A mark inside the selection is taken out with the selection.
      shownStart = edits.copyTo(open == start ? start + 1 : start);
      selectionEnd = edits.copyTo(close == end - 1 ? end - 1 : end);
      edits.delete(close, 1);
    } else if (wrapped != null) {
      shownStart = edits.copyTo(start);
      selectionEnd = edits.copyTo(end);
    } else {
      edits.insert(start, mark);
      shownStart = edits.copyTo(start);
      selectionEnd = edits.copyTo(end);
      edits.insert(end, mark);
    }
    selectionStart ??= shownStart;
  }
  return TextEditingValue(
    text: edits.finish(),
    selection: TextSelection(
      baseOffset: selectionStart!,
      extentOffset: selectionEnd,
    ),
  );
}

/// A part of one line that an inline style goes around.
typedef _Part = ({int start, int end});

extension on _Part {
  /// Where the marks of [style] around this part are, or null when it does
  /// not have it. They may be just outside it, past other marks, or its own
  /// first and last characters.
  (int, int)? wrapped(String text, InlineStyle style) {
    final mark = _inlineMark[style]!;
    if (end - start > 2 && text[start] == mark && text[end - 1] == mark) {
      return (start, end - 1);
    }
    bool isMark(String character) => _inlineMark.containsValue(character);
    int? open;
    for (var i = start - 1; i >= 0 && isMark(text[i]); i--) {
      if (text[i] == mark) {
        open = i;
        break;
      }
    }
    int? close;
    for (var i = end; i < text.length && isMark(text[i]); i++) {
      if (text[i] == mark) {
        close = i;
        break;
      }
    }
    return open == null || close == null ? null : (open, close);
  }
}

/// The parts of each line [value]'s selection touches, without the spaces
/// around them and widened to whole words.
List<_Part> _inlineParts(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return const [];
  return [
    for (final (lineStart, lineEnd) in _linesTouched(text, selection))
      ?_inlinePart(
        text,
        math.max(selection.start, lineStart),
        math.min(selection.end, lineEnd),
      ),
  ];
}

_Part? _inlinePart(String text, int start, int end) {
  while (start < end && _isSpace(text[start])) {
    start++;
  }
  while (end > start && _isSpace(text[end - 1])) {
    end--;
  }
  if (start >= end) return null;
  while (start > 0 && _isWord(text[start - 1])) {
    start--;
  }
  while (end < text.length && _isWord(text[end])) {
    end++;
  }
  return (start: start, end: end);
}

/// The fences of the monospace block the selected lines are in, each as
/// (where, how many characters to delete with it), or null when they are in
/// none.
((int, int), (int, int))? _monospaceBlock(TextEditingValue value) {
  final text = value.text;
  final lines = _linesTouched(text, value.selection);
  final (first, firstEnd) = lines.first;
  final (lastStart, last) = lines.last;

  bool isFence(int start, int end) =>
      text.substring(start, end).trim() == _fence;

  // The selection holds the fences.
  if (lines.length >= 3 &&
      isFence(first, firstEnd) &&
      isFence(lastStart, last)) {
    return (
      (first, firstEnd + 1 - first),
      (lastStart - 1, last - lastStart + 1),
    );
  }
  // The fences are the lines around the selection.
  if (first == 0 || last == text.length) return null;
  final before = _previousLine(text, first);
  var after = text.indexOf('\n', last + 1);
  if (after < 0) after = text.length;
  if (!isFence(before, first - 1) || !isFence(last + 1, after)) return null;
  return ((before, first - before), (last, after - last));
}

/// Puts the selected lines in a monospace block, or takes them out of the
/// one they are in.
TextEditingValue toggleMonospaceBlock(TextEditingValue value) {
  final text = value.text;
  if (!value.selection.isValid) return value;
  final edits = _Edits(text);
  final int start;
  final int end;
  if (_monospaceBlock(value) case (
    (final open, final openLength),
    (final close, final closeLength),
  )) {
    edits.delete(open, openLength);
    start = edits.copyTo(open + openLength);
    end = edits.copyTo(close);
    edits.delete(close, closeLength);
  } else {
    final lines = _linesTouched(text, value.selection);
    edits.insert(lines.first.$1, '$_fence\n');
    start = edits.copyTo(lines.first.$1);
    end = edits.copyTo(lines.last.$2);
    edits.insert(lines.last.$2, '\n$_fence');
  }
  return TextEditingValue(
    text: edits.finish(),
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

/// Whether every line [value]'s selection touches, blank ones aside, has
/// [style].
bool hasLineStyle(TextEditingValue value, LineStyle style) {
  final text = value.text;
  if (!value.selection.isValid) return false;
  final filled = [
    for (final (start, end) in _linesTouched(text, value.selection))
      if (text.substring(start, end).trim().isNotEmpty)
        text.substring(start, end),
  ];
  return filled.isNotEmpty && filled.every(_markOf(style).hasMatch);
}

/// Gives every line the selection touches [style], in place of any other
/// line mark, or takes it away when they all have it. Blank lines stay as
/// they are. Numbers count up from 1, or on from a numbered item just above.
TextEditingValue toggleLineStyle(TextEditingValue value, LineStyle style) {
  final text = value.text;
  if (!value.selection.isValid) return value;
  final remove = hasLineStyle(value, style);
  final lines = _linesTouched(text, value.selection);

  var number = BigInt.one;
  final first = lines.first.$1;
  if (style == LineStyle.numbered && first > 0) {
    final above = text.substring(_previousLine(text, first), first - 1);
    if (_numberMark.firstMatch(above) case final match?) {
      number = BigInt.parse(match[1]!) + BigInt.one;
    }
  }

  final edits = _Edits(text);
  final start = edits.copyTo(first);
  for (final (start, end) in lines) {
    final line = text.substring(start, end);
    if (line.trim().isEmpty) continue;
    final existing = _anyLineMark.firstMatch(line);
    if (remove) {
      edits.delete(start, existing!.end);
      continue;
    }
    edits.replace(start, existing?.end ?? 0, switch (style) {
      LineStyle.bullet => '- ',
      LineStyle.numbered => '$number. ',
      LineStyle.quote => '> ',
    });
    number += BigInt.one;
  }
  final end = edits.copyTo(lines.last.$2);
  return TextEditingValue(
    text: edits.finish(),
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

/// Enter in a list item starts the next one: a bullet like this one, or the
/// next number. Enter in an empty item ends the list and takes its mark
/// away.
class ListContinuation extends TextInputFormatter {
  const ListContinuation();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final old = oldValue.text;
    final selection = oldValue.selection;
    if (!selection.isValid || !selection.isCollapsed) return newValue;
    final at = selection.start;
    // Only a line break typed at the cursor.
    if (newValue.text.length != old.length + 1 ||
        newValue.selection != TextSelection.collapsed(offset: at + 1) ||
        newValue.text != old.replaceRange(at, at, '\n')) {
      return newValue;
    }

    final lineStart = at == 0 ? 0 : old.lastIndexOf('\n', at - 1) + 1;
    var lineEnd = old.indexOf('\n', at);
    if (lineEnd < 0) lineEnd = old.length;
    final line = old.substring(lineStart, lineEnd);

    final String next;
    final int markLength;
    if (_bulletMark.firstMatch(line) case final match?) {
      next = match[0]!;
      markLength = match.end;
    } else if (_numberMark.firstMatch(line) case final match?) {
      next = '${BigInt.parse(match[1]!) + BigInt.one}. ';
      markLength = match.end;
    } else {
      return newValue;
    }
    // Before the mark, Enter only breaks the line.
    if (at < lineStart + markLength) return newValue;

    if (line.substring(markLength).trim().isEmpty) {
      return TextEditingValue(
        text: old.replaceRange(lineStart, lineEnd, ''),
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    return TextEditingValue(
      text: old.replaceRange(at, at, '\n$next'),
      selection: TextSelection.collapsed(offset: at + 1 + next.length),
    );
  }
}
