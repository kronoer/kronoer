import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kronoer/src/entries/time_taken.dart';

/// A small JPEG whose EXIF says when it was taken, as a phone writes it.
Uint8List jpegTaken({String? taken, String? offset, String? changed}) {
  final image = img.Image(width: 8, height: 8);
  if (changed != null) {
    image.exif.imageIfd['DateTime'] = img.IfdValueAscii(changed);
  }
  if (taken != null) {
    image.exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(taken);
  }
  if (offset != null) {
    image.exif.exifIfd['OffsetTimeOriginal'] = img.IfdValueAscii(offset);
  }
  return img.encodeJpg(image);
}

/// The EXIF of [taken] as HEIC keeps it: an Exif item in a box, not a JPEG
/// segment.
Uint8List heicTaken(String taken, {String? offset}) {
  final exif = img.ExifData();
  exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(taken);
  if (offset != null) {
    exif.exifIfd['OffsetTimeOriginal'] = img.IfdValueAscii(offset);
  }
  final tiff = img.OutputBuffer(bigEndian: true);
  exif.write(tiff);
  return Uint8List.fromList([
    ...[0, 0, 0, 24],
    ...latin1.encode('ftypheic'),
    ...List.filled(12, 0),
    ...latin1.encode('mdat'),
    ...[0, 0, 0, 6],
    ...latin1.encode('Exif\u0000\u0000'),
    ...tiff.getBytes(),
    ...List.filled(64, 0xAB),
  ]);
}

void main() {
  group('reading the time taken', () {
    test('with its zone, at that moment', () {
      final taken = readTimeTaken(
        jpegTaken(taken: '2026:11:14 16:20:05', offset: '+07:00'),
      );
      expect(taken, isNotNull);
      expect(taken!.isUtc, isFalse);
      expect(
        taken.isAtSameMomentAs(DateTime.utc(2026, 11, 14, 9, 20, 5)),
        isTrue,
      );
    });

    test('with a zone west of UTC', () {
      final taken = readTimeTaken(
        jpegTaken(taken: '2026:11:14 16:20:05', offset: '-03:30'),
      );
      expect(
        taken!.isAtSameMomentAs(DateTime.utc(2026, 11, 14, 19, 50, 5)),
        isTrue,
      );
    });

    test('without a zone, as device local time', () {
      expect(
        readTimeTaken(jpegTaken(taken: '2026:11:14 16:20:05')),
        DateTime(2026, 11, 14, 16, 20, 5),
      );
    });

    test('a broken zone is left out', () {
      expect(
        readTimeTaken(jpegTaken(taken: '2026:11:14 16:20:05', offset: '7')),
        DateTime(2026, 11, 14, 16, 20, 5),
      );
    });

    test('from HEIC, whose EXIF is not in a JPEG segment', () {
      expect(
        readTimeTaken(heicTaken('2026:11:14 16:20:05')),
        DateTime(2026, 11, 14, 16, 20, 5),
      );
      expect(
        readTimeTaken(heicTaken('2026:11:14 16:20:05', offset: '+07:00'))!
            .isAtSameMomentAs(DateTime.utc(2026, 11, 14, 9, 20, 5)),
        isTrue,
      );
    });

    test('missing: no EXIF, or no time it was taken', () {
      expect(readTimeTaken(jpegTaken()), isNull);
      // When it was last changed is not when it was taken.
      expect(readTimeTaken(jpegTaken(changed: '2026:11:14 16:20:05')), isNull);
      expect(
        readTimeTaken(img.encodePng(img.Image(width: 4, height: 4))),
        isNull,
      );
      expect(readTimeTaken(Uint8List(0)), isNull);
      expect(readTimeTaken(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('broken or partial times are skipped', () {
      for (final broken in [
        '0000:00:00 00:00:00',
        '    :  :     :  :  ',
        '2026:02:31 10:00:00',
        '2026:13:01 10:00:00',
        '2026:11:14 24:00:00',
        '2026:11:14',
        '2026-11-14 16:20:05',
        '1850:01:01 10:00:00',
      ]) {
        expect(readTimeTaken(jpegTaken(taken: broken)), isNull, reason: broken);
      }
    });

    test('trailing NULs and spaces are not part of the time', () {
      expect(
        parseTimeTaken('2026:11:14 16:20:05\u0000 ', offset: '+07:00\u0000'),
        DateTime.utc(2026, 11, 14, 9, 20, 5).toLocal(),
      );
    });

    test('a truncated EXIF block reads as none', () {
      final whole = jpegTaken(taken: '2026:11:14 16:20:05');
      final start = latin1.decode(whole).indexOf('Exif');
      expect(readTimeTaken(whole.sublist(0, start + 20)), isNull);
    });
  });

  group('the suggested Entry date', () {
    final now = DateTime(2026, 11, 19, 14, 32);

    DateTime? suggest(List<DateTime?> times, {DateTime? entryDate}) =>
        suggestedEntryDate(
          entryDate: entryDate ?? now,
          timesTaken: times,
          now: now,
        );

    test('is the earliest time taken, skipping photos with none', () {
      expect(
        suggest([
          DateTime(2026, 11, 14, 16, 20),
          null,
          DateTime(2026, 11, 13, 9),
          DateTime(2026, 11, 15, 8),
        ]),
        DateTime(2026, 11, 13, 9),
      );
    });

    test('is none without a time taken', () {
      expect(suggest([]), isNull);
      expect(suggest([null, null]), isNull);
    });

    test('only when more than an hour from the Entry date', () {
      expect(suggest([now.subtract(const Duration(minutes: 59))]), isNull);
      expect(suggest([now.subtract(const Duration(hours: 1))]), isNull);
      final earlier = now.subtract(const Duration(hours: 1, minutes: 1));
      expect(suggest([earlier]), earlier);
      // The earliest decides: a later photo far off does not count.
      expect(
        suggest([
          now.subtract(const Duration(minutes: 30)),
          DateTime(2026, 11, 14),
        ]),
        DateTime(2026, 11, 14),
      );
      expect(
        suggest([
          now.subtract(const Duration(minutes: 30)),
          now.subtract(const Duration(minutes: 10)),
        ]),
        isNull,
      );
    });

    test('from an Entry date in the past, a later time counts too', () {
      final entryDate = DateTime(2026, 11, 1, 10);
      expect(
        suggest([DateTime(2026, 11, 2, 10)], entryDate: entryDate),
        DateTime(2026, 11, 2, 10),
      );
    });

    test('future times are skipped', () {
      expect(suggest([now.add(const Duration(days: 2))]), isNull);
      expect(
        suggest([
          now.add(const Duration(days: 2)),
          DateTime(2026, 11, 14, 16, 20),
        ]),
        DateTime(2026, 11, 14, 16, 20),
      );
    });
  });
}
