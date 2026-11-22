import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/src/books/book_description_screen.dart';
import 'package:kronoer/src/books/book_info_screen.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_name_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/books/cover_viewer_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/image_viewer_screen.dart';
import 'package:kronoer/src/entries/starred_entries_screen.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/search/search_bar_hero.dart';
import 'package:kronoer/src/search/search_screen.dart';
import 'package:kronoer/src/settings/about_screen.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/timeline/timeline_books_screen.dart';
import 'package:kronoer/src/timeline/timeline_screen.dart';
import 'package:kronoer/src/ui/gallery.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:kronoer/src/welcome/welcome_screen.dart';

const _showGallery = kDebugMode && bool.fromEnvironment('KRONOER_GALLERY');

abstract final class Routes {
  static const books = '/';
  static const newBook = '/new-book';
  static const welcome = '/welcome';
  static const timeline = '/timeline';

  /// "Book di Linimasa": which Books the Timeline shows.
  static const timelineBooks = '$timeline/books';
  static const settings = '/settings';
  static const theme = '$settings/theme';
  static const language = '$settings/language';
  static const about = '$settings/about';
  static const licenses = '$about/licenses';
  static const gallery = '/debug/gallery';

  /// Search in every Book, starting with [query].
  static String search({String query = ''}) => _withQuery('/search', query);

  static String book(String bookId) => '/books/${Uri.encodeComponent(bookId)}';

  /// Search in one Book, starting with [query].
  static String bookSearch(String bookId, {String query = ''}) =>
      _withQuery('${book(bookId)}/search', query);

  static String bookInfo(String bookId) => '${book(bookId)}/info';
  static String renameBook(String bookId) => '${bookInfo(bookId)}/rename';
  static String editBookDescription(String bookId) =>
      '${bookInfo(bookId)}/description';

  /// "Entry berbintang": the Book's Starred Entries.
  static String starredEntries(String bookId) => '${bookInfo(bookId)}/starred';

  /// The Book's Cover, full screen.
  static String bookCover(String bookId) => '${bookInfo(bookId)}/cover';
  static String newEntry(String bookId) => '${book(bookId)}/entries/new';

  /// The editor for the first Entry, right after Welcome.
  static String firstEntry(String bookId) => '${newEntry(bookId)}?first=true';

  /// An Entry, read only. With a [query], the words it matches are marked.
  static String entry(String bookId, String entryId, {String query = ''}) =>
      _withQuery(_entry(bookId, entryId), query);
  static String editEntry(String bookId, String entryId) =>
      '${_entry(bookId, entryId)}/edit';
  static String image(String bookId, String entryId, String imageId) =>
      '${_entry(bookId, entryId)}/images/${Uri.encodeComponent(imageId)}';

  static String _entry(String bookId, String entryId) =>
      '${book(bookId)}/entries/${Uri.encodeComponent(entryId)}';

  static String _withQuery(String path, String query) => query.isEmpty
      ? path
      : Uri(path: path, queryParameters: {'q': query}).toString();
}

final _rootNavigator = GlobalKey<NavigatorState>();

/// A screen over the tabs, hiding the bottom navigation.
GoRoute _over({
  required String path,
  GoRouterWidgetBuilder? builder,
  GoRouterPageBuilder? pageBuilder,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  parentNavigatorKey: _rootNavigator,
  builder: builder,
  pageBuilder: pageBuilder,
  routes: routes,
);

final routerProvider = Provider<GoRouter>((ref) {
  final hasStarted = ValueNotifier(ref.read(hasStartedProvider));
  ref.listen(hasStartedProvider, (_, next) => hasStarted.value = next);

  final router = GoRouter(
    navigatorKey: _rootNavigator,
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
      // The three tabs. Every other screen goes on the root navigator, over
      // the bottom navigation, so the bar shows only on the tabs.
      StatefulShellRoute(
        builder: (_, _, shell) => shell,
        navigatorContainerBuilder: (_, shell, tabs) =>
            HomeShell(shell: shell, tabs: tabs),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.books,
                builder: (_, _) => const BookListScreen(),
                routes: [
                  _over(
                    path: 'new-book',
                    builder: (_, _) => const CreateBookScreen(),
                  ),
                  _over(
                    path: 'search',
                    pageBuilder: (_, s) => CustomTransitionPage(
                      key: s.pageKey,
                      transitionsBuilder: fadeThrough,
                      child: SearchScreen(
                        query: s.uri.queryParameters['q'] ?? '',
                      ),
                    ),
                  ),
                  _over(
                    path: 'books/:bookId',
                    builder: (_, s) =>
                        BookScreen(bookId: s.pathParameters['bookId']!),
                    routes: [
                      _over(
                        path: 'info',
                        builder: (_, s) =>
                            BookInfoScreen(bookId: s.pathParameters['bookId']!),
                        routes: [
                          _over(
                            path: 'rename',
                            builder: (_, s) => RenameBookScreen(
                              bookId: s.pathParameters['bookId']!,
                            ),
                          ),
                          _over(
                            path: 'description',
                            builder: (_, s) => BookDescriptionScreen(
                              bookId: s.pathParameters['bookId']!,
                            ),
                          ),
                          _over(
                            path: 'starred',
                            builder: (_, s) => StarredEntriesScreen(
                              bookId: s.pathParameters['bookId']!,
                            ),
                          ),
                          _over(
                            path: 'cover',
                            builder: (_, s) => CoverViewerScreen(
                              bookId: s.pathParameters['bookId']!,
                            ),
                          ),
                        ],
                      ),
                      _over(
                        path: 'search',
                        builder: (_, s) => SearchScreen(
                          bookId: s.pathParameters['bookId'],
                          query: s.uri.queryParameters['q'] ?? '',
                        ),
                      ),
                      _over(
                        path: 'entries/new',
                        builder: (_, s) => EntryEditorScreen(
                          bookId: s.pathParameters['bookId']!,
                          isFirst: s.uri.queryParameters['first'] == 'true',
                        ),
                      ),
                      _over(
                        path: 'entries/:entryId',
                        builder: (_, s) => EntryReadScreen(
                          bookId: s.pathParameters['bookId']!,
                          entryId: s.pathParameters['entryId']!,
                          query: s.uri.queryParameters['q'] ?? '',
                        ),
                        routes: [
                          _over(
                            path: 'edit',
                            builder: (_, s) => EntryEditorScreen(
                              bookId: s.pathParameters['bookId']!,
                              entryId: s.pathParameters['entryId'],
                            ),
                          ),
                          _over(
                            path: 'images/:imageId',
                            builder: (_, s) => ImageViewerScreen(
                              bookId: s.pathParameters['bookId']!,
                              entryId: s.pathParameters['entryId']!,
                              imageId: s.pathParameters['imageId']!,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.timeline,
                builder: (_, _) => const TimelineScreen(),
                routes: [
                  _over(
                    path: 'books',
                    builder: (_, _) => const TimelineBooksScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  _over(path: 'theme', builder: (_, _) => const ThemeScreen()),
                  _over(
                    path: 'language',
                    builder: (_, _) => const LanguageScreen(),
                  ),
                  _over(
                    path: 'about',
                    builder: (_, _) => const AboutScreen(),
                    routes: [
                      _over(
                        path: 'licenses',
                        builder: (_, _) => const LicensesScreen(),
                      ),
                    ],
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
