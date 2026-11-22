/// An Entry date as the core keeps it: local time with its UTC offset, as
/// `YYYY-MM-DDTHH:MM:SS±HH:MM`. Fractions of a second are dropped.
String formatEntryDate(DateTime time) {
  final local = time.toLocal();
  final offset = local.timeZoneOffset;
  final offsetMinutes = offset.inMinutes.abs();
  String two(int n) => n.toString().padLeft(2, '0');

  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)}T${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}${offset.isNegative ? '-' : '+'}'
      '${two(offsetMinutes ~/ 60)}:${two(offsetMinutes % 60)}';
}

/// A day as the core takes it for the Timeline: `YYYY-MM-DD`.
String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// A `YYYY-MM-DD` day from the core, as its local midnight.
DateTime parseDay(String text) {
  final [year, month, day] = text.split('-').map(int.parse).toList();
  return DateTime(year, month, day);
}

/// The moment an Entry date names, in this device's local time.
DateTime parseEntryDate(String text) => DateTime.parse(text).toLocal();
