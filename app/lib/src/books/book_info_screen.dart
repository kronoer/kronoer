import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_insight_card.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/books/cover_editing.dart';
import 'package:kronoer/src/books/cover_processing.dart';
import 'package:kronoer/src/books/cover_viewer_screen.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/trash/trash.dart';
import 'package:kronoer/src/trash/trash_actions.dart';
import 'package:kronoer/src/trash/trash_providers.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/setting_row.dart';
import 'package:material_ui/material_ui.dart';

/// What a Book is: its Cover, name, and Description, centered, with a menu
/// to change them. Under them, the Book insight, once the Book has Entries.
/// Below that, rows like the Settings tab's: Entry berbintang, whether the
/// Timeline shows the Book, and Hapus Book.
///
/// The Cover rises into the top bar, between back and the menu. The bar is
/// clear, letting taps through to the Cover, until the content scrolls
/// under it.
class BookInfoScreen extends ConsumerStatefulWidget {
  const BookInfoScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<BookInfoScreen> createState() => _BookInfoScreenState();
}

class _BookInfoScreenState extends ConsumerState<BookInfoScreen> {
  var _scrolled = false;

  bool _onScroll(ScrollNotification notification) {
    final scrolled = notification.metrics.extentBefore > 0;
    if (notification.depth == 0 && scrolled != _scrolled) {
      setState(() => _scrolled = scrolled);
    }
    return false;
  }

  Future<void> _setInTimeline(bool inTimeline) => ref
      .read(bookRepositoryProvider)
      .setBookInTimeline(widget.bookId, inTimeline: inTimeline);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bookId = widget.bookId;
    final book = ref.watch(bookProvider(bookId)).value;
    // Named by the delete dialog.
    final trashDays = ref.watch(trashDaysProvider).value ?? defaultTrashDays;
    final insight = ref.watch(bookInsightProvider(bookId)).value;
    final starredCount =
        ref.watch(starredEntriesProvider(bookId)).value?.length ?? 0;
    // Under the status bar, not the top bar: the Cover sits in the bar.
    final top = MediaQuery.paddingOf(context).top + Space.xl;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        forceMaterialTransparency: !_scrolled,
        actionsPadding: const EdgeInsets.only(right: Space.xs),
        actions: [if (book != null) _BookInfoMenu(book)],
      ),
      body: book == null
          ? const SizedBox.shrink()
          : NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              // Each part is its own child, so a screen reader reads them
              // apart. Only the rows below reach the edges.
              child: ListView(
                padding: EdgeInsets.only(top: top, bottom: Space.xl),
                children: [
                  Center(child: _InfoCover(book)),
                  const SizedBox(height: Space.xl),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                    child: Text(
                      book.name,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (book.description.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.l),
                      child: Center(
                        child: FilledButton(
                          onPressed: () =>
                              context.go(Routes.editBookDescription(bookId)),
                          child: Text(l10n.addBookDescription),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.xl,
                        Space.m,
                        Space.xl,
                        0,
                      ),
                      child: FoldedDescription(book.description),
                    ),
                  const SizedBox(height: Space.xl),
                  if (insight != null && insight.entryCount > 0) ...[
                    BookInsightCard(insight),
                    const SizedBox(height: Space.m),
                  ],
                  SettingRow(
                    icon: KIcons.star,
                    title: l10n.starredEntries,
                    trailing: starredCount > 0
                        ? Text(
                            '$starredCount',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                    onTap: () => context.go(Routes.starredEntries(bookId)),
                  ),
                  SettingRow(
                    icon: KIcons.timelineBook,
                    title: l10n.showInTimeline,
                    subtitle: book.inTimeline
                        ? l10n.showInTimelineOn
                        : l10n.showInTimelineOff,
                    trailing: Switch(
                      value: book.inTimeline,
                      onChanged: (value) => _setInTimeline(value),
                    ),
                    onTap: () => _setInTimeline(!book.inTimeline),
                  ),
                  SettingRow(
                    icon: KIcons.bin,
                    title: l10n.deleteBook,
                    destructive: true,
                    onTap: () => _deleteBook(context, ref, book, trashDays),
                  ),
                ],
              ),
            ),
    );
  }
}

/// The Cover large, which opens it full screen; without one, a tile of the
/// same size that offers to add one.
class _InfoCover extends ConsumerWidget {
  const _InfoCover(this.book);

  final Book book;

