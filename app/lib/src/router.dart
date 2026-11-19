import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/books/book_name_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/image_viewer_screen.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/ui/gallery.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:kronoer/src/welcome/welcome_screen.dart';

const _showGallery = kDebugMode && bool.fromEnvironment('KRONOER_GALLERY');

abstract final class Routes {
  static const books = '/';
  static const newBook = '/new-book';
  static const welcome = '/welcome';
  static const settings = '/settings';
  static const gallery = '/debug/gallery';

  static String book(String bookId) => '/books/${Uri.encodeComponent(bookId)}';
  static String renameBook(String bookId) => '${book(bookId)}/rename';
  static String newEntry(String bookId) => '${book(bookId)}/entries/new';
  static String entry(String bookId, String entryId) =>
      '${book(bookId)}/entries/${Uri.encodeComponent(entryId)}';
  static String editEntry(String bookId, String entryId) =>
      '${entry(bookId, entryId)}/edit';
  static String image(String bookId, String entryId, String imageId) =>
      '${entry(bookId, entryId)}/images/${Uri.encodeComponent(imageId)}';
}

final routerProvider = Provider<GoRouter>((ref) {
  final hasStarted = ValueNotifier(ref.read(hasStartedProvider));
  ref.listen(hasStartedProvider, (_, next) => hasStarted.value = next);

  final router = GoRouter(
    initialLocation: _showGallery ? Routes.gallery : Routes.books,
    refreshListenable: hasStarted,
    redirect: (context, state) {
      final path = state.uri.path;
      if (path.startsWith('/debug/')) return null;

      final atWelcome = path == Routes.welcome;
      if (!hasStarted.value) return atWelcome ? null : Routes.welcome;
      return atWelcome ? Routes.books : null;
    },

    routes: [
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: Routes.books,
        builder: (_, _) => const BookListScreen(),
        routes: [
          GoRoute(path: 'settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(
            path: 'new-book',
            builder: (_, _) => const CreateBookScreen(),
          ),
          GoRoute(
            path: 'books/:bookId',
            builder: (_, s) => BookScreen(bookId: s.pathParameters['bookId']!),
            routes: [
              GoRoute(
                path: 'rename',
                builder: (_, s) =>
                    RenameBookScreen(bookId: s.pathParameters['bookId']!),
              ),
              GoRoute(
                path: 'entries/new',
                builder: (_, s) =>
                    EntryEditorScreen(bookId: s.pathParameters['bookId']!),
              ),
              GoRoute(
                path: 'entries/:entryId',
                builder: (_, s) => EntryReadScreen(
                  bookId: s.pathParameters['bookId']!,
                  entryId: s.pathParameters['entryId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, s) => EntryEditorScreen(
                      bookId: s.pathParameters['bookId']!,
                      entryId: s.pathParameters['entryId'],
                    ),
                  ),
                  GoRoute(
                    path: 'images/:imageId',
                    builder: (_, s) => ImageViewerScreen(
                      imageId: s.pathParameters['imageId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      if (kDebugMode)
        GoRoute(path: Routes.gallery, builder: (_, _) => const Gallery()),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    hasStarted.dispose();
  });

  return router;
});
