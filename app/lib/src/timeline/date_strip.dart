import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/timeline/timeline_rows.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// What the date strip shows: the days of one month, the months of one
/// year, or the years.
enum StripLevel { day, month, year }

/// The date crumbs, such as "Semua tahun › 2026 › November", over a strip
/// that scrolls sideways, newest on the right. A crumb goes up a level; a
/// month or a year in the strip goes down one.
///
/// It shows where [highlight] is: its month's days, its year's months, or
/// every year, from [oldest] to [newest] only. A day, month, or year with an
/// Entry, as [days] tells, has a dot.
class DateStrip extends StatefulWidget {
  const DateStrip({
    super.key,
    required this.level,
    required this.highlight,
    required this.oldest,
    required this.newest,
    required this.days,
    required this.onLevel,
    required this.onDay,
    required this.onMonth,
    required this.onYear,
  });

  final StripLevel level;
  final DateTime highlight;
  final DateTime oldest;
  final DateTime newest;

  /// The days with an Entry.
  final Set<DateTime> days;

  /// A crumb was tapped: go up to this level.
  final ValueChanged<StripLevel> onLevel;

  final ValueChanged<DateTime> onDay;

  /// A month was tapped, as its 1st.
  final ValueChanged<DateTime> onMonth;

  final ValueChanged<int> onYear;

  @override
  State<DateStrip> createState() => _DateStripState();
}

typedef _Item = ({
  String key,
  String top,
  String main,
  String label,
  bool has,
  bool selected,
  VoidCallback onTap,
});

class _DateStripState extends State<DateStrip> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  @override
  void didUpdateWidget(DateStrip old) {
    super.didUpdateWidget(old);
    final moved =
        widget.level != old.level ||
        (widget.level == StripLevel.day &&
            (widget.highlight.year, widget.highlight.month) !=
                (old.highlight.year, old.highlight.month)) ||
        (widget.level == StripLevel.month &&
            widget.highlight.year != old.highlight.year);
    if (moved || widget.highlight != old.highlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: moved));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _itemWidth => switch (widget.level) {
    StripLevel.day => 44,
    StripLevel.month => 56,
    StripLevel.year => 76,
  };

  /// Scrolls the strip so the selected item shows, in the middle when it
  /// was out of sight; at once when the strip shows something else now.
  void _reveal({required bool jump}) {
    if (!mounted || !_controller.hasClients) return;
    final index = _items(context).indexWhere((item) => item.selected);
    if (index < 0) return;
    final position = _controller.position;
    final width = _itemWidth;
    final start = Space.m + index * width;
    final visible =
        start >= position.pixels &&
        start + width <= position.pixels + position.viewportDimension;
    if (visible) return;
    final target = (start + width / 2 - position.viewportDimension / 2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (jump) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// The strip's items, newest first.
  List<_Item> _items(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final highlight = widget.highlight;
    final (oldest, newest) = (widget.oldest, widget.newest);
    String label(String name, bool has) =>
        has ? name : l10n.timelineStripNoEntry(name);

    switch (widget.level) {
      case StripLevel.day:
        final (year, month) = (highlight.year, highlight.month);
        var last = DateTime(year, month + 1, 0);
        if (last.isAfter(newest)) last = newest;
        var first = DateTime(year, month);
        if (first.isBefore(oldest)) first = oldest;
        return [
          // Each item has its own day, for its tap.
          for (var day = last; !day.isBefore(first); day = addDays(day, -1))
            (
              key: '$day',
              top: DateFormat.E(locale).format(day),
              main: '${day.day}',
              label: label(
                DateFormat.yMMMMEEEEd(locale).format(day),
                widget.days.contains(day),
              ),
              has: widget.days.contains(day),
              selected: day == highlight,
              onTap: () => widget.onDay(day),
            ),
        ];
      case StripLevel.month:
        final year = highlight.year;
        final months = {
          for (final day in widget.days)
            if (day.year == year) day.month,
        };
        final last = year == newest.year ? newest.month : 12;
        final first = year == oldest.year ? oldest.month : 1;
        return [
          for (var month = last; month >= first; month--)
            (
              key: '$year-$month',
              top: '',
              main: DateFormat.MMM(locale).format(DateTime(year, month)),
              label: label(
                DateFormat.yMMMM(locale).format(DateTime(year, month)),
                months.contains(month),
              ),
              has: months.contains(month),
              selected: month == highlight.month,
              onTap: () => widget.onMonth(DateTime(year, month)),
            ),
        ];
      case StripLevel.year:
        final years = {for (final day in widget.days) day.year};
        return [
          for (var year = newest.year; year >= oldest.year; year--)
            (
              key: '$year',
              top: '',
              main: '$year',
              label: label('$year', years.contains(year)),
              has: years.contains(year),
              selected: year == highlight.year,
              onTap: () => widget.onYear(year),
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final scheme = Theme.of(context).colorScheme;
    final level = widget.level;
    final items = _items(context);

    final crumbs = [
      (l10n.timelineAllYears, StripLevel.year),
      if (level != StripLevel.year)
        ('${widget.highlight.year}', StripLevel.month),
      if (level == StripLevel.day)
        (DateFormat.MMMM(locale).format(widget.highlight), StripLevel.day),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            // They start on the left; with large text they scroll, and the
            // last one shows.
            child: LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(
                  Space.m,
                  0,
                  Space.m,
                  Space.xs,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth - 2 * Space.m,
                  ),
                  child: Row(
                    spacing: 2,
                    children: [
                      for (final (i, (name, to)) in crumbs.indexed) ...[
                        if (i > 0)
                          KIcon(
                            KIcons.chevronRight,
                            size: 16,
                            color: scheme.outline,
                          ),
                        _Crumb(
                          name,
                          onTap: i == crumbs.length - 1
                              ? null
                              : () => widget.onLevel(to),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 74,
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              itemExtent: _itemWidth,
              itemCount: items.length,
              itemBuilder: (_, i) =>
                  _StripItem(items[i], key: ValueKey(items[i].key)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb(this.name, {required this.onTap});

  final String name;

  /// Null for the last crumb: where the strip already is.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Space.s),
          alignment: Alignment.center,
          child: Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 15,
              color: onTap == null ? scheme.onSurface : scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  const _StripItem(this.item, {super.key});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = item.selected;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(Radii.m),
        child: Opacity(
          opacity: item.has || selected ? 1 : 0.5,
          child: Column(
            spacing: 2,
            children: [
              SizedBox(
                height: 16,
                child: Text(
                  item.top,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 36),
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : null,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.main,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: item.has ? scheme.primary : null,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
