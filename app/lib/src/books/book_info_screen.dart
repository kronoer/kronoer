import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// What a Book is: its name and Description, centered, with a menu to change
/// them or delete the Book. The Book's Cover will sit above the name.
class BookInfoScreen extends ConsumerWidget {
  const BookInfoScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = ref.watch(bookProvider(bookId)).value;

    return Scaffold(
      appBar: AppBar(
        actionsPadding: const EdgeInsets.only(right: Space.xs),
        actions: [if (book != null) _BookInfoMenu(book)],
      ),
      body: book == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.l,
                Space.xl,
                Space.xl,
              ),
              children: [
                Text(
                  book.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
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
                    padding: const EdgeInsets.only(top: Space.m),
                    child: FoldedDescription(book.description),
                  ),
              ],
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

class _BookInfoMenu extends ConsumerWidget {
  const _BookInfoMenu(this.book);

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

    // Leave first, so no screen shows a Book that is gone. Read the
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
          onPressed: () => context.go(Routes.renameBook(book.id)),
          child: Text(l10n.renameBook),
        ),
        MenuItemButton(
          onPressed: () => context.go(Routes.editBookDescription(book.id)),
          child: Text(l10n.editBookDescription),
        ),
        MenuItemButton(
          style: destructiveMenuItem(scheme),
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
