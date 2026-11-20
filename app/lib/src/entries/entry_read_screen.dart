import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_deletion.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/entries/image_placeholder.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The paragraphs of an Entry's text: lines split by one or more blank lines.
List<String> paragraphs(String text) => [
  for (final paragraph in text.trim().split(RegExp(r'\n\s*\n')))
    if (paragraph.trim().isNotEmpty) paragraph.trim(),
];

/// One Entry, whole and read only: date and time, text, and images. Only the
/// pen opens the editor.
class EntryReadScreen extends ConsumerWidget {
  const EntryReadScreen({
    required this.bookId,
    required this.entryId,
    super.key,
  });

  final String bookId;
  final String entryId;

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
              onPressed: () => context.go(Routes.editEntry(bookId, entryId)),
              icon: const KIcon(KIcons.pen, size: 22),
            ),
            EntryMenu(onDelete: () => deleteEntryWithUndo(context, ref, entry)),
          ],
        ],
      ),
      // Null while loading, or once the Entry is gone.
      body: entry == null ? const SizedBox.shrink() : _EntryBody(entry),
    );
  }
}

class _EntryBody extends StatelessWidget {
  const _EntryBody(this.entry);

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.m, Space.xl, 32),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.l,
            children: [
              for (final paragraph in paragraphs(entry.text))
                Text(
                  paragraph,
                  style: theme.extension<EntryTextStyles>()!.entryBody,
                ),
            ],
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
                    ImagePlaceholder(imageId),
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: () => context.go(
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
    );
  }
}
