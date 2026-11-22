import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The IDs of Entries deleted while their "Urungkan" is still on screen.
///
/// The repository cannot bring back a deleted Entry as it was (its ID and
/// Images go with it), so a deleted Entry is only hidden until the snackbar
/// closes, and deleted from the repository then. If the app dies before
/// that, the Entry is still there on the next launch.
class PendingDeletions extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void hide(String entryId) => state = {...state, entryId};

  void show(String entryId) => state = {...state}..remove(entryId);
}

final pendingDeletionsProvider =
    NotifierProvider<PendingDeletions, Set<String>>(PendingDeletions.new);

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

/// Deletes [entry] with undo: closes its [screens] screens and shows "Entry
/// dihapus · Urungkan". No confirmation dialog.
void deleteEntryWithUndo(
  BuildContext context,
  WidgetRef ref,
  Entry entry, {
  int screens = 1,
}) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  // Read everything before leaving: this widget's ref goes with the screen.
  final entries = ref.read(entryRepositoryProvider);
  final pending = ref.read(pendingDeletionsProvider.notifier);

  pending.hide(entry.id);
  closeEntryScreens(context, entry.bookId, screens: screens);

  messenger.hideCurrentSnackBar();
  final snackBar = messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.entryDeleted),
      // Let it time out, so the delete is not held back for long.
      persist: false,
      action: SnackBarAction(label: l10n.undo, onPressed: () {}),
    ),
  );

  snackBar.closed.then((reason) async {
    if (reason != SnackBarClosedReason.action) {
      await entries.deleteEntry(entry.id);
    }
    pending.show(entry.id);
  });
}

/// The ⋮ menu of an Entry, in the read view and the editor. It has "Pindahkan
/// ke Book lain" when [onMove] is given, as in the read view.
class EntryMenu extends StatelessWidget {
  const EntryMenu({required this.onDelete, this.onMove, super.key});

  final VoidCallback onDelete;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onMove = this.onMove;

    return MenuAnchor(
      menuChildren: [
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
