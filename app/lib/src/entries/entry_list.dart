import 'package:intl/intl.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/scrollbar.dart';
import 'package:kronoer/src/ui/selection.dart';
import 'package:material_ui/material_ui.dart';

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// One row of the list: a month separator or an Entry card.
sealed class _Row {}

final class _MonthRow extends _Row {
  _MonthRow(this.month);

  final DateTime month;
}

final class _EntryRow extends _Row {
  _EntryRow(this.entry);

  final Entry entry;
}

/// [entries] come in order of Entry date, newest or oldest first, so each
/// month starts where the month of the Entry date changes.
List<_Row> _rows(List<Entry> entries) {
  final rows = <_Row>[];
  DateTime? month;

  for (final entry in entries) {
    final entryMonth = DateTime(entry.dateTime.year, entry.dateTime.month);
    if (entryMonth != month) {
      rows.add(_MonthRow(entryMonth));
      month = entryMonth;
    }
    rows.add(_EntryRow(entry));
  }

  return rows;
}

/// Entries as cards in [order], under a separator for each month, with a
/// scrollbar that shows the month at the top: a Book's Entries.
class EntryList extends StatefulWidget {
  const EntryList(
    this.entries, {
    super.key,
    required this.onOpen,
    this.order = EntryOrder.newestFirst,
    this.controller,
    this.bottomPadding = Space.xl,
    this.selection,
    this.onSelect,
  });

  /// In [order].
  final List<Entry> entries;

  /// The order [entries] come in. When it changes, the list goes back to the
  /// top.
  final EntryOrder order;

  final void Function(Entry entry) onOpen;

  /// Made and disposed by the list when not given.
  final ScrollController? controller;

  /// Room below the last card, for example for a FAB.
  final double bottomPadding;

  /// The selected Entries, as in a Book. While selection mode is on, a tap
  /// selects or deselects a card rather than opening it. Without it, cards
  /// only open.
  final Selection? selection;

  /// Selects or deselects an Entry: on a long press, or on a tap while
  /// [selection] is on. Without it, a long press does nothing.
  final void Function(Entry entry)? onSelect;

  @override
  State<EntryList> createState() => _EntryListState();
}

class _EntryListState extends State<EntryList> {
  ScrollController? _ownController;
  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  /// One key per card, so the scrollbar can find the card at the top.
  final _cardKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(EntryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final entry in widget.entries) entry.id};
    _cardKeys.removeWhere((id, _) => !ids.contains(id));
    if (widget.order != oldWidget.order && _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  /// The month of the first card that reaches below the top of the list.
  String? _monthAtTop() {
    final list = context.findRenderObject();
    if (list is! RenderBox) return null;

    for (final entry in widget.entries) {
      final card = _cardKeys[entry.id]?.currentContext?.findRenderObject();
      if (card is! RenderBox || !card.hasSize) continue;

      final bottom = card
          .localToGlobal(Offset(0, card.size.height), ancestor: list)
          .dy;
      if (bottom > 0) {
        return DateFormat.yMMM(_locale(context)).format(entry.dateTime);
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows(widget.entries);
    final selection = widget.selection;
    final selecting = selection?.isOn ?? false;
    final onSelect = widget.onSelect;

    return LabeledScrollbar(
      controller: _controller,
      label: _monthAtTop,
      child: ListView.separated(
        controller: _controller,
        // Room on the right for the scrollbar.
        padding: EdgeInsets.fromLTRB(
          Space.l,
          Space.xs,
          Space.xl,
          widget.bottomPadding,
        ),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.m),
        itemBuilder: (_, i) => switch (rows[i]) {
          _MonthRow(:final month) => _MonthSeparator(month),
          _EntryRow(:final entry) => _EntryCard(
            entry,
            selecting: selecting,
            badge: selection?.badges ?? false,
            selected: selection?.contains(entry.id) ?? false,
            onTap: selecting
                ? () => onSelect?.call(entry)
                : () => widget.onOpen(entry),
            onLongPress: onSelect == null ? null : () => onSelect(entry),
            key: _cardKeys.putIfAbsent(entry.id, GlobalKey.new),
          ),
        },
      ),
    );
  }
}

class _MonthSeparator extends StatelessWidget {
  const _MonthSeparator(this.month);

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, 0),
      child: Semantics(
        header: true,
        child: Text(
          DateFormat.yMMMM(_locale(context)).format(month),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One Entry's card. While [selecting], a [selected] card is tinted, and the
/// card carries a check over its top-left corner while [badge] is on. The
/// check lies over the card, so its contents stay where they are.
class _EntryCard extends StatelessWidget {
  const _EntryCard(
    this.entry, {
    required this.selecting,
    required this.selected,
    required this.badge,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final Entry entry;

  final bool selecting;
  final bool selected;

  /// Whether the card carries a [SelectionBadge]: while selection mode is
  /// on, or still fading out. It shows only on a [selected] card.
  final bool badge;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = _locale(context);
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final preview = previewRuns(entry.text);
    final previewStyle = theme.extension<EntryTextStyles>()!.entryPreview;
    final color = CardTheme.of(context).color ?? theme.colorScheme.surface;

    final card = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: selected ? selectedTint(theme) : color),
      duration: selectionDuration,
      curve: selectionCurve,
      builder: (_, color, content) => KCard(
        color: color,
        onTap: onTap,
        opens: !selecting,
        onLongPress: onLongPress,
        child: content!,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: Space.m,
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMM', locale).format(entry.dateTime),
                  style: meta?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Text(DateFormat.Hm(locale).format(entry.dateTime), style: meta),
            ],
          ),
          if (preview.isNotEmpty)
            Text.rich(
              TextStyleLook.of(context)
                  .span(preview, fontSize: previewStyle.fontSize),
              style: previewStyle,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          if (entry.imageIds.isNotEmpty) _CardImages(entry.id, entry.imageIds),
        ],
      ),
    );

    return Semantics(
      selected: selecting ? selected : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (badge)
            PositionedDirectional(
              start: -6,
              top: -6,
              child: SelectionBadge(
                selected: selected,
                ring: theme.colorScheme.surface,
              ),
            ),
        ],
      ),
    );
  }
}

/// One image fills the width; more go two by two.
class _CardImages extends StatelessWidget {
  const _CardImages(this.entryId, this.imageIds);

  final String entryId;
  final List<String> imageIds;

  Widget _image(String id, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(Radii.m),
    child: SizedBox(
      height: height,
      child: EntryImage(entryId: entryId, imageId: id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (imageIds.length == 1) return _image(imageIds.single, 150);

    return Column(
      spacing: Space.s,
      children: [
        for (var i = 0; i < imageIds.length; i += 2)
          Row(
            spacing: Space.s,
            children: [
              Expanded(child: _image(imageIds[i], 96)),
              Expanded(
                child: i + 1 < imageIds.length
                    ? _image(imageIds[i + 1], 96)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    );
  }
}
