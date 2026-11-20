import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/scrollbar.dart';
import 'package:material_ui/material_ui.dart';

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// The Entries of one Book as cards, newest Entry date first, under a
/// separator for each month.
class BookScreen extends ConsumerWidget {
  const BookScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId)).value;
    final entries = ref.watch(entriesProvider(bookId)).value;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(book?.name ?? ''),
        actionsPadding: const EdgeInsets.only(right: Space.xs),
        actions: [
          if (book != null && (entries?.isNotEmpty ?? false))
            IconButton(
              tooltip: l10n.searchInBook(book.name),
              onPressed: () => context.go(Routes.bookSearch(bookId)),
              icon: const KIcon(KIcons.search),
            ),
          if (book != null) _BookMenu(book),
        ],
      ),
      body: switch (entries) {
        null => const SizedBox.shrink(),
        [] => EmptyState(
          title: l10n.bookEmptyTitle,
          message: l10n.bookEmptyMessage,
        ),
        final entries => _EntryList(entries),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.writeEntry,
        onPressed: () => context.go(Routes.newEntry(bookId)),
        child: const KIcon(KIcons.pen),
      ),
    );
  }
}

class _BookMenu extends ConsumerWidget {
  const _BookMenu(this.book);

  final Book book;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final count = ref.read(entriesProvider(book.id)).value?.length ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBookTitle),
        content: Text(l10n.deleteBookMessage(book.name, count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructiveTextButton(scheme),
            child: Text(l10n.deleteBookConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Leave first, so this screen never shows a Book that is gone. Read the
    // repository before that: this widget's ref goes with the screen.
    final books = ref.read(bookRepositoryProvider);
    context.go(Routes.books);
    await books.deleteBook(book.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const KIcon(KIcons.pen),
          onPressed: () => context.go(Routes.renameBook(book.id)),
          child: Text(l10n.renameBook),
        ),
        MenuItemButton(
          style: destructiveMenuItem(scheme),
          leadingIcon: const KIcon(KIcons.bin),
          onPressed: () => _delete(context, ref),
          child: Text(l10n.deleteBook),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: l10n.bookMenu,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const KIcon(KIcons.moreVertical),
      ),
    );
  }
}

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

/// [entries] come newest first, so each month starts where the month of
/// the Entry date changes.
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

class _EntryList extends StatefulWidget {
  const _EntryList(this.entries);

  final List<Entry> entries;

  @override
  State<_EntryList> createState() => _EntryListState();
}

class _EntryListState extends State<_EntryList> {
  final _controller = ScrollController();

  /// One key per card, so the scrollbar can find the card at the top.
  final _cardKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(_EntryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final entry in widget.entries) entry.id};
    _cardKeys.removeWhere((id, _) => !ids.contains(id));
  }

  @override
  void dispose() {
    _controller.dispose();
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

    return LabeledScrollbar(
      controller: _controller,
      label: _monthAtTop,
      child: ListView.separated(
        controller: _controller,
        // Room on the right for the scrollbar, at the bottom for the FAB.
        padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.xl, 112),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.m),
        itemBuilder: (_, i) => switch (rows[i]) {
          _MonthRow(:final month) => _MonthSeparator(month),
          _EntryRow(:final entry) => _EntryCard(
            entry,
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

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.entry, {super.key});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = _locale(context);
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final text = previewText(entry.text);

    return KCard(
      onTap: () => context.go(Routes.entry(entry.bookId, entry.id)),
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
                  style: meta?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation.weight(600)],
                  ),
                ),
              ),
              Text(DateFormat.Hm(locale).format(entry.dateTime), style: meta),
            ],
          ),
          if (text.isNotEmpty)
            Text(
              text,
              style: theme.extension<EntryTextStyles>()!.entryPreview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          if (entry.imageIds.isNotEmpty) _CardImages(entry.id, entry.imageIds),
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
