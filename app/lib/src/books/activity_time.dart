import 'package:intl/intl.dart';

String formatActivityTime(
  DateTime at, {
  required DateTime now,
  required String locale,
  required String yesterday,
}) {
  final day = DateTime(at.year, at.month, at.day);

  if (day == DateTime(now.year, now.month, now.day)) {
    return DateFormat.Hm(locale).format(at);
  }

  if (day == DateTime(now.year, now.month, now.day - 1)) return yesterday;

  if (at.year == now.year) return DateFormat.MMMd(locale).format(at);

  return DateFormat.yMMMd(locale).format(at);
}
