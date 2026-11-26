import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The page that names a Book, shared by Create Book and Edit Book name: the
/// title, the "Book name" field, and a check FAB that saves.
class _BookNamePage extends StatefulWidget {
  const _BookNamePage({
    required this.title,
    required this.saveTooltip,
    required this.onSave,
    this.initialName = '',
  });

  final String title;
  final String saveTooltip;
  final String initialName;

  /// Called once with the trimmed name, which is never empty.
  final Future<void> Function(String name) onSave;

  @override
  State<_BookNamePage> createState() => _BookNamePageState();
}

class _BookNamePageState extends State<_BookNamePage> {
  late final _name = TextEditingController(text: widget.initialName);
  var _showRequired = false;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();

    if (name.isEmpty) {
      setState(() => _showRequired = true);
      return;
    }

    if (_saving) return;
    _saving = true;

    await widget.onSave(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
        child: TextField(
          controller: _name,
          autofocus: true,
          enableIMEPersonalizedLearning: false,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_showRequired) setState(() => _showRequired = false);
          },
          decoration: InputDecoration(
            labelText: l10n.bookName,
            errorText: _showRequired ? l10n.bookNameRequired : null,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: widget.saveTooltip,
        onPressed: _save,
        child: const KIcon(KIcons.check),
      ),
    );
  }
}

/// Creates a Book and opens it.
class CreateBookScreen extends ConsumerWidget {
  const CreateBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return _BookNamePage(
      title: l10n.newBook,
      saveTooltip: l10n.createBook,
      onSave: (name) async {
        final book = await ref.read(bookRepositoryProvider).createBook(name);
        if (!context.mounted) return;

        context.go(Routes.book(book.id));
      },
    );
  }
}

/// Renames a Book and goes back to its Book info.
class RenameBookScreen extends ConsumerWidget {
  const RenameBookScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId)).value;

    // The field starts with the current name, so wait for the Book.
    if (book == null) {
      return Scaffold(
        appBar: AppBar(titleSpacing: 0, title: Text(l10n.renameBookTitle)),
      );
    }

    return _BookNamePage(
      title: l10n.renameBookTitle,
      saveTooltip: l10n.saveBookName,
      initialName: book.name,
      onSave: (name) async {
        if (name != book.name) {
          await ref.read(bookRepositoryProvider).renameBook(bookId, name);
        }
        if (!context.mounted) return;

        context.go(Routes.bookInfo(bookId));
      },
    );
  }
}
