import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The most characters a Book's Description holds.
const bookDescriptionMaxLength = 300;

/// The field shows how many characters are used from this many on.
const _counterFrom = 250;

/// Sets a Book's Description and goes back to its Book info. The Description
/// is plain text with line breaks; emptying it removes it.
class BookDescriptionScreen extends ConsumerWidget {
  const BookDescriptionScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId)).value;

    // The field starts with the current Description, so wait for the Book.
    if (book == null) {
      return Scaffold(
        appBar: AppBar(titleSpacing: 0, title: Text(l10n.editBookDescription)),
      );
    }

    return _DescriptionPage(
      initial: book.description,
      onSave: (description) async {
        if (description != book.description) {
          await ref
              .read(bookRepositoryProvider)
              .setBookDescription(bookId, description);
        }
        if (!context.mounted) return;

        context.go(Routes.bookInfo(bookId));
      },
    );
  }
}

class _DescriptionPage extends StatefulWidget {
  const _DescriptionPage({required this.initial, required this.onSave});

  final String initial;

  /// Called once with the Description trimmed, which may be empty.
  final Future<void> Function(String description) onSave;

  @override
  State<_DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<_DescriptionPage> {
  late final _description = TextEditingController(text: widget.initial);
  var _saving = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;

    await widget.onSave(_description.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: Text(l10n.editBookDescription)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
        child: TextField(
          controller: _description,
          autofocus: true,
          enableIMEPersonalizedLearning: false,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          minLines: 8,
          maxLines: 8,
          maxLength: bookDescriptionMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) =>
                  currentLength < _counterFrom
                  ? null
                  : Text('$currentLength/$maxLength'),
          decoration: InputDecoration(
            labelText: l10n.bookDescription,
            alignLabelWithHint: true,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.saveBookDescription,
        onPressed: _save,
        child: const KIcon(KIcons.check),
      ),
    );
  }
}
