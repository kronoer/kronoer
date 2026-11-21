import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/entries/text_style_editing.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:material_ui/material_ui.dart';

/// [text] with the selection written into it: `[` and `]` around a
/// selection, or `|` for a cursor.
TextEditingValue _value(String text) {
  final cursor = text.indexOf('|');
  if (cursor >= 0) {
    return TextEditingValue(
      text: text.replaceFirst('|', ''),
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
  final start = text.indexOf('[');
  final end = text.indexOf(']') - 1;
  return TextEditingValue(
    text: text.replaceFirst('[', '').replaceFirst(']', ''),
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

/// [value] written as [_value] reads it.
String _written(TextEditingValue value) {
  final selection = value.selection;
  final text = value.text;
  if (selection.isCollapsed) {
    return text.replaceRange(selection.start, selection.start, '|');
  }
  return text
      .replaceRange(selection.end, selection.end, ']')
      .replaceRange(selection.start, selection.start, '[');
}

String _inline(String text, InlineStyle style) =>
    _written(toggleInlineStyle(_value(text), style));

String _line(String text, LineStyle style) =>
    _written(toggleLineStyle(_value(text), style));

String _mono(String text) => _written(toggleMonospaceBlock(_value(text)));

/// Types a line break at the cursor, through [ListContinuation].
String _enter(String text) {
  final old = _value(text);
  final at = old.selection.start;
  final typed = TextEditingValue(
    text: old.text.replaceRange(at, at, '\n'),
    selection: TextSelection.collapsed(offset: at + 1),
  );
  return _written(const ListContinuation().formatEditUpdate(old, typed));
}

void main() {
  group('inline styles', () {
    test('wrap the selection, and keep it on the text', () {
      expect(
        _inline('Pagi [ini] hujan', InlineStyle.bold),
        'Pagi *[ini]* hujan',
      );
      expect(_inline('[Pagi] ini', InlineStyle.italic), '_[Pagi]_ ini');
      expect(
        _inline('ini [hujan]', InlineStyle.strikethrough),
        'ini ~[hujan]~',
      );
      expect(_inline('jalan [ls -a]', InlineStyle.code), 'jalan `[ls -a]`');
    });

    test('leave out the spaces around the selection', () {
      expect(
        _inline('Pagi[ ini ]hujan', InlineStyle.bold),
        'Pagi *[ini]* hujan',
      );
    });

    test(
      'take the whole word when the selection starts or ends inside one',
      () {
        expect(_inline('Pa[gi in]i', InlineStyle.bold), '*[Pagi ini]*');
      },
    );

    test('put a pair on every line, since a pair never crosses one', () {
      expect(_inline('[satu\ndua]', InlineStyle.bold), '*[satu*\n*dua]*');
      // A blank line in between gets none.
      expect(_inline('[satu\n\ndua]', InlineStyle.italic), '_[satu_\n\n_dua]_');
    });

    test('are taken away when the selection has them', () {
      expect(
        _inline('Pagi *[ini]* hujan', InlineStyle.bold),
        'Pagi [ini] hujan',
      );
      // With the marks selected too.
      expect(
        _inline('Pagi [*ini*] hujan', InlineStyle.bold),
        'Pagi [ini] hujan',
      );
      // Past other marks.
      expect(_inline('*_[ini]_*', InlineStyle.bold), '_[ini]_');
      // Only when every line has it; otherwise the rest get it.
      expect(_inline('[*satu*\ndua]', InlineStyle.bold), '[*satu*\n*dua]*');
    });

    test('combine', () {
      expect(_inline('_[ini]_', InlineStyle.bold), '_*[ini]*_');
      final value = toggleInlineStyle(_value('_[ini]_'), InlineStyle.bold);
      expect(
        parseInline(value.text).single,
        const StyledRun('ini', 2, {InlineStyle.italic, InlineStyle.bold}),
      );
    });

    test('do nothing to a selection of spaces', () {
      expect(_inline('a[  ]b', InlineStyle.bold), 'a[  ]b');
    });
  });

  group('line styles', () {
    test('mark every line the selection touches', () {
      expect(_line('ro[ti\nte]h', LineStyle.bullet), '[- roti\n- teh]');
      expect(_line('a[a\n\nb]b', LineStyle.quote), '[> aa\n\n> bb]');
    });

    test('a selection ending at the start of a line leaves that line', () {
      expect(_line('[roti\n]teh', LineStyle.bullet), '[- roti]\nteh');
    });

    test('numbers count up, or on from an item just above', () {
      expect(
        _line('[roti\nteh\nkopi]', LineStyle.numbered),
        '[1. roti\n2. teh\n3. kopi]',
      );
      expect(
        _line('7. gula\n[roti\nteh]', LineStyle.numbered),
        '7. gula\n[8. roti\n9. teh]',
      );
    });

    test('replace another line style', () {
      expect(
        _line('[- roti\n> teh\n3. kopi]', LineStyle.quote),
        '[> roti\n> teh\n> kopi]',
      );
    });

    test('are taken away when every line has them', () {
      expect(_line('[- roti\n* teh]', LineStyle.bullet), '[roti\nteh]');
      expect(_line('[1. roti\n\n2. teh]', LineStyle.numbered), '[roti\n\nteh]');
      expect(_line('[> kata\n> Ibu]', LineStyle.quote), '[kata\nIbu]');
      // Not every line has it, so the rest get it.
      expect(_line('[> kata\nIbu]', LineStyle.quote), '[> kata\n> Ibu]');
    });
  });

  group('monospace blocks', () {
    test('wrap the lines the selection touches', () {
      expect(
        _mono('jalan\nls [-a\ncd] ..\nselesai'),
        'jalan\n```\n[ls -a\ncd ..]\n```\nselesai',
      );
    });

    test('are taken away from the lines inside one', () {
      expect(
        _mono('jalan\n```\nls [-a\ncd] ..\n```\nselesai'),
        'jalan\n[ls -a\ncd ..]\nselesai',
      );
      expect(_mono('```\n[ls]\n```'), '[ls]');
    });

    test('or when the selection holds the fences', () {
      expect(
        _mono('jalan\n[```\nls -a\n```]\nselesai'),
        'jalan\n[ls -a]\nselesai',
      );
    });

    test('what they hold is not styled', () {
      final value = toggleMonospaceBlock(_value('[jam *7* pagi]'));
      expect(parseTextStyles(value.text), [
        const CodeBlock(StyledRun('jam *7* pagi', 4)),
      ]);
    });
  });

  group('Enter in a list', () {
    test('starts the next item', () {
      expect(_enter('- roti|'), '- roti\n- |');
      expect(_enter('* roti|\n* teh'), '* roti\n* |\n* teh');
      expect(_enter('9. roti|'), '9. roti\n10. |');
    });

    test('in the middle of an item, takes the rest along', () {
      expect(_enter('- roti| bakar'), '- roti\n- | bakar');
    });

    test('in an empty item, ends the list and takes its mark away', () {
      expect(_enter('- roti\n- |'), '- roti\n|');
      expect(_enter('1. roti\n2. |'), '1. roti\n|');
    });

    test('before the mark, or outside a list, only breaks the line', () {
      expect(_enter('|- roti'), '\n|- roti');
      expect(_enter('roti|'), 'roti\n|');
      expect(_enter('> kata|'), '> kata\n|');
    });

    test('leaves other edits alone', () {
      final old = _value('- roti|');
      const pasted = TextEditingValue(
        text: '- roti\nteh',
        selection: TextSelection.collapsed(offset: 10),
      );
      expect(const ListContinuation().formatEditUpdate(old, pasted), pasted);
    });
  });
}