  static const _width = 192.0;
  static const _radius = BorderRadius.all(Radius.circular(Radii.l));

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final source = await showCoverSheet(context, canRemove: false);
    if (source == null || !context.mounted) return;
    await pickCover(context, ref, bookId: book.id, source: source);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final coverId = book.coverId;
    const size = Size(_width, _width / coverAspectRatio);

    if (coverId == null) {
      return Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: _radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _add(context, ref),
          child: SizedBox.fromSize(
            size: size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10,
              children: [
                KIcon(KIcons.image, size: 32, color: scheme.onSurfaceVariant),
                Text(
                  l10n.addCover,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: l10n.openCover,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: _radius,
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: _radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(Routes.bookCover(book.id)),
            child: SizedBox.fromSize(
              size: size,
              // The label above says it all, even when the image is broken.
              child: ExcludeSemantics(
                child: Hero(
                  tag: coverHeroTag(book.id),
                  child: BookCoverImage(
                    bookId: book.id,
                    coverId: coverId,
                    thumbnail: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Book's Description, centered, folded to [maxLines] lines. When it is
/// longer, the cut text ends with "…" and a link that unfolds it.
class FoldedDescription extends StatefulWidget {
  const FoldedDescription(this.text, {this.maxLines = 3, super.key});

  final String text;
  final int maxLines;

  @override
  State<FoldedDescription> createState() => _FoldedDescriptionState();
}

class _FoldedDescriptionState extends State<FoldedDescription> {
  late final _unfold = TapGestureRecognizer()
    ..onTap = () => setState(() => _unfolded = true);
  var _unfolded = false;

  @override
  void didUpdateWidget(FoldedDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) _unfolded = false;
  }

  @override
  void dispose() {
    _unfold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (_unfolded) {
      return Text(widget.text, textAlign: TextAlign.center, style: style);
    }

    final link = TextSpan(
      text: l10n.showMoreDescription,
      recognizer: _unfold,
      style: TextStyle(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w500,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final cut = _cut(
          context,
          style: style,
          link: link,
          maxWidth: constraints.maxWidth,
        );
        return Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: cut ?? widget.text),
              if (cut != null) link,
            ],
          ),
          textAlign: TextAlign.center,
        );
      },
    );
  }

  /// The longest start of the text that fits in [FoldedDescription.maxLines]
  /// lines with "… " and the link after it, ending with "… ". `null` when the
  /// whole text fits without the link.
  String? _cut(
    BuildContext context, {
    required TextStyle style,
    required TextSpan link,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      textAlign: TextAlign.center,
      maxLines: widget.maxLines,
    );
    bool fits(InlineSpan span) {
      painter
        ..text = TextSpan(style: style, children: [span])
        ..layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines;
    }

    try {
      if (fits(TextSpan(text: widget.text))) return null;

      final characters = widget.text.characters.toList();
      String withEllipsis(int length) =>
          '${characters.take(length).join().trimRight()}… ';
      bool fitsWithLink(int length) => fits(
        TextSpan(
          children: [
            TextSpan(text: withEllipsis(length)),
            link,
          ],
        ),
      );

      // The longest length that fits: binary search, since a longer start
      // never fits where a shorter one does not.
      var low = 0;
      var high = characters.length;
      while (low < high) {
        final middle = (low + high + 1) ~/ 2;
        if (fitsWithLink(middle)) {
          low = middle;
        } else {
          high = middle - 1;
        }
      }
      return withEllipsis(low);
    } finally {
      painter.dispose();
    }
  }
}

/// Asks, saying the Trash keeps it [days] days, then moves [book] with its
/// Entries to the Trash, leaving for the Book list.
Future<void> _deleteBook(
  BuildContext context,
  WidgetRef ref,
  Book book,
  int days,
) async {
  final count = ref.read(entriesProvider(book.id)).value?.length ?? 0;
  if (!await confirmTrashBooks(
        context,
        [book],
        entryCount: count,
        days: days,
      ) ||
      !context.mounted) {
    return;
  }
  // Leave once it is in the Trash, so no screen shows a Book that is gone.
  await trashBooksWithUndo(context, ref, [book]);
  if (context.mounted) context.go(Routes.books);
}

class _BookInfoMenu extends StatelessWidget {
  const _BookInfoMenu(this.book);

  final Book book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => context.go(Routes.renameBook(book.id)),
          child: Text(l10n.renameBook),
        ),
        MenuItemButton(
          onPressed: () => context.go(Routes.editBookDescription(book.id)),
          child: Text(l10n.editBookDescription),
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
