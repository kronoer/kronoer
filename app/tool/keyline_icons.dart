// Copies the Keyline Icons that Kronoer uses into vectors/icons/ and their
// license into assets/icons/. Run from app/, then compile the icons:
//   dart run tool/keyline_icons.dart
//   dart run tool/compile_vectors.dart
import 'dart:io';

const commit = '460c70bdc3948c1d1496842640767e44c3e8eaae';

const names = [
  'arrow-left',
  'arrow-u-turn-left',
  'bell',
  'bin-2',
  'book',
  'book-lock',
  'calendar',
  'camera',
  'check',
  'chevron-right',
  'clock',
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
  'star',
  'star-off',
  'swatch-book',
  'triangle-alert',
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
