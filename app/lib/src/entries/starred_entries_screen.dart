import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_copying.dart';
import 'package:kronoer/src/entries/entry_list.dart';
import 'package:kronoer/src/entries/entry_moving.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/entries/entry_selection.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/trash/trash_actions.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/selection.dart';
import 'package:material_ui/material_ui.dart';

/// "Entry berbintang": the Starred Entries of one Book as cards, newest
/// first, under a separator for each month. A tap opens an Entry's read
/// view.
///
/// A long press starts the same selection mode as the Book's. Unstarring
/// there says so, with Urungkan to star the Entries again.
class StarredEntriesScreen extends ConsumerStatefulWidget {
  const StarredEntriesScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<StarredEntriesScreen> createState() =>
      _StarredEntriesScreenState();
}

class _StarredEntriesScreenState extends ConsumerState<StarredEntriesScreen>
    with SingleTickerProviderStateMixin {
  late final _selection = Selection(
    vsync: this,
    onChanged: () => setState(() {}),
  );

  String get _bookId => widget.bookId;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _copy(List<Entry> entries) async {
    final copied = await copyEntriesText(context, ref, entries);
    if (copied && mounted) _selection.clear();
  }

  Future<void> _move(List<String> ids) => moveEntriesWithUndo(
    context,
    ref,
    ids,
    fromBookId: _bookId,
    onMoved: () {
      if (mounted) _selection.clear();
    },
  );

  /// Every selected Entry here is starred, so this unstars them, unless
  /// one was unstarred elsewhere in the meantime.
  Future<void> _star(List<String> ids, {required bool starred}) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Read before waiting: this screen may be gone by the time to undo.
    final entries = ref.read(entryRepositoryProvider);
    _selection.clear();
    await entries.setEntriesStarred(ids, starred: starred);
    if (starred) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.starsRemoved(ids.length)),
          persist: false,
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () =>
                unawaited(entries.setEntriesStarred(ids, starred: true)),
          ),
        ),
      );
  }

  /// Moves [ids] to the Trash, with no confirmation, and ends selection
  /// mode.
  Future<void> _delete(List<String> ids) => trashEntriesWithUndo(
    context,
    ref,
    ids,
    onTrashed: () {
      if (mounted) _selection.clear();
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(starredEntriesProvider(_bookId)).value;
    final selecting = _selection.isOn;

    // A selected Entry no longer here, unstarred, moved, or deleted, here or
    // elsewhere, is no longer selected.
    ref.listen(starredEntriesProvider(_bookId), (_, next) {
      final entries = next.value;
      if (entries == null) return;
      _selection.retain({for (final entry in entries) entry.id});
    });

    final selectedEntries = [
      for (final entry in entries ?? const <Entry>[])
        if (_selection.contains(entry.id)) entry,
    ];
    final selected = [for (final entry in selectedEntries) entry.id];

    final list = switch (entries) {
      null => const SizedBox.shrink(),
      [] => EmptyState(icon: KIcons.star, title: l10n.starredEntriesEmpty),
      final entries => EntryList(
        entries,
        onOpen: (entry) => context.push(Routes.entry(entry.bookId, entry.id)),
        selection: _selection,
        onSelect: (entry) => _selection.toggle(entry.id),
      ),
    };

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selection.clear();
      },
      child: AnimatedBuilder(
        animation: _selection.mode,
        child: list,
        builder: (context, list) => Scaffold(
          appBar: selectionAppBar(
            context,
            shown: _selection.mode.value,
            isOn: selecting,
            // Where a plain app bar puts its back button and title.
            normal: Row(
              children: [
                const SizedBox(width: Space.xs),
                const BackButton(),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    l10n.starredEntries,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            selecting: EntrySelectionBar(
              selected: selectedEntries,
              onClose: _selection.clear,
              onStar: ({required starred}) => _star(selected, starred: starred),
              onCopy: () => _copy(selectedEntries),
              onMove: () => _move(selected),
              onDelete: () => _delete(selected),
            ),
          ),
          body: list,
        ),
      ),
    );
  }
}
