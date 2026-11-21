import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_deletion.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/search/highlight.dart';
import 'package:kronoer/src/search/search.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// One Entry, whole and read only: date and time, text with its Text styles,
/// and images. Only the pen opens the editor.
///
/// With a [query], as when opened from a search, every word it matches is
/// marked and the view starts at the first one.
class EntryReadScreen extends ConsumerWidget {
  const EntryReadScreen({
    required this.bookId,
    required this.entryId,
    this.query = '',
    super.key,
  });

  final String bookId;
  final String entryId;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = ref.watch(bookProvider(bookId)).value;
    final entry = ref.watch(entryProvider(entryId)).value;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          book?.name ?? '',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.only(right: Space.xs),
        actions: [
          if (entry != null) ...[
            IconButton(
              tooltip: l10n.editEntry,
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => context.push(Routes.editEntry(bookId, entryId)),
              icon: const KIcon(KIcons.pen, size: 22),
            ),
            EntryMenu(onDelete: () => deleteEntryWithUndo(context, ref, entry)),
          ],
        ],
      ),
      // Null while loading, or once the Entry is gone.
      body: entry == null
          ? const SizedBox.shrink()
          : _EntryBody(entry, query: query),
    );
  }
}

/// [object] if it lays out text, or else the first of its descendants that
/// does.
RenderParagraph? _paragraphIn(RenderObject? object) {
  if (object == null || object is RenderParagraph) {
    return object as RenderParagraph?;
  }
  RenderParagraph? found;
  object.visitChildren((child) => found ??= _paragraphIn(child));
  return found;
}

class _EntryBody extends StatefulWidget {
  const _EntryBody(this.entry, {required this.query});

  final Entry entry;
  final String query;

  @override
  State<_EntryBody> createState() => _EntryBodyState();
}

class _EntryBodyState extends State<_EntryBody> {
  final _scroll = ScrollController();

  /// The text with the first match, to start the view there.
  final _firstMatch = GlobalKey();
  late List<TextBlock> _blocks;
  late List<TextRange> _matches;
  var _revealed = false;

  @override
  void initState() {
    super.initState();
    _blocks = parseTextStyles(widget.entry.text);
    _matches = _find();
  }

  @override
  void didUpdateWidget(_EntryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.text != oldWidget.entry.text) {
      _blocks = parseTextStyles(widget.entry.text);
    }
    if (widget.entry.text != oldWidget.entry.text ||
        widget.query != oldWidget.query) {
      _matches = _find();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<TextRange> _find() => isSearchable(widget.query)
      ? matchesIn(widget.entry.text, widget.query)
      : const [];

  /// Scrolls once, so the first match, at [first] in its text as shown, sits
  /// a third of the way down.
  void _revealFirstMatch(TextRange first) {
    if (_revealed) return;
    _revealed = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Text in a SelectionArea sits under a MouseRegion: look below it.
      final paragraph = _paragraphIn(
        _firstMatch.currentContext?.findRenderObject(),
      );
      if (paragraph == null || !_scroll.hasClients) return;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: first.start, extentOffset: first.end),
      );
      if (boxes.isEmpty) return;
      final target = RenderAbstractViewport.of(paragraph)
          .getOffsetToReveal(paragraph, 1 / 3, rect: boxes.first.toRect())
          .offset;
      final position = _scroll.position;
      _scroll.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final entry = widget.entry;

    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.m, Space.xl, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              DateFormat.yMMMMEEEEd(locale).format(entry.dateTime),
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            DateFormat.Hm(locale).format(entry.dateTime),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          SelectionArea(
            child: EntryText(
              _blocks,
              matches: _matches,
              firstMatchKey: _firstMatch,
              onFirstMatch: _revealFirstMatch,
            ),
          ),
          for (final (i, imageId) in entry.imageIds.indexed) ...[
            const SizedBox(height: 20),
            Semantics(
              button: true,
              label: l10n.openImage(i + 1, entry.imageIds.length),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.m),
                child: SizedBox(
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      EntryImage(
                        entryId: entry.id,
                        imageId: imageId,
                        thumbnail: false,
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () => context.push(
                            Routes.image(entry.bookId, entry.id, imageId),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
