// Copies the Keyline Icons that Kronoer uses into vectors/icons/ and their
// license into assets/icons/. Run from app/, then compile the icons:
//   dart run tool/keyline_icons.dart
//   dart run tool/compile_vectors.dart
import 'dart:io';

const commit = '613a1e1f156fcd707c6884830d49d8180b8396e5';

const names = [
  'arrow-left',
  'bin-2',
  'book',
  'calendar',
  'camera',
  'check',
  'chevron-right',
  'copy',
  'download',
  'fingerprint-pattern',
  'image',
  'image-off',
  'info',
  'language',
  'lock',
  'more-vertical',
  'pen',
  'pin',
  'pin-off',
  'plus',
  'search',
  'settings',
  'swatch-book',
  'upload',
  'x',
];

Future<void> main() async {
  final base =
      'https://raw.githubusercontent.com/keyline-icons/keyline-icons/$commit';
  final client = HttpClient();
  try {
    for (final style in ['stroke', 'fill']) {
      final dir = Directory('vectors/icons/$style');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      for (final name in names) {
        await _download(
          client,
          '$base/icons/$style/$name.svg',
          File('${dir.path}/$name.svg'),
        );
      }
    }
    await _download(client, '$base/LICENSE', File('assets/icons/LICENSE'));
  } finally {
    client.close();
  }
}

Future<void> _download(HttpClient client, String url, File to) async {
  final response = await (await client.getUrl(Uri.parse(url))).close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('${response.statusCode} for $url');
  }
  await response.pipe(to.openWrite());
  stdout.writeln(to.path);
}
