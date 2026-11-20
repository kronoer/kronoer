// Compiles the SVGs in vectors/ into the .vec files the app bundles from
// assets/. Run from app/ after changing an SVG:
//   dart run tool/compile_vectors.dart
//
// The app does not use Flutter's asset transformers: they start one
// `dart run vector_graphics_compiler` per SVG, which ran the machine out of
// memory (KRO-29). This runs the compiler once per folder instead.
import 'dart:io';

/// Each SVG folder under vectors/ and the asset folder it compiles into.
const folders = {
  'vectors/brand': 'assets/brand',
  'vectors/illustrations': 'assets/illustrations',
  'vectors/icons/stroke': 'assets/icons/stroke',
  'vectors/icons/fill': 'assets/icons/fill',
};

Future<void> main() async {
  for (final MapEntry(key: from, value: to) in folders.entries) {
    final out = Directory(to)..createSync(recursive: true);
    for (final old in out.listSync().whereType<File>()) {
      if (old.path.endsWith('.vec')) old.deleteSync();
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
