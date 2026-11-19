import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kronoer/src/books/activity_time.dart';

void main() {
  setUpAll(initializeDateFormatting);

  String format(DateTime at, {DateTime? now, String locale = 'id'}) =>
      formatActivityTime(
        at,
        now: now ?? DateTime(2026, 11, 19, 20),
        locale: locale,
        yesterday: 'Kemarin',
      );

  test('today shows the time in the locale format', () {
    expect(format(DateTime(2026, 11, 19, 14, 32)), '14.32');
    expect(format(DateTime(2026, 11, 19, 14, 32), locale: 'en'), '14:32');
  });

  test('just after midnight is still today', () {
    expect(format(DateTime(2026, 11, 19, 0, 5)), '00.05');
  });

  test('yesterday, also across a month and a year', () {
    expect(format(DateTime(2026, 11, 18, 23, 59)), 'Kemarin');
    expect(
      format(DateTime(2026, 10, 31, 8), now: DateTime(2026, 11, 1, 9)),
      'Kemarin',
    );
    expect(
      format(DateTime(2025, 12, 31, 22), now: DateTime(2026, 1, 1, 1)),
      'Kemarin',
    );
  });

  test('earlier this year shows day and month', () {
    expect(format(DateTime(2026, 11, 17, 9)), '17 Nov');
    expect(format(DateTime(2026, 11, 12, 9), locale: 'en'), 'Nov 12');
  });

  test('an earlier year adds the year', () {
    expect(format(DateTime(2025, 11, 12, 9)), '12 Nov 2025');
  });
}
