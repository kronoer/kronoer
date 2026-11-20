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
    for (final MapEntry(key: from, value: to) in folders.entries) {
      expect(
        _names(to, '.vec'),
        _names(from, '.svg'),
        reason: 'run `dart run tool/compile_vectors.dart` ($from -> $to)',
      );
      expect(_names(to, '.svg'), isEmpty, reason: '$to holds SVG files');
    }
  });
}
