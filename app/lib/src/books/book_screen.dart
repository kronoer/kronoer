import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The Entries of one Book. Placeholder until the Book story.
class BookScreen extends ConsumerWidget {
  const BookScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider(bookId)).value;
    final entries = ref.watch(entriesProvider(bookId)).value ?? const <Entry>[];
    final l10n = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(book?.name ?? '')),
      body: ListView(
        children: [
          for (final entry in entries)
            ListTile(
              title: Text(
                entry.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${l10n.formatMediumDate(entry.dateTime)} · '
                '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(entry.dateTime))}',
              ),
              onTap: () => context.go(Routes.entry(bookId, entry.id)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go(Routes.newEntry(bookId)),
        child: const KIcon(KIcons.pen),
      ),
    );
  }
}
