import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The ⋮ menu in the app bar of a list of Entries: a Book or the Timeline.
///
/// It has Book info when [onInfo] is given, then Search and Sort when the
/// list has Entries, then "Book di Linimasa" when [onTimelineBooks] is given.
/// Sort opens a submenu with the two orders, the current one checked. With
/// nothing to show, there is no button at all.
class EntryListMenu extends StatelessWidget {
  const EntryListMenu({
    required this.hasEntries,
    required this.order,
    required this.onOrder,
    required this.onSearch,
    this.onInfo,
    this.onTimelineBooks,
    super.key,
  });

  /// Whether Search and Sort show: an empty list has nothing to find or sort.
  final bool hasEntries;
  final EntryOrder order;
  final ValueChanged<EntryOrder> onOrder;
  final VoidCallback onSearch;
  final VoidCallback? onInfo;

  /// Opens "Book di Linimasa". It shows even when the list is empty: with
  /// every Book kept out of the Timeline, it is the way back.
  final VoidCallback? onTimelineBooks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onInfo = this.onInfo;
    final onTimelineBooks = this.onTimelineBooks;
    if (onInfo == null && onTimelineBooks == null && !hasEntries) {
      return const SizedBox.shrink();
    }

    Widget orderItem(EntryOrder value, String label) {
      final current = value == order;
      return Semantics(
        checked: current,
        child: MenuItemButton(
          onPressed: () => onOrder(value),
          trailingIcon: current ? const KIcon(KIcons.check) : null,
          child: Text(label),
        ),
      );
    }

    return MenuAnchor(
      menuChildren: [
        if (onInfo != null)
          MenuItemButton(onPressed: onInfo, child: Text(l10n.bookInfo)),
        if (hasEntries) ...[
          MenuItemButton(onPressed: onSearch, child: Text(l10n.search)),
          SubmenuButton(
            submenuIcon: const WidgetStatePropertyAll(
              KIcon(KIcons.chevronRight, size: 20),
            ),
            menuChildren: [
              orderItem(EntryOrder.newestFirst, l10n.newestFirst),
              orderItem(EntryOrder.oldestFirst, l10n.oldestFirst),
            ],
            child: Text(l10n.sortEntries),
          ),
        ],
        if (onTimelineBooks != null)
          MenuItemButton(
            onPressed: onTimelineBooks,
            child: Text(l10n.booksInTimeline),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: l10n.moreOptions,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const KIcon(KIcons.moreVertical),
      ),
    );
  }
}
