import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/activity_time.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/router.dart';
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

    final preview = switch (summary.lastEntryText) {
      final text? => previewText(text),
      null => null,
    };

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
          if (preview != null && preview.isNotEmpty)
            Text(
              preview,
              style: theme.extension<EntryTextStyles>()!.entryPreviewSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Wordmark(),
        actionsPadding: const EdgeInsets.only(right: Space.s),
        actions: [
          IconButton(
            tooltip: l10n.settings,
            onPressed: () => context.go(Routes.settings),
            icon: const KIcon(KIcons.settings),
          ),
        ],
      ),
      body: switch (summaries) {
        null => const SizedBox.shrink(),
        [] => EmptyState(
          title: l10n.bookListEmptyTitle,
          message: l10n.bookListEmptyMessage,
        ),
        final books => ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 112),
          itemBuilder: (_, i) => _BookCard(summary: books[i], now: now),
          separatorBuilder: (_, _) => const SizedBox(height: Space.m),
          itemCount: books.length,
        ),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(Routes.newBook),
        icon: const KIcon(KIcons.plus),
        label: Text(l10n.newBook),
      ),
    );
  }
}
