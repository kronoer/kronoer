import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

class _CreateBookScreenState extends ConsumerState<CreateBookScreen> {
  final _name = TextEditingController();
  var _showRequired = false;
  var _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();

    if (name.isEmpty) {
      setState(() => _showRequired = true);
      return;
    }

    if (_creating) return;
    _creating = true;

    final book = await ref.read(bookRepositoryProvider).createBook(name);
    if (!mounted) return;

    context.go(Routes.book(book.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: Text(l10n.newBook)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
        child: TextField(
          controller: _name,
          autofocus: true,
          enableIMEPersonalizedLearning: false,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _create(),
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
        tooltip: l10n.createBook,
        onPressed: _create,
        child: const KIcon(KIcons.check),
      ),
    );
  }
}

class CreateBookScreen extends ConsumerStatefulWidget {
  const CreateBookScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _CreateBookScreenState();
}
