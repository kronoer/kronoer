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

/// Deletes [entry] with undo: returns to its Book and shows "Entry dihapus ·
/// Urungkan". No confirmation dialog.
void deleteEntryWithUndo(BuildContext context, WidgetRef ref, Entry entry) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  // Read everything before leaving: this widget's ref goes with the screen.
  final entries = ref.read(entryRepositoryProvider);
  final pending = ref.read(pendingDeletionsProvider.notifier);

  pending.hide(entry.id);
  context.go(Routes.book(entry.bookId));

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

/// The ⋮ menu of an Entry, in the read view and the editor.
class EntryMenu extends StatelessWidget {
  const EntryMenu({required this.onDelete, super.key});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      menuChildren: [
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
