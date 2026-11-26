import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_copying.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The selection mode top bar of a list of Entries: back, how many are
/// selected, then "Star" or "Unstar", "Copy", "Move", and "Delete".
///
/// The star button stars the [selected] Entries while any of them is not
/// starred yet, and unstars them when all are. While the bar fades out after
/// the last Entry is deselected, it keeps the count and the star button it
/// showed.
class EntrySelectionBar extends StatefulWidget {
  const EntrySelectionBar({
    required this.selected,
    required this.onClose,
    required this.onStar,
    required this.onCopy,
    required this.onMove,
    required this.onDelete,
    super.key,
  });

  /// In the order the list shows them.
  final List<Entry> selected;
  final VoidCallback onClose;
  final void Function({required bool starred}) onStar;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  State<EntrySelectionBar> createState() => _EntrySelectionBarState();
}

class _EntrySelectionBarState extends State<EntrySelectionBar> {
  var _count = 0;
  var _stars = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    final selected = widget.selected;
    if (selected.isNotEmpty) {
      _count = selected.length;
      _stars = selected.any((entry) => !entry.starred);
    }
    final stars = _stars;

    return Row(
      children: [
        const SizedBox(width: Space.xs),
        BackButton(onPressed: widget.onClose),
        const SizedBox(width: Space.s),
        Expanded(
          child: Semantics(
            label: l10n.entriesSelected(_count),
            excludeSemantics: true,
            child: Text('$_count'),
          ),
        ),
        IconButton(
          tooltip: stars ? l10n.starEntries : l10n.unstarEntries,
          color: variant,
          onPressed: () => widget.onStar(starred: stars),
          icon: KIcon(stars ? KIcons.star : KIcons.starOff),
        ),
        IconButton(
          tooltip: l10n.copyEntries,
          color: variant,
          // Entries of Images only have no text to copy.
          onPressed: selected.any(hasText) ? widget.onCopy : null,
          icon: const KIcon(KIcons.copy),
        ),
        IconButton(
          tooltip: l10n.moveEntries,
          color: variant,
          onPressed: widget.onMove,
          icon: const KIcon(KIcons.bookArrowRight),
        ),
        IconButton(
          tooltip: l10n.deleteEntries,
          color: variant,
          onPressed: widget.onDelete,
          icon: const KIcon(KIcons.bin),
        ),
        const SizedBox(width: Space.xs),
      ],
    );
  }
}
