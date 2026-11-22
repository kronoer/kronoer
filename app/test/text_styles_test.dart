import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/entries/text_styles.dart';

const _bold = {InlineStyle.bold};
const _italic = {InlineStyle.italic};

void main() {
  group('inline styles', () {
    test('each pair of marks styles the text between them', () {
      expect(parseInline('*tebal* dan _miring_'), [
        const StyledRun('tebal', 1, _bold),
        const StyledRun(' dan ', 7),
        const StyledRun('miring', 13, _italic),
      ]);
      expect(parseInline('~coret~ `kode`'), [
        const StyledRun('coret', 1, {InlineStyle.strikethrough}),
        const StyledRun(' ', 7),
        const StyledRun('kode', 9, {InlineStyle.code}),
      ]);
    });

    test('styles combine', () {
      expect(parseInline('*_dua_*'), [
        const StyledRun('dua', 2, {InlineStyle.bold, InlineStyle.italic}),
      ]);
    });

    test('marks inside words and numbers, and unpaired marks, stay', () {
      for (final text in [
        '2 * 3 * 4',
        'file_name_here',
        'a*b*c',
        '*kata',
        'kata*',
        '* kata*',
        '*kata *',
        '**',
      ]) {
        expect(parseInline(text), [StyledRun(text, 0)], reason: text);
      }
    });

    test('marks may sit next to punctuation', () {
      expect(parseInline('(*kata*),'), [
        const StyledRun('(', 0),
        const StyledRun('kata', 2, _bold),
        const StyledRun('),', 7),
      ]);
    });

    test('nothing inside code is styled', () {
      expect(parseInline('`*a* _b_`'), [
        const StyledRun('*a* _b_', 1, {InlineStyle.code}),
      ]);
    });

    test('a pair never crosses a line', () {
      expect(parseTextStyles('*satu\ndua*'), [
        const ParagraphBlock([
          StyledRun('*satu', 0),
          StyledRun('\n', 5),
          StyledRun('dua*', 6),
        ]),
      ]);
    });
  });

  group('blocks', () {
    test('paragraphs split at blank lines and keep where they start', () {
      expect(parseTextStyles('  Satu.\n\n\nDua\nbaris.\n \n'), [
        const ParagraphBlock([StyledRun('Satu.', 2)]),
        const ParagraphBlock([
          StyledRun('Dua', 10),
          StyledRun('\n', 13),
          StyledRun('baris.', 14),
        ]),
      ]);
    });

    test('a monospace block may span lines and styles nothing', () {
      expect(parseTextStyles('Lihat:\n```\nfn *a*\n  _b_\n```\nSelesai.'), [
        const ParagraphBlock([StyledRun('Lihat:', 0)]),
        const CodeBlock(StyledRun('fn *a*\n  _b_', 11)),
        const ParagraphBlock([StyledRun('Selesai.', 28)]),
      ]);
    });

    test('an unpaired or empty fence is no block', () {
      expect(parseTextStyles('```kode'), [
        const ParagraphBlock([StyledRun('```kode', 0)]),
      ]);
      expect(
        parseTextStyles('```\n \n```'),
        everyElement(isA<ParagraphBlock>()),
      );
    });

    test('lists: bullets and numbers as typed, only at the line start', () {
      expect(parseTextStyles('- satu\n* *dua*\n12. tiga\n-empat\n - lima'), [
        const ListBlock([
          ListItem(ListItem.bullet, [StyledRun('satu', 2)]),
          ListItem(ListItem.bullet, [StyledRun('dua', 10, _bold)]),
          ListItem('12.', [StyledRun('tiga', 19)]),
        ]),
        const ParagraphBlock([
          StyledRun('-empat', 24),
          StyledRun('\n', 30),
          StyledRun('- lima', 32),
        ]),
      ]);
    });

    test('consecutive quoted lines are one quote; no nested quotes', () {
      expect(parseTextStyles('> satu\n> _dua_\n>> tiga'), [
        const QuoteBlock([
          StyledRun('satu', 2),
          StyledRun('\n', 6),
          StyledRun('dua', 10, _italic),
        ]),
        const ParagraphBlock([StyledRun('>> tiga', 15)]),
      ]);
    });
  });

  group('previews', () {
    test('are one line, keeping bullets and styles', () {
      final runs = previewRuns(
        'Belanja:\n\n- *kopi*\n- gula\n\n> catatan\n\n```\na  b\n```',
      );
      expect(
        runs.map((run) => run.text).join(),
        'Belanja: • kopi • gula catatan a b',
      );
      String styledWith(InlineStyle style) => [
        for (final run in runs)
          if (run.styles.contains(style)) run.text,
      ].join();
      expect(styledWith(InlineStyle.bold), 'kopi');
      expect(styledWith(InlineStyle.code), 'a b');
    });

    test('keep every shown character over its place in the text', () {
      const text =
          'Belanja:\n\n- *kopi*\n12. gula\n\n> catatan\n\n```\na  b\n```';
      final runs = previewRuns(text);
      // Each run shows the text under it, with marks as their stand-ins and
      // whitespace as one space.
      expect(
        [for (final run in runs) text.substring(run.start, run.end)],
        ['Belanja:\n', '- ', 'kopi', '\n12. gula\n', 'catatan\n', 'a ', 'b'],
      );
    });
  });

  test('places in the text as written map onto the shown text', () {
    final runs = parseInline('a *b* c');
    expect(shownOffset(runs, 0), 0);
    expect(shownOffset(runs, 3), 2);
    // The closing mark falls where the next shown text starts.
    expect(shownOffset(runs, 4), 3);
    expect(shownOffset(runs, 6), 4);
    expect(shownOffset(runs, 7), 5);
  });

  group('plain text', () {
    test('inline marks go', () {
      expect(
        plainText('*tebal* _miring_ ~coret~ `kode` *_dua_*'),
        'tebal miring coret kode dua',
      );
    });

    test('marks that style nothing stay', () {
      expect(plainText('2 * 3 * 4 dan file_name'), '2 * 3 * 4 dan file_name');
    });

    test('quote marks go and the lines stay', () {
      expect(plainText('> satu\n> *dua*'), 'satu\ndua');
    });

    test('bullets become • and numbers stay', () {
      expect(plainText('- kopi\n* *gula*\n12. teh'), '• kopi\n• gula\n12. teh');
    });

    test('a monospace block keeps its text as written', () {
      expect(plainText('```\n*a*\n  b\n```'), '*a*\n  b');
    });

    test('lines and blank lines stay where they are', () {
      expect(
        plainText('Pagi ini hujan.\nTurun pelan.\n\nSiangnya cerah.'),
        'Pagi ini hujan.\nTurun pelan.\n\nSiangnya cerah.',
      );
      // A list right under a line, with no blank line, stays right under it.
      expect(
        plainText('Belanja:\n- kopi\n\n> kata Ibu\n```\nkode\n```\nakhir'),
        'Belanja:\n• kopi\n\nkata Ibu\nkode\nakhir',
      );
    });

    test('several blank lines become one', () {
      expect(plainText('satu\n\n\n\ndua'), 'satu\n\ndua');
    });
  });
}
