import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_list_menu.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/timeline/date_strip.dart';
import 'package:kronoer/src/timeline/day_line.dart';
import 'package:kronoer/src/timeline/timeline_rows.dart';
import 'package:material_ui/material_ui.dart';

/// The earliest day with an Entry in the Timeline.
final oldestTimelineDayProvider = StreamProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(entryRepositoryProvider).watchOldestTimelineDay(),
);

/// The days with an Entry in the Timeline, from the first day to the last.
final timelineDaysProvider = StreamProvider.autoDispose
    .family<Set<DateTime>, (DateTime, DateTime)>(
      (ref, range) => ref
          .watch(entryRepositoryProvider)
          .watchTimelineDays(range.$1, range.$2),
    );

/// Linimasa: every Entry from every Book on a time line, under its day.
/// Every day shows, from today back to the oldest Entry; long runs of days
/// with no Entry are one row. The date strip above the list follows it, and
/// moves it to a day, a month, or a year. Writing happens inside a Book, so
/// there is no FAB.
///
/// It opens on today, at the day level. The order is not stored: it lasts
/// until the app closes, and turns only the list around. Books the user
/// keeps out of the Timeline, from Book info or "Book di Linimasa", are left
/// out.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final _sliverKey = GlobalKey();
  StripLevel _level = StripLevel.day;

  /// The day the strip shows: the topmost day in the list, or the one picked
  /// last. Today until then.
  DateTime? _highlight;

  /// While the list is moved to a row: its scrolling moves no highlight.
  bool _jumping = false;

  TimelineRows? _rows;

  ScrollController get _controller => PrimaryScrollController.of(context);

  RenderSliverMultiBoxAdaptor? get _sliver {
    final sliver = _sliverKey.currentContext?.findRenderObject();
    return sliver is RenderSliverMultiBoxAdaptor && sliver.geometry != null
        ? sliver
        : null;
  }

  /// The index of the topmost row on screen.
  int? _topRow() {
    final sliver = _sliver;
    if (sliver == null) return null;
    final top = sliver.constraints.scrollOffset;
    for (var child = sliver.firstChild; child != null;) {
      final offset = sliver.childScrollOffset(child)!;
      if (offset + child.size.height > top + 0.5) return sliver.indexOf(child);
      child = sliver.childAfter(child);
    }
    return null;
  }

  /// Moves the list so the row at [index] is at the top, or as near as the
  /// list goes. Rows have no fixed height, so a row not laid out yet is
  /// reached by jumping to where it should be until it is.
  Future<void> _jumpToRow(int index) async {
    _jumping = true;
    try {
      for (var attempt = 0; attempt < 12; attempt++) {
        final sliver = _sliver;
        if (!mounted || sliver == null || !_controller.hasClients) return;
        final position = _controller.position;
        RenderBox? first, last;
        for (var child = sliver.firstChild; child != null;) {
          if (sliver.indexOf(child) == index) {
            position.jumpTo(
              sliver
                  .childScrollOffset(child)!
                  .clamp(position.minScrollExtent, position.maxScrollExtent),
            );
            return;
          }
          first ??= child;
          last = child;
          child = sliver.childAfter(child);
        }
        if (first == null || last == null) return;

        final firstIndex = sliver.indexOf(first);
        final lastIndex = sliver.indexOf(last);
        final from = sliver.childScrollOffset(first)!;
        final to = sliver.childScrollOffset(last)! + last.size.height;
        final perRow = (to - from) / (lastIndex - firstIndex + 1);
        final guess = index < firstIndex
            ? from - (firstIndex - index) * perRow
            : to + (index - lastIndex - 1) * perRow;
        position.jumpTo(
          guess.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _jumping = false;
    }
  }

  /// Whether the highlight follows the list once this frame is laid out.
  bool _followPending = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || _jumping || _followPending) return false;
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }
    // The list lays out its rows at the new place only after this.
    _followPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followPending = false;
      final rows = _rows;
      final index = _topRow();
      if (!mounted || _jumping || rows == null || index == null) return;
      if (index >= rows.rows.length) return;
      final day = rows.rows[index].day;
      if (day != _highlight) setState(() => _highlight = day);
    });
    WidgetsBinding.instance.scheduleFrame();
    return false;
  }

  /// Highlights [day] and moves the list to it.
  void _goTo(DateTime day, {StripLevel? level}) {
    final index = _rows?.rowOf(day);
    setState(() {
      _highlight = day;
      if (level != null) _level = level;
    });
    if (index != null) _jumpToRow(index);
  }

  /// To the first day of [from] to [to] in the list's order.
  void _goToSpan(DateTime from, DateTime to, StripLevel level) {
    final rows = _rows;
    if (rows == null) return;
    if (from.isBefore(rows.oldest)) from = rows.oldest;
    if (to.isAfter(rows.newest)) to = rows.newest;
    final newestFirst =
        ref.read(timelineOrderProvider) == EntryOrder.newestFirst;
    _goTo(newestFirst ? to : from, level: level);
  }

  void _backToToday() {
    final today = dayOf(ref.read(clockProvider)());
    final index = _rows?.rowOf(today);
    setState(() {
      _level = StripLevel.day;
      _highlight = today;
    });
    if (index == null || !_controller.hasClients) return;
    if (index == 0) {
      _jumping = true;
      _controller
          .animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _jumping = false);
    } else {
      _jumpToRow(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final order = ref.watch(timelineOrderProvider);
    final entries = ref.watch(allEntriesProvider).value;
    final books = ref.watch(bookSummariesProvider).value ?? const [];
    final names = {
      for (final summary in books) summary.book.id: summary.book.name,
    };
    // There are Entries, but every Book is kept out of the Timeline.
    final allKeptOut =
        books.any((summary) => summary.entryCount > 0) &&
        books.every((summary) => !summary.book.inTimeline);
    final today = dayOf(ref.watch(clockProvider)());

    // A new order starts at the top of the list.
    ref.listen(timelineOrderProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpTo(0);
        final rows = _rows;
        if (rows != null && rows.rows.isNotEmpty) {
          setState(() => _highlight = rows.rows.first.day);
        }
      });
    });

    final appBar = AppBar(
      titleSpacing: 20,
      title: Text(l10n.timeline),
      actionsPadding: const EdgeInsets.only(right: Space.s),
      actions: [
        EntryListMenu(
          hasEntries: entries?.isNotEmpty ?? false,
          order: order,
          onOrder: ref.read(timelineOrderProvider.notifier).set,
          // Pushed, so back comes here and not to the Book tab.
          onSearch: () => context.push(Routes.search()),
          onTimelineBooks: books.isEmpty
              ? null
              : () => context.push(Routes.timelineBooks),
        ),
      ],
    );
    if (entries == null) return Scaffold(appBar: appBar);

    final rows = _rows = timelineRows(
      entries,
      today: today,
      order: order,
      oldest: ref.watch(oldestTimelineDayProvider).value,
    );
    final days =
        ref.watch(timelineDaysProvider((rows.oldest, rows.newest))).value ??
        const {};
    var highlight = _highlight ?? today;
    if (highlight.isBefore(rows.oldest)) highlight = rows.oldest;
    if (highlight.isAfter(rows.newest)) highlight = rows.newest;

    Widget row(TimelineRow row) => switch (row) {
      DayHeadingRow() => DayHeading(row, today: today),
      EntryLineRow(:final entry) => EntryLine(
        row,
        bookName: names[entry.bookId],
        // Pushed, so back returns here at the same place.
        onTap: () => context.push(Routes.entry(entry.bookId, entry.id)),
      ),
      EmptyRangeRow() => EmptyRange(row, today: today),
      NoEntryRow() => NoEntryInfo(
        title: allKeptOut ? l10n.timelineNoBooksShown : l10n.timelineEmptyTitle,
        message: allKeptOut ? null : l10n.timelineEmptyMessage,
      ),
    };

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          DateStrip(
            level: _level,
            highlight: highlight,
            oldest: rows.oldest,
            newest: rows.newest,
            days: days,
            onLevel: (level) => setState(() => _level = level),
            onDay: _goTo,
            onMonth: (month) => _goToSpan(
              month,
              DateTime(month.year, month.month + 1, 0),
              StripLevel.day,
            ),
            onYear: (year) => _goToSpan(
              DateTime(year),
              DateTime(year, 12, 31),
              StripLevel.month,
            ),
          ),
          Expanded(
            child: ScrollToTopOnReselect(
              onReselect: _backToToday,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: CustomScrollView(
                  controller: _controller,
                  slivers: [
                    SliverList(
                      key: _sliverKey,
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => row(rows.rows[i]),
                        childCount: rows.rows.length,
                      ),
                    ),
                    const SliverPadding(
                      padding: EdgeInsets.only(bottom: Space.xl),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
