import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/compile_vectors.dart' show folders;

Set<String> _names(String dir, String extension) => {
  for (final file in Directory(dir).listSync().whereType<File>())
    if (file.path.endsWith(extension))
      file.uri.pathSegments.last.replaceFirst(extension, ''),
};

void main() {
  // The app bundles compiled .vec files; tool/compile_vectors.dart makes them.
  test('every SVG has its compiled .vec, and nothing else is bundled', () {
    // Several SVG folders may compile into one asset folder.
    final sources = <String, List<String>>{};
    for (final (from, to) in folders) {
      (sources[to] ??= []).add(from);
    }
    for (final MapEntry(key: to, value: from) in sources.entries) {
      expect(_names(to, '.vec'), {
        for (final dir in from) ..._names(dir, '.svg'),
      }, reason: 'run `dart run tool/compile_vectors.dart` ($from -> $to)');
      expect(_names(to, '.svg'), isEmpty, reason: '$to holds SVG files');
    }
  });

  test('icons made for Kronoer do not share a name with a Keyline Icon', () {
    for (final style in ['stroke', 'fill']) {
      final custom = _names('vectors/icons/custom/$style', '.svg');
      expect(
        custom.intersection(_names('vectors/icons/$style', '.svg')),
        isEmpty,
      );
    }
  });
}
