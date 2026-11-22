import 'package:flutter/foundation.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_repository.dart';

/// The local day [time] falls on, as that day's midnight.
DateTime dayOf(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// [day] moved by [days], staying at midnight across daylight saving.
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// A run of this many empty days or more is one row.
const emptyRangeMinDays = 7;

/// One row of the Timeline.
@immutable
sealed class TimelineRow {
  const TimelineRow(this.day);

  /// The day the date strip shows while this row is the topmost one.
  final DateTime day;
}

/// A day's heading. An [empty] day has no Entry and is a faded row.
final class DayHeadingRow extends TimelineRow {
  const DayHeadingRow(super.day, {required this.empty});

  final bool empty;
}

/// An Entry on the time line, the [first] and the [last] of its day.
final class EntryLineRow extends TimelineRow {
  const EntryLineRow(
    this.entry,
    super.day, {
    required this.first,
    required this.last,
  });

  final Entry entry;
  final bool first;
  final bool last;
}

/// A run of [emptyRangeMinDays] or more days with no Entry, from the
/// earliest, [from], to the latest, [to].
final class EmptyRangeRow extends TimelineRow {
  const EmptyRangeRow(super.day, {required this.from, required this.to});

  final DateTime from;
  final DateTime to;
}

/// Under today's heading when the Timeline has no Entry.
final class NoEntryRow extends TimelineRow {
  const NoEntryRow(super.day);
}

/// The Timeline's rows, and where each of its days is.
@immutable
class TimelineRows {
  const TimelineRows._(this.rows, this._rowOfDay, this.oldest, this.newest);

  final List<TimelineRow> rows;
  final Map<DateTime, int> _rowOfDay;

  /// The earliest and the latest day the Timeline covers.
  final DateTime oldest;
  final DateTime newest;

  /// The index of the row [day] is on: its heading, or the run of empty days
  /// it is in. Null outside [oldest] to [newest].
  int? rowOf(DateTime day) => _rowOfDay[day];
}

/// The Timeline's rows for [entries], which come in [order].
///
/// Every day shows, from the later of [today] and the newest Entry's day
/// back to the earliest of the oldest Entry's day, [oldest] when given, and
/// the 1st of this month. Today always has its own row; other runs of
/// [emptyRangeMinDays] or more empty days are one row each. Oldest first
/// turns the days around, and each day's Entries come in [order].
TimelineRows timelineRows(
  List<Entry> entries, {
  required DateTime today,
  required EntryOrder order,
  DateTime? oldest,
}) {
  today = dayOf(today);
  final byDay = <DateTime, List<Entry>>{};
  for (final entry in entries) {
    (byDay[dayOf(entry.dateTime)] ??= []).add(entry);
  }

  var newest = today;
  var first = DateTime(today.year, today.month);
  if (oldest != null && oldest.isBefore(first)) first = oldest;
  for (final day in byDay.keys) {
    if (day.isAfter(newest)) newest = day;
    if (day.isBefore(first)) first = day;
  }

  // Newest first, one block of rows per day or run of empty days.
  final blocks = <List<TimelineRow>>[];
  final daysOfBlock = <List<DateTime>>[];
  for (var day = newest; !day.isBefore(first);) {
    final dayEntries = byDay[day];
    if (dayEntries != null) {
      blocks.add([
        DayHeadingRow(day, empty: false),
        for (final (i, entry) in dayEntries.indexed)
          EntryLineRow(
            entry,
            day,
            first: i == 0,
            last: i == dayEntries.length - 1,
          ),
      ]);
      daysOfBlock.add([day]);
      day = addDays(day, -1);
      continue;
    }
    if (day == today) {
      blocks.add([
        DayHeadingRow(day, empty: entries.isNotEmpty),
        if (entries.isEmpty) NoEntryRow(day),
      ]);
      daysOfBlock.add([day]);
      day = addDays(day, -1);
      continue;
    }

    // A run of empty days, down to a day with Entries, today, or the end.
    final run = <DateTime>[];
    while (!day.isBefore(first) && byDay[day] == null && day != today) {
      run.add(day);
      day = addDays(day, -1);
    }
    if (run.length >= emptyRangeMinDays) {
      final (from, to) = (run.last, run.first);
      blocks.add([
        EmptyRangeRow(
          order == EntryOrder.newestFirst ? to : from,
          from: from,
          to: to,
        ),
      ]);
      daysOfBlock.add(run);
    } else {
      for (final empty in run) {
        blocks.add([DayHeadingRow(empty, empty: true)]);
        daysOfBlock.add([empty]);
      }
    }
  }

  final inOrder = order == EntryOrder.newestFirst
      ? blocks.indexed
      : blocks.indexed.toList().reversed;
  final rows = <TimelineRow>[];
  final rowOfDay = <DateTime, int>{};
  for (final (i, block) in inOrder) {
    for (final day in daysOfBlock[i]) {
      rowOfDay[day] = rows.length;
    }
    rows.addAll(block);
  }
  return TimelineRows._(rows, rowOfDay, first, newest);
}
