import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kronoer/src/entries/image_processing.dart';

/// A JPEG photo as a phone writes it: EXIF with GPS location, camera model,
/// time, and orientation, plus XMP and IPTC.
Uint8List photo({
  required int width,
  required int height,
  int orientation = 1,
  img.Color? left,
  img.Color? right,
}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    final color = pixel.x < width / 2
        ? left ?? img.ColorRgb8(200, 30, 30)
        : right ?? img.ColorRgb8(30, 30, 200);
    pixel
      ..r = color.r
      ..g = color.g
      ..b = color.b;
  }
  image.exif.imageIfd
    ..orientation = orientation
    ..['Make'] = img.IfdValueAscii('Kamera Contoh')
    ..['Model'] = img.IfdValueAscii('KX-1000')
    ..['DateTime'] = img.IfdValueAscii('2026:11:19 14:32:00');
  image.exif.gpsIfd
    ..['GPSLatitudeRef'] = img.IfdValueAscii('S')
    ..['GPSLatitude'] = img.IfdValueRational.list([
      img.Rational(6, 1),
      img.Rational(10, 1),
      img.Rational(0, 1),
    ])
    ..['GPSLongitudeRef'] = img.IfdValueAscii('E')
    ..['GPSLongitude'] = img.IfdValueRational.list([
      img.Rational(106, 1),
      img.Rational(49, 1),
      img.Rational(0, 1),
    ]);
  final jpeg = img.encodeJpg(image, quality: 95);

  // XMP (APP1) and IPTC (APP13) right after the start of image.
  Uint8List segment(int marker, List<int> payload) {
    final length = payload.length + 2;
    return Uint8List.fromList([
      0xFF,
      marker,
      length >> 8,
      length & 0xFF,
      ...payload,
    ]);
  }

  final xmp = segment(0xE1, [
    ...latin1.encode('http://ns.adobe.com/xap/1.0/\x00'),
    ...latin1.encode('<x:xmpmeta><rdf:Description photoshop:City="Jakarta"/>'),
  ]);
  final iptc = segment(0xED, [
    ...latin1.encode('Photoshop 3.0\x00'),
    ...latin1.encode('8BIM\x04\x04\x00\x00\x00\x00\x00\x0aCity Jakarta'),
  ]);
  return Uint8List.fromList([
    ...jpeg.sublist(0, 2),
    ...xmp,
    ...iptc,
    ...jpeg.sublist(2),
  ]);
}

/// The markers of every segment before the image data.
List<int> markers(Uint8List jpeg) {
  final found = <int>[];
  var i = 2;
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    if (marker == 0xDA) break;
    found.add(marker);
    i += 2 + (jpeg[i + 2] << 8 | jpeg[i + 3]);
  }
  return found;
}

void main() {
  Future<ProcessedImage> process(WidgetTester tester, Uint8List bytes) async =>
      (await tester.runAsync(() => processImage(bytes)))!;

  img.Image decode(Uint8List jpeg) => img.decodeJpg(jpeg)!;

  testWidgets('the photo fixture carries the metadata it should', (
    tester,
  ) async {
    final bytes = photo(width: 60, height: 30, orientation: 6);
    final exif = img.decodeJpgExif(bytes)!;

    expect(exif.gpsIfd['GPSLatitudeRef']?.toString(), 'S');
    expect(exif.imageIfd.orientation, 6);
    expect(markers(bytes), containsAll([0xE1, 0xED]));
    final text = latin1.decode(bytes);
    for (final meta in ['Exif', 'KX-1000', 'Jakarta', 'xap', '8BIM']) {
      expect(text, contains(meta), reason: meta);
    }
  });

  testWidgets('no metadata is left: no EXIF, GPS, XMP, or IPTC', (
    tester,
  ) async {
    final processed = await process(
      tester,
      photo(width: 600, height: 400, orientation: 6),
    );

    for (final jpeg in [processed.full, processed.thumbnail]) {
      // Only JFIF, quantization and Huffman tables, and the frame header.
      expect(markers(jpeg), everyElement(isIn([0xE0, 0xDB, 0xC4, 0xC0])));
      expect(decode(jpeg).exif.isEmpty, isTrue);
      final text = latin1.decode(jpeg);
      for (final leak in ['Exif', 'KX-1000', 'Jakarta', 'xap', '8BIM']) {
        expect(text, isNot(contains(leak)), reason: leak);
      }
    }
  });

  testWidgets('the EXIF rotation is applied to the pixels', (tester) async {
    // Orientation 6: shown turned a quarter clockwise, so the left half
    // (red) ends up on top.
    final processed = await process(
      tester,
      photo(width: 60, height: 30, orientation: 6),
    );

    final full = decode(processed.full);
    expect((full.width, full.height), (30, 60));
    final top = full.getPixel(15, 10);
    final bottom = full.getPixel(15, 50);
    expect(top.r, greaterThan(150));
    expect(top.b, lessThan(100));
    expect(bottom.b, greaterThan(150));
    expect(bottom.r, lessThan(100));
  });

  testWidgets('a large photo is scaled to 2048 and 512 on its longest side', (
    tester,
  ) async {
    final processed = await process(tester, photo(width: 4000, height: 1000));

    final full = decode(processed.full);
    final thumbnail = decode(processed.thumbnail);
    expect((full.width, full.height), (fullImageSize, 512));
    expect((thumbnail.width, thumbnail.height), (thumbnailSize, 128));
  });

  testWidgets('a rotated portrait photo keeps 2048 on its longest side', (
    tester,
  ) async {
    final processed = await process(
      tester,
      photo(width: 3000, height: 1500, orientation: 6),
    );

    final full = decode(processed.full);
    final thumbnail = decode(processed.thumbnail);
    expect((full.width, full.height), (1024, fullImageSize));
    expect((thumbnail.width, thumbnail.height), (256, thumbnailSize));
  });

  testWidgets('a small photo is never scaled up', (tester) async {
    final processed = await process(tester, photo(width: 300, height: 200));

    expect(decode(processed.full).width, 300);
    expect(decode(processed.thumbnail).width, 300);
  });

  testWidgets('a PNG with transparency becomes a JPEG on white', (
    tester,
  ) async {
    final png = img.encodePng(
      img.Image(width: 20, height: 20, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0)),
    );
    final processed = await process(tester, png);

    expect(processed.full.sublist(0, 2), [0xFF, 0xD8]);
    final pixel = decode(processed.full).getPixel(10, 10);
    expect([pixel.r, pixel.g, pixel.b], everyElement(greaterThan(245)));
  });

  testWidgets('bytes that are no image are refused', (tester) async {
    final error = await tester.runAsync(() async {
      try {
        await processImage(Uint8List.fromList(utf8.encode('bukan foto')));
        return null;
      } on Object catch (error) {
        return error;
      }
    });
    expect(error, isA<UnreadableImage>());
  });
}
