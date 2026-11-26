// Compiles the SVGs in vectors/ into the .vec files the app bundles from
// assets/. Run from app/ after changing an SVG:
//   dart run tool/compile_vectors.dart
//
// Flutter's asset transformers start one `dart run vector_graphics_compiler`
// per SVG, which runs out of memory; this runs the compiler once per folder.
import 'dart:io';

/// Each SVG folder under vectors/ and the asset folder it compiles into.
///
/// vectors/icons/stroke and fill hold the Keyline Icons, which
/// tool/keyline_icons.dart replaces whole on every run. Icons made for
/// Kronoer live in vectors/icons/custom/ and compile into the same asset
/// folders, so the app loads both the same way.
const folders = [
  ('vectors/brand', 'assets/brand'),
  ('vectors/illustrations', 'assets/illustrations'),
  ('vectors/icons/stroke', 'assets/icons/stroke'),
  ('vectors/icons/fill', 'assets/icons/fill'),
  ('vectors/icons/custom/stroke', 'assets/icons/stroke'),
  ('vectors/icons/custom/fill', 'assets/icons/fill'),
];

Future<void> main() async {
  final cleared = <String>{};
  for (final (from, to) in folders) {
    final out = Directory(to)..createSync(recursive: true);
    // Clear each asset folder once, before the first folder compiles into it.
    if (cleared.add(to)) {
      for (final old in out.listSync().whereType<File>()) {
        if (old.path.endsWith('.vec')) old.deleteSync();
      }
    }

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'vector_graphics_compiler',
      '--input-dir',
      from,
      '--out-dir',
      to,
      '--concurrency',
      '2',
    ]);
    if (result.exitCode != 0) {
      stderr
        ..write(result.stdout)
        ..write(result.stderr);
      exit(result.exitCode);
    }

    // The compiler names its output name.svg.vec.
    for (final file in out.listSync().whereType<File>()) {
      if (file.path.endsWith('.svg.vec')) {
        file.renameSync(file.path.replaceFirst(RegExp(r'\.svg\.vec$'), '.vec'));
      }
    }
    stdout.writeln('$from -> $to');
  }
}
