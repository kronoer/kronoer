import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/star_mark.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/timeline/timeline_rows.dart';
import 'package:material_ui/material_ui.dart';

/// The Timeline's left edge; the right one leaves room for a thumb.
const _start = 20.0;
const _end = Space.xl;

/// The time column, then the dot and line column.
const _timeWidth = 40.0;
const _lineWidth = 22.0;

/// Where an Entry's dot sits, from the top of its row.
const _dotCenter = 10.0;

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// A day's name: today, yesterday, or its weekday.
String _dayTitle(BuildContext context, DateTime day, DateTime today) {
  final l10n = AppLocalizations.of(context);
  if (day == today) return l10n.timelineToday;
  if (day == addDays(today, -1)) return l10n.timelineYesterday;
  return DateFormat.EEEE(_locale(context)).format(day);
}

/// A day's date under its name: with the weekday when the name is today or
/// yesterday, and with the year only when it is not this year's.
String _dayDate(BuildContext context, DateTime day, DateTime today) {
  final named = day == today || day == addDays(today, -1);
  final year = day.year == today.year ? '' : ' y';
  return DateFormat(
    '${named ? 'EEEE, ' : ''}d MMMM$year',
    _locale(context),
  ).format(day);
}

/// A day's heading. A day with no Entry is one faded line.
class DayHeading extends StatelessWidget {
  const DayHeading(this.row, {required this.today, super.key});

  final DayHeadingRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = _dayTitle(context, row.day, today);
    final date = _dayDate(context, row.day, today);

    if (row.empty) return _FadedRow(title: title, detail: date);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_start, Space.s, _end, 10),
      child: MergeSemantics(
        child: Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  height: 28 / 20,
                  color: row.day == today ? scheme.primary : scheme.onSurface,
                ),
              ),
              Text(
                date,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A run of days with no Entry, such as "28 Okt – 9 Nov".
class EmptyRange extends StatelessWidget {
  const EmptyRange(this.row, {required this.today, super.key});

  final EmptyRangeRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final thisYear = row.from.year == today.year && row.to.year == today.year;
    final format = DateFormat(thisYear ? 'd MMM' : 'd MMM y', _locale(context));
    return _FadedRow(
      title: '${format.format(row.from)} – ${format.format(row.to)}',
      semanticsLabel: AppLocalizations.of(context).timelineStripNoEntry(
        '${format.format(row.from)} – ${format.format(row.to)}',
      ),
    );
  }
}

class _FadedRow extends StatelessWidget {
  const _FadedRow({required this.title, this.detail, this.semanticsLabel});

  final String title;
  final String? detail;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final detail = this.detail;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_start, Space.xs, _end, 10),
      child: Opacity(
        opacity: 0.7,
        child: Semantics(
          label: semanticsLabel,
          excludeSemantics: semanticsLabel != null,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: title),
                if (detail != null)
                  TextSpan(
                    text: '  $detail',
                    style: const TextStyle(fontWeight: FontWeight.w400),
                  ),
              ],
            ),
            style: theme.textTheme.titleSmall?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

/// Under today's heading while the Timeline has no Entry.
class NoEntryInfo extends StatelessWidget {
  const NoEntryInfo({required this.title, this.message, super.key});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = this.message;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _start + _timeWidth + _lineWidth,
        0,
        _end,
        Space.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.xs,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 15,
              height: 22 / 15,
            ),
          ),
          if (message != null)
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// One Entry on its day's time line: the time, a dot on the line that joins
/// the day's Entries, then the Book's name, the text, and the Images.
class EntryLine extends StatelessWidget {
  const EntryLine(
    this.row, {
    required this.bookName,
    required this.onTap,
    super.key,
  });

  final EntryLineRow row;
  final String? bookName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = row.entry;
    final preview = previewRuns(entry.text);
    final previewStyle = theme.extension<EntryTextStyles>()!.entryPreview;
    final bookName = this.bookName;
    final line = ColoredBox(color: scheme.outlineVariant);
    const lineLeft = _timeWidth + 7;

    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(_start, 0, _end, row.last ? Space.m : 0),
          child: Stack(
            children: [
              if (!row.first)
                Positioned(
                  left: lineLeft,
                  top: 0,
                  width: 2,
                  height: _dotCenter,
                  child: line,
                ),
              if (!row.last)
                Positioned(
                  left: lineLeft,
                  top: _dotCenter,
                  bottom: 0,
                  width: 2,
                  child: line,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _timeWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      // The time column is too narrow for the star beside
                      // the time, so it goes under it.
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.xs,
                        children: [
                          Text(
                            DateFormat.Hm(_locale(context))
                                .format(entry.dateTime.toLocal()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 20 / 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (entry.starred) const StarMark(),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _lineWidth,
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Container(
                        margin: const EdgeInsets.only(top: _dotCenter - 8),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 3),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.xs,
                        children: [
                          if (bookName != null)
                            Text(
                              bookName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 20 / 13,
                                fontWeight: FontWeight.w500,
                                color: scheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (preview.isNotEmpty)
                            Text.rich(
                              TextStyleLook.of(
                                context,
                              ).span(preview, fontSize: previewStyle.fontSize),
                              style: previewStyle,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (entry.imageIds.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: Space.xs),
                              child: _LineImages(
                                entry.id,
                                entry.imageIds,
                                size: preview.isEmpty ? 96 : 72,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Up to three Images in a row; the third says how many more there are.
class _LineImages extends StatelessWidget {
  const _LineImages(this.entryId, this.imageIds, {required this.size});

  static const _shown = 3;

  final String entryId;
  final List<String> imageIds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final more = imageIds.length - _shown;

    return Row(
      spacing: 6,
      children: [
        for (final (i, id) in imageIds.take(_shown).indexed)
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.m),
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EntryImage(entryId: entryId, imageId: id),
                  if (i == _shown - 1 && more > 0)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: Text(
                          '+$more',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
