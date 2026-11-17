import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

class BookListScreen extends ConsumerWidget {
  const BookListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value ?? const <Book>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Books'),
        actions: [
          IconButton(
            onPressed: () => context.go(Routes.settings),
            icon: const KIcon(KIcons.settings),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final book in books)
            ListTile(
              title: Text(book.name),
              onTap: () => context.go(Routes.book(book.id)),
            ),
        ],
      ),
    );
  }
}
