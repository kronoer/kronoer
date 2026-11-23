import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/star_mark.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/trash/trash.dart';
import 'package:kronoer/src/trash/trash_actions.dart';
import 'package:kronoer/src/trash/trash_providers.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/selection.dart';
import 'package:kronoer/src/ui/setting_row.dart';
import 'package:material_ui/material_ui.dart';

/// How many Entries go for good with [book]: those that went to the Trash
/// with it, and those of it deleted on their own before, among [trash].
int _entriesGoingWith(TrashedBook book, List<TrashItem> trash) =>
    book.entryCount +
    trash
        .whereType<TrashedEntry>()
        .where((item) => item.entry.bookId == book.id)
        .length;

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// "Sampah": how long it keeps what is deleted, a row for the Books and
/// Entries in it with how many, and what happens to them.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  /// Asks for how long the Trash keeps what is deleted, and sets it. A
  /// shorter time that deletes items at once asks again first.
  Future<void> _pickDays(BuildContext context, WidgetRef ref, int days) async {
    final trash = ref.read(trashRepositoryProvider);
    final now = ref.read(clockProvider)();
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _TrashDaysDialog(days),
    );
    if (picked == null || picked == days || !context.mounted) return;
    final items = await ref.read(trashProvider.future);
    final limit = now.subtract(Duration(days: picked));
    final past = items.where((item) => !item.deletedAt.isAfter(limit)).length;
    if (picked < days && past > 0) {
      if (!context.mounted || !await _confirmShorten(context, picked, past)) {
        return;
      }
    }
    await trash.setTrashDays(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = ref.watch(trashProvider).value?.length;
    final days = ref.watch(trashDaysProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trash)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          SettingRow(
            icon: KIcons.clock,
            title: l10n.trashKeepFor,
            subtitle: days == null ? null : l10n.trashDaysChoice(days),
            onTap: days == null ? null : () => _pickDays(context, ref, days),
          ),
          SettingRow(
            icon: KIcons.book,
            title: l10n.trashBooksAndEntries,
            subtitle: count == null ? null : l10n.trashItemCount(count),
            onTap: () => context.go(Routes.trashItems),
          ),
          Padding(
            // Under the rows' titles: their padding, icon, and gap.
            padding: const EdgeInsetsDirectional.fromSTEB(
              64,
              Space.s,
              Space.xl,
              0,
            ),
            child: Text(
              l10n.trashHubHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Simpan selama": 7, 30, or 90 days, [days] chosen. Picking one closes it
/// with that; Batal closes it with none.
class _TrashDaysDialog extends StatelessWidget {
  const _TrashDaysDialog(this.days);

  final int days;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.trashKeepFor),
      contentPadding: const EdgeInsets.only(top: Space.l),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            child: Text(
              l10n.trashKeepForHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: Space.s),
          RadioGroup<int>(
            groupValue: days,
            onChanged: (picked) => Navigator.pop(context, picked),
            child: Column(
              children: [
                for (final choice in trashDayChoices)
                  RadioListTile<int>(
                    value: choice,
                    // The circle lines up with the title, 24 in; the label
                    // 16 after the circle.
                    contentPadding: const EdgeInsets.symmetric(horizontal: 13),
                    horizontalTitleGap: Space.s,
                    title: Text(l10n.trashDaysChoice(choice)),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

/// Asks before [days] deletes the [count] items deleted longer ago for good:
/// true once confirmed.
Future<bool> _confirmShorten(BuildContext context, int days, int count) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.shortenTrashTitle(days)),
      content: Text(l10n.shortenTrashMessage(count, days)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructiveTextButton(scheme),
          child: Text(l10n.shortenTrashConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// "Book dan Entry": everything in the Trash as cards, the one deleted most
/// recently first, each with the days it has left. A tap opens one; a long
/// press starts selection mode, to restore or delete several for good. The
/// menu empties the Trash.
class TrashListScreen extends ConsumerStatefulWidget {
  const TrashListScreen({super.key});

  @override
  ConsumerState<TrashListScreen> createState() => _TrashListScreenState();
}

class _TrashListScreenState extends ConsumerState<TrashListScreen>
    with SingleTickerProviderStateMixin {
  late final _selection = Selection(
    vsync: this,
    onChanged: () => setState(() {}),
  );

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _restore(List<TrashItem> items) async {
    final restored = await restoreFromTrash(context, ref, items);
    if (restored && mounted) _selection.clear();
  }

  Future<void> _deleteForever(List<TrashItem> items) async {
    final trash = ref.read(trashRepositoryProvider);
    final confirmed = await confirmDeleteForever(
      context,
      items,
      bookEntryCount: switch (items) {
        [final TrashedBook book] => _entriesGoingWith(
          book,
          ref.read(trashProvider).value ?? const [],
        ),
        _ => 0,
      },
    );
    if (!confirmed) return;
    await trash.deleteForever(
      bookIds: [
        for (final item in items)
          if (item is TrashedBook) item.id,
      ],
      entryIds: [
        for (final item in items)
          if (item is TrashedEntry) item.id,
      ],
    );
    if (mounted) _selection.clear();
  }

  Future<void> _empty(int count) async {
    final trash = ref.read(trashRepositoryProvider);
    if (!await confirmEmptyTrash(context, count)) return;
    await trash.emptyTrash();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(trashProvider).value;
    final now = ref.watch(clockProvider)();
    final selecting = _selection.isOn;

    // What is no longer in the Trash, restored or deleted, here or
    // elsewhere, is no longer selected.
    ref.listen(trashProvider, (_, next) {
      final items = next.value;
      if (items == null) return;
      _selection.retain({for (final item in items) item.id});
    });

    final selected = [
      for (final item in items ?? const <TrashItem>[])
        if (_selection.contains(item.id)) item,
    ];

    final list = switch (items) {
      null => const SizedBox.shrink(),
      [] => EmptyState(
        icon: KIcons.bin,
        title: l10n.trashEmpty,
        message: l10n.trashHint(
          ref.watch(trashDaysProvider).value ?? defaultTrashDays,
        ),
      ),
      final items => ListView.separated(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xl),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.m),
        itemBuilder: (context, i) {
          final item = items[i];
          return _TrashCard(
            item,
            key: ValueKey(item.id),
            daysLeft: item.daysLeft(now),
            selecting: selecting,
            selected: _selection.contains(item.id),
            badge: _selection.badges,
            onTap: selecting
                ? () => _selection.toggle(item.id)
                : () => context.go(Routes.trashItem(item.id)),
            onLongPress: () => _selection.toggle(item.id),
          );
        },
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
            // Where a plain app bar puts its back button, title, and menu.
            normal: Row(
              children: [
                const SizedBox(width: Space.xs),
                const BackButton(),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    l10n.trashBooksAndEntries,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                MenuAnchor(
                  menuChildren: [
                    MenuItemButton(
                      style: destructiveMenuItem(scheme),
                      leadingIcon: const KIcon(KIcons.bin),
                      onPressed: items == null || items.isEmpty
                          ? null
                          : () => _empty(items.length),
                      child: Text(l10n.emptyTrash),
                    ),
                  ],
                  builder: (context, controller, _) => IconButton(
                    tooltip: l10n.trashMenu,
                    color: scheme.onSurfaceVariant,
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    icon: const KIcon(KIcons.moreVertical),
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
            ),
            selecting: _TrashSelectionBar(
              count: selected.length,
              onClose: _selection.clear,
              onRestore: () => _restore(selected),
              onDelete: () => _deleteForever(selected),
            ),
          ),
          body: list,
        ),
      ),
    );
  }
}

/// The selection mode top bar of the Trash: back, how many are selected,
/// Pulihkan, and Hapus permanen. While it fades out after the last item is
/// deselected, it keeps the count it showed.
class _TrashSelectionBar extends StatefulWidget {
  const _TrashSelectionBar({
    required this.count,
    required this.onClose,
    required this.onRestore,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onClose;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  State<_TrashSelectionBar> createState() => _TrashSelectionBarState();
}

class _TrashSelectionBarState extends State<_TrashSelectionBar> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    if (widget.count > 0) _count = widget.count;

    return Row(
      children: [
        const SizedBox(width: Space.xs),
        BackButton(onPressed: widget.onClose),
        const SizedBox(width: Space.s),
        Expanded(
          child: Semantics(
            label: l10n.itemsSelected(_count),
            excludeSemantics: true,
            child: Text('$_count'),
          ),
        ),
        IconButton(
          tooltip: l10n.restore,
          color: variant,
          onPressed: widget.onRestore,
          icon: const KIcon(KIcons.arrowUTurnLeft),
        ),
        IconButton(
          tooltip: l10n.deleteForever,
          color: variant,
          onPressed: widget.onDelete,
          icon: const KIcon(KIcons.bin),
        ),
        const SizedBox(width: Space.xs),
      ],
    );
  }
}

/// One item of the Trash as a card. An Entry shows its day, its Book, and
/// the start of its text; a Book its Cover, its name, and its Entries. Both
/// show the days left. While [selecting], a [selected] card is tinted and
/// carries a check over its top-left corner while [badge] is on.
class _TrashCard extends StatelessWidget {
  const _TrashCard(
    this.item, {
    required this.daysLeft,
    required this.selecting,
    required this.selected,
    required this.badge,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final TrashItem item;
  final int daysLeft;
  final bool selecting;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final color = CardTheme.of(context).color ?? theme.colorScheme.surface;
    final left = Text(l10n.trashDaysLeft(daysLeft), style: meta);

    final content = switch (item) {
      TrashedEntry(:final entry, :final bookName) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s,
        children: [
          Row(
            spacing: Space.xs,
            children: [
              Expanded(
                child: Text(
                  '${DateFormat('EEEE, d MMM', _locale(context)).format(entry.dateTime)} · $bookName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meta?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (entry.starred) const StarMark(),
            ],
          ),
          if (previewRuns(entry.text) case final preview
              when preview.isNotEmpty)
            Text.rich(
              TextStyleLook.of(
                context,
              ).span(preview, fontSize: theme.textTheme.bodyMedium?.fontSize),
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else if (entry.imageIds.isNotEmpty)
            Text(
              l10n.bookCardImages(entry.imageIds.length),
              style: theme.textTheme.bodyMedium,
            ),
          left,
        ],
      ),
      TrashedBook(:final book, :final entryCount) => Row(
        spacing: Space.l,
        children: [
          CoverThumbnail(book, width: 30, radius: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  book.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                Text(l10n.trashBookCount(entryCount), style: meta),
                left,
              ],
            ),
          ),
        ],
      ),
    };

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
      child: content,
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

/// One item of the Trash, read-only, with only Pulihkan and Hapus permanen.
/// An Entry shows as its read view does, under a banner with the days it has
/// left; a Book shows its Cover, name, and counts, but not its Entries.
/// It closes once the item is restored or deleted.
class TrashItemScreen extends ConsumerWidget {
  const TrashItemScreen({required this.id, super.key});

  final String id;

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    TrashItem item,
  ) async {
    final restored = await restoreFromTrash(context, ref, [item]);
    if (restored && context.mounted) context.pop();
  }

  Future<void> _deleteForever(
    BuildContext context,
    WidgetRef ref,
    TrashItem item,
  ) async {
    final trash = ref.read(trashRepositoryProvider);
    final confirmed = await confirmDeleteForever(
      context,
      [item],
      bookEntryCount: switch (item) {
        TrashedBook() => _entriesGoingWith(
          item,
          ref.read(trashProvider).value ?? const [],
        ),
        TrashedEntry() => 0,
      },
    );
    if (!confirmed) return;
    await switch (item) {
      TrashedBook() => trash.deleteForever(bookIds: [item.id]),
      TrashedEntry() => trash.deleteForever(entryIds: [item.id]),
    };
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final item = ref
        .watch(trashProvider)
        .value
        ?.where((item) => item.id == id)
        .firstOrNull;

    final title = switch (item) {
      TrashedBook() => Text(l10n.trashBookTitle),
      TrashedEntry(:final bookName) => Text(
        bookName,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      null => null,
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: item is TrashedEntry ? 0 : null,
        title: title,
      ),
      // Null while loading, or once the item is gone.
      body: switch (item) {
        null => const SizedBox.shrink(),
        TrashedEntry(:final entry) => EntryBody(
          entry,
          top: _TrashBanner(l10n.trashEntryBanner(item.daysLeft(now))),
        ),
        TrashedBook(:final book) => _TrashedBookView(
          item,
          banner: _TrashBanner(l10n.trashBookBanner(item.daysLeft(now))),
          key: ValueKey(book.id),
        ),
      },
      bottomNavigationBar: item == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.s,
                  Space.l,
                  Space.m,
                ),
                child: Row(
                  children: [
                    TextButton(
                      style: destructiveTextButton(theme.colorScheme),
                      onPressed: () => _deleteForever(context, ref, item),
                      child: Text(l10n.deleteForever),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _restore(context, ref, item),
                      icon: const KIcon(KIcons.arrowUTurnLeft, size: 20),
                      label: Text(l10n.restore),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A Book in the Trash: its Cover, name, Entries and photos, and the banner.
class _TrashedBookView extends ConsumerWidget {
  const _TrashedBookView(this.item, {required this.banner, super.key});

  final TrashedBook item;
  final Widget banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = item.book;
    final insight = ref.watch(bookInsightProvider(book.id)).value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.xl,
        Space.xl,
        Space.xl,
        Space.xl,
      ),
      children: [
        Center(child: CoverThumbnail(book, width: 120, radius: Radii.m)),
        const SizedBox(height: Space.l),
        Text(
          book.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: Space.xs),
        Text(
          l10n.trashBookCounts(
            insight?.entryCount ?? item.entryCount,
            insight?.imageCount ?? 0,
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xl),
        banner,
      ],
    );
  }
}

/// "Di Sampah · tersisa N hari", in a box over what is in the Trash.
class _TrashBanner extends StatelessWidget {
  const _TrashBanner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variant = theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: Space.m,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      child: Row(
        spacing: Space.m,
        children: [
          KIcon(KIcons.bin, size: 20, color: variant),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: variant),
            ),
          ),
        ],
      ),
    );
  }
}
