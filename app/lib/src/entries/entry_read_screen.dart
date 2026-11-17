import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/entries/image_placeholder.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// One Entry, read only. Placeholder until the read view story.
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
    final entry = ref.watch(entryProvider(entryId)).value;
    final theme = Theme.of(context);
    final l10n = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => context.go(Routes.editEntry(bookId, entryId)),
            icon: const KIcon(KIcons.pen),
          ),
        ],
      ),
      // Null while loading, or right after the Entry is deleted.
      body: entry == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(Space.l),
              children: [
                Text(
                  '${l10n.formatFullDate(entry.dateTime)} · '
                  '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(entry.dateTime))}',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: Space.l),
                Text(
                  entry.text,
                  style: theme.extension<EntryTextStyles>()!.entryBody,
                ),
                if (entry.imageIds.isNotEmpty) ...[
                  const SizedBox(height: Space.l),
                  Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final imageId in entry.imageIds)
                        GestureDetector(
                          onTap: () => context.go(
                            Routes.image(bookId, entryId, imageId),
                          ),
                          child: SizedBox.square(
                            dimension: 96,
                            child: ImagePlaceholder(imageId),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
