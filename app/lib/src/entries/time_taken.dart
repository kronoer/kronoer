import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How far the time an Image was taken must be from the Entry date before
/// the editor offers it.
const timeTakenMargin = Duration(hours: 1);

const _dateTimeOriginal = 0x9003;
const _offsetTimeOriginal = 0x9011;

/// The time a photo was taken, from its EXIF `DateTimeOriginal`; null when
/// it has none or the time is broken or partial.
///
/// Taken with `OffsetTimeOriginal`'s zone when the photo has one, otherwise
/// as device local time. EXIF is found where JPEG (its APP1 segment) and
/// HEIC (its Exif item) keep it: behind `Exif\0\0`, as a TIFF block. Only
/// read in memory while the photo is prepared: the time is never stored.
DateTime? readTimeTaken(Uint8List bytes) {
  try {
    final tiff = _findTiff(bytes);
    if (tiff == null) return null;
    final exif = img.ExifData.fromInputBuffer(
      img.InputBuffer(bytes, bigEndian: true, offset: tiff),
    );
    // Both live in the Exif sub-IFD, which getTag does not look into.
    img.IfdValue? tag(int id) => exif.exifIfd[id] ?? exif.getTag(id);
    final taken = tag(_dateTimeOriginal)?.toString();
    if (taken == null) return null;
    return parseTimeTaken(taken, offset: tag(_offsetTimeOriginal)?.toString());
  } on Object {
    return null;
  }
}

/// Where the TIFF header after the first `Exif\0\0` starts; null when none.
int? _findTiff(Uint8List bytes) {
  for (var i = 0; i + 10 <= bytes.length; i++) {
    if (bytes[i] != 0x45 ||
        bytes[i + 1] != 0x78 ||
        bytes[i + 2] != 0x69 ||
        bytes[i + 3] != 0x66 ||
        bytes[i + 4] != 0 ||
        bytes[i + 5] != 0) {
      continue;
    }
    final t = i + 6;
    final little =
        bytes[t] == 0x49 &&
        bytes[t + 1] == 0x49 &&
        bytes[t + 2] == 0x2A &&
        bytes[t + 3] == 0;
    final big =
        bytes[t] == 0x4D &&
        bytes[t + 1] == 0x4D &&
        bytes[t + 2] == 0 &&
        bytes[t + 3] == 0x2A;
    if (little || big) return t;
  }
  return null;
}

final _dateTime = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$');
final _offset = RegExp(r'^([+-])(\d{2}):(\d{2})$');

/// An EXIF time, `2026:11:14 16:20:05`, with its zone, `+07:00`, when
/// [offset] is one; null when the time is broken or partial.
DateTime? parseTimeTaken(String value, {String? offset}) {
  final match = _dateTime.firstMatch(_trim(value));
  if (match == null) return null;
  final [year, month, day, hour, minute, second] = [
    for (var i = 1; i <= 6; i++) int.parse(match[i]!),
  ];
  if (year < 1900 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final utc = DateTime.utc(year, month, day, hour, minute, second);
  // 31 February rolls over into March: broken.
  if (utc.month != month || utc.day != day) return null;

  final zone = offset == null ? null : _offset.firstMatch(_trim(offset));
  if (zone == null) {
    return DateTime(year, month, day, hour, minute, second);
  }
  final hours = int.parse(zone[2]!);
  final minutes = int.parse(zone[3]!);
  if (hours > 14 || minutes > 59) {
    return DateTime(year, month, day, hour, minute, second);
  }
  final sign = zone[1] == '-' ? -1 : 1;
  return utc
      .subtract(Duration(hours: hours, minutes: minutes) * sign)
      .toLocal();
}

/// EXIF text may end in NULs or spaces.
String _trim(String value) => value.replaceAll('\u0000', '').trim();

/// The time an Entry is offered as its Entry date: the earliest of the
/// times its Images were taken, when that is more than [timeTakenMargin]
/// from [entryDate]. Images with no time taken, and times after [now], are
/// skipped.
DateTime? suggestedEntryDate({
  required DateTime entryDate,
  required Iterable<DateTime?> timesTaken,
  required DateTime now,
}) {
  DateTime? earliest;
  for (final taken in timesTaken) {
    if (taken == null || taken.isAfter(now)) continue;
    if (earliest == null || taken.isBefore(earliest)) earliest = taken;
  }
  if (earliest == null) return null;
  if (entryDate.difference(earliest).abs() <= timeTakenMargin) return null;
  return earliest;
}
