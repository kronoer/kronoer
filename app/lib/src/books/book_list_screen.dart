import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/activity_time.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_fab.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/search/search_bar_hero.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/wordmark.dart';
import 'package:material_ui/material_ui.dart';

class _BookCard extends StatelessWidget {
  const _BookCard({required this.summary, required this.now});

  final BookSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = summary.book;

    final description = _description(context, summary);

    return KCard(
      onTap: () => context.go(Routes.book(book.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: Space.m,
            children: [
              Expanded(
                child: Text(book.name, style: theme.textTheme.titleMedium),
              ),
              Text(
                formatActivityTime(
                  book.lastActivityAt,
                  now: now,
                  locale: Localizations.localeOf(context).toString(),
                  yesterday: l10n.yesterday,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (description != null)
            Text.rich(
              TextSpan(children: description),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  /// The line under the Book's name: the latest Entry's text, how many Images it has, or that
  /// the Book has no Entries yet. `null` when there is nothing to say.
  static List<InlineSpan>? _description(
    BuildContext context,
    BookSummary summary,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final entryStyle = theme.extension<EntryTextStyles>()!.entryPreviewSmall;
    final label = theme.textTheme.bodyMedium!;
    // Same line height as the Entry text, so every card is as tall.
    final labelStyle = label.copyWith(
      color: color,
      height: entryStyle.fontSize! * entryStyle.height! / label.fontSize!,
    );

    InlineSpan icon(KIcons icon) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: KIcon(icon, filled: true, size: 16, color: color),
      ),
    );

    final runs = switch (summary.lastEntryText) {
      final text? => previewRuns(text),
      null => null,
    };
    final images = summary.lastEntryImageCount;
    InlineSpan preview(List<StyledRun> runs) => TextSpan(
      style: entryStyle,
      children: [
        TextStyleLook.of(context).span(runs, fontSize: entryStyle.fontSize),
      ],
    );

    return switch (runs) {
      null => [
        icon(KIcons.pen),
        TextSpan(text: l10n.bookCardNoEntries, style: labelStyle),
      ],
      _ when images > 0 => [
        icon(KIcons.image),
        TextSpan(text: l10n.bookCardImages(images), style: labelStyle),
        if (runs.isNotEmpty) ...[
          TextSpan(text: ' · ', style: labelStyle),
          preview(runs),
        ],
      ],
      [] => null,
      _ => [preview(runs)],
    };
  }
}

/// Looks like a search field; tapping it opens the search across all Books.
class _SearchField extends StatelessWidget implements PreferredSizeWidget {
  const _SearchField();

  @override
  Size get preferredSize => const Size.fromHeight(52 + Space.s);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
      // Moves up into the search screen's app bar when tapped.
      child: SearchBarHero(
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go(Routes.search()),
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: l10n.searchAllBooks,
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    spacing: Space.m,
                    children: [
                      KIcon(KIcons.search, size: 22, color: color),
                      Text(
                        l10n.searchAllBooks,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
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

class BookListScreen extends ConsumerWidget {
  const BookListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaries = ref.watch(bookSummariesProvider).value;
    final now = ref.watch(clockProvider)();
    final hasEntries =
        summaries?.any((summary) => summary.lastEntryText != null) ?? false;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Wordmark(),
        // Fixed under the app bar: it does not scroll with the Books.
        bottom: hasEntries ? const _SearchField() : null,
      ),
      body: switch (summaries) {
        null => const SizedBox.shrink(),
        [] => EmptyState(
          title: l10n.bookListEmptyTitle,
          message: l10n.bookListEmptyMessage,
        ),
        final books => ScrollToTopOnReselect(
          child: ListView.separated(
            primary: true,
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 112),
            itemBuilder: (_, i) => _BookCard(summary: books[i], now: now),
            separatorBuilder: (_, _) => const SizedBox(height: Space.m),
            itemCount: books.length,
          ),
        ),
      },
      floatingActionButton: BookFab(
        child: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () => context.go(Routes.newBook),
          icon: const KIcon(KIcons.plus),
          label: Text(l10n.newBook),
        ),
      ),
    );
  }
}
