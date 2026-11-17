import 'package:material_ui/material_ui.dart';

/// Writes a new Entry, or edits one when [entryId] is set. Placeholder
/// until the editor story.
class EntryEditorScreen extends StatelessWidget {
  const EntryEditorScreen({required this.bookId, this.entryId, super.key});

  final String bookId;

  /// Null for a new Entry.
  final String? entryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(entryId == null ? 'New entry' : 'Edit entry')),
      body: const Center(child: Text('Editor placeholder')),
    );
  }
}
