import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/trash/trash_actions.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// Closes the top [screens] screens of an Entry (its read view, editor, or
/// viewer), back to whatever opened them: the Book, the Timeline, or a
/// search. With nothing under them, goes to the Entry's Book.
void closeEntryScreens(BuildContext context, String bookId, {int screens = 1}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (!navigator.canPop()) {
    context.go(Routes.book(bookId));
    return;
  }
  for (var i = 0; i < screens && navigator.canPop(); i++) {
    navigator.pop();
  }
}

/// Moves [entry] to the Trash with undo: closes its [screens] screens and
/// shows "Entry dipindahkan ke Sampah · Urungkan". No confirmation dialog.
Future<void> deleteEntryWithUndo(
  BuildContext context,
  WidgetRef ref,
  Entry entry, {
  int screens = 1,
}) => trashEntriesWithUndo(
  context,
  ref,
  [entry.id],
  onTrashed: () {
    if (context.mounted) {
      closeEntryScreens(context, entry.bookId, screens: screens);
    }
  },
);

/// The ⋮ menu of an Entry, in the read view and the editor. As in the read
/// view, it starts with "Beri bintang" or, for a [starred] Entry, "Hapus
/// bintang" when [onStar] is given, then has "Salin teks" when [onCopy] is
/// and "Pindahkan ke Book lain" when [onMove] is.
class EntryMenu extends StatelessWidget {
  const EntryMenu({
    required this.onDelete,
    this.onMove,
    this.onCopy,
    this.onStar,
    this.starred = false,
    super.key,
  });

  final VoidCallback onDelete;
  final VoidCallback? onMove;
  final VoidCallback? onCopy;
  final VoidCallback? onStar;
  final bool starred;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onMove = this.onMove;
    final onCopy = this.onCopy;
    final onStar = this.onStar;

    return MenuAnchor(
      menuChildren: [
        if (onStar != null)
          MenuItemButton(
            leadingIcon: KIcon(starred ? KIcons.starOff : KIcons.star),
            onPressed: onStar,
            child: Text(starred ? l10n.unstarEntry : l10n.starEntry),
          ),
        if (onCopy != null)
          MenuItemButton(
            leadingIcon: const KIcon(KIcons.copy),
            onPressed: onCopy,
            child: Text(l10n.copyEntryText),
          ),
        if (onMove != null)
          MenuItemButton(
            leadingIcon: const KIcon(KIcons.bookArrowRight),
            onPressed: onMove,
            child: Text(l10n.moveToAnotherBook),
          ),
        MenuItemButton(
          style: destructiveMenuItem(scheme),
          leadingIcon: const KIcon(KIcons.bin),
          onPressed: onDelete,
          child: Text(l10n.deleteEntry),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: l10n.entryMenu,
        color: scheme.onSurfaceVariant,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const KIcon(KIcons.moreVertical),
      ),
    );
  }
}
