import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/src/books/book_description_screen.dart';
import 'package:kronoer/src/books/book_info_screen.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_name_screen.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/books/cover_viewer_screen.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_read_screen.dart';
import 'package:kronoer/src/entries/image_viewer_screen.dart';
import 'package:kronoer/src/entries/starred_entries_screen.dart';
import 'package:kronoer/src/export/export_screen.dart';
import 'package:kronoer/src/import/import_screen.dart';
import 'package:kronoer/src/home/home_shell.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/lock/locked_books_screen.dart';
import 'package:kronoer/src/search/search_bar_hero.dart';
import 'package:kronoer/src/search/search_screen.dart';
import 'package:kronoer/src/settings/about_screen.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/trash/trash_screen.dart';
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

  /// "Punya arsip? Impor": the Import page, before the user has started.
  static const welcomeImport = '$welcome/import';
  static const timeline = '/timeline';

  /// "Book di Linimasa": which Books the Timeline shows.
  static const timelineBooks = '$timeline/books';
  static const settings = '/settings';
  static const theme = '$settings/theme';
  static const language = '$settings/language';

  /// "Kunci lagi": how long until App lock asks again.
  static const lockAgain = '$settings/lock-again';
  static const about = '$settings/about';

  /// "Ekspor Data": every Book into one unencrypted Archive.
  static const export = '$settings/export';
  static const import = '$settings/import';
  static const licenses = '$about/licenses';
  static const trash = '$settings/trash';
  static const trashItems = '$trash/items';
  static const gallery = '/debug/gallery';

  /// "Book terkunci": the Locked Books area. A Locked Book's own screens are
  /// under it, at the same paths as any Book's after this prefix; the router
  /// puts them there.
  static const lockedBooks = '/locked';

  /// Whether [path] is in the Book terkunci area.
  static bool inLockedBooks(String path) =>
      path == lockedBooks || path.startsWith('$lockedBooks/');

  /// Search in every Book, starting with [query].
  static String search({String query = ''}) => _withQuery('/search', query);

  static String book(String bookId) => '/books/${Uri.encodeComponent(bookId)}';

  /// Search in one Book, starting with [query].
  static String bookSearch(String bookId, {String query = ''}) =>
      _withQuery('${book(bookId)}/search', query);

  static String trashItem(String id) =>
      '$trashItems/${Uri.encodeComponent(id)}';

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

/// The navigator over the tabs, for dialogs shown from outside any screen.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// A screen over the tabs, hiding the bottom navigation.
GoRoute _over({
  required String path,
  GoRouterWidgetBuilder? builder,
  GoRouterPageBuilder? pageBuilder,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  parentNavigatorKey: rootNavigatorKey,
  builder: builder,
  pageBuilder: pageBuilder,
  routes: routes,
);

/// A Book and the screens under it, at `books/:bookId`: on the Book list, and
/// in the Book terkunci area for a Locked Book.
GoRoute _bookRoute() => _over(
  path: 'books/:bookId',
  builder: (_, s) => BookScreen(bookId: s.pathParameters['bookId']!),
  routes: [
    _over(
      path: 'info',
      builder: (_, s) => BookInfoScreen(bookId: s.pathParameters['bookId']!),
      routes: [
        _over(
          path: 'rename',
          builder: (_, s) =>
              RenameBookScreen(bookId: s.pathParameters['bookId']!),
        ),
        _over(
          path: 'description',
          builder: (_, s) =>
              BookDescriptionScreen(bookId: s.pathParameters['bookId']!),
        ),
        _over(
          path: 'starred',
          builder: (_, s) =>
              StarredEntriesScreen(bookId: s.pathParameters['bookId']!),
        ),
        _over(
          path: 'cover',
          builder: (_, s) =>
              CoverViewerScreen(bookId: s.pathParameters['bookId']!),
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
);

final _bookPath = RegExp(r'^/books/([^/]+)');

/// Where a trip to [uri] goes, given the Book terkunci area: a Locked Book's
/// screens are only inside it, under [Routes.lockedBooks], and only while it
/// is [open]. Screens link to a Book by [Routes.book] and friends; this
/// puts a Locked Book's there. Outside the area, a Locked Book goes nowhere
/// but the Book list.
String? _lockedBooksRedirect(
  Uri uri, {
  required bool open,
  required Set<String> locked,
}) {
  final path = uri.path;
  if (Routes.inLockedBooks(path)) return open ? null : Routes.books;
  final match = _bookPath.firstMatch(path);
  if (match == null || !locked.contains(Uri.decodeComponent(match[1]!))) {
    return null;
  }
  return open ? '${Routes.lockedBooks}$uri' : Routes.books;
}

final routerProvider = Provider<GoRouter>((ref) {
  final hasStarted = ValueNotifier(ref.read(hasStartedProvider));
  ref.listen(hasStartedProvider, (_, next) => hasStarted.value = next);
  bool lockedBooksOpen() => ref.read(appLockProvider).lockedBooksOpen;
  final areaOpen = ValueNotifier(lockedBooksOpen());
  ref.listen(
    appLockProvider.select((lock) => lock.lockedBooksOpen),
    (_, next) => areaOpen.value = next,
  );
  // Kept alive here, so the redirect knows which Books are locked.
  ref.listen(lockedBookSummariesProvider, (_, _) {});

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: _showGallery ? Routes.gallery : Routes.books,
    refreshListenable: Listenable.merge([hasStarted, areaOpen]),
    redirect: (context, state) {
      final path = state.uri.path;
      if (path.startsWith('/debug/')) return null;

      final atWelcome = path == Routes.welcome;
      if (!hasStarted.value) {
        return atWelcome || path == Routes.welcomeImport
            ? null
            : Routes.welcome;
      }
      // An Import from Welcome that added something starts the app, and
      // its summary stays open until the user leaves it.
      if (atWelcome) return Routes.books;
      return _lockedBooksRedirect(
        state.uri,
        open: areaOpen.value,
        locked: {
          for (final summary
              in ref.read(lockedBookSummariesProvider).value ?? const [])
            summary.book.id,
        },
      );
    },

    routes: [
      GoRoute(
        path: Routes.welcome,
        builder: (_, _) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'import',
            builder: (_, _) => const ImportScreen(back: Routes.welcome),
          ),
        ],
      ),
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
                  _bookRoute(),
                  _over(
                    path: 'locked',
                    builder: (_, _) => const LockedBooksScreen(),
                    routes: [_bookRoute()],
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
                    path: 'lock-again',
                    builder: (_, _) => const LockAgainScreen(),
                  ),
                  _over(
                    path: 'export',
                    builder: (_, _) => const ExportScreen(),
                  ),
                  _over(
                    path: 'import',
                    builder: (_, _) => const ImportScreen(),
                  ),
                  _over(
                    path: 'trash',
                    builder: (_, _) => const TrashScreen(),
                    routes: [
                      _over(
                        path: 'items',
                        builder: (_, _) => const TrashListScreen(),
                        routes: [
                          _over(
                            path: ':itemId',
                            builder: (_, s) => TrashItemScreen(
                              id: s.pathParameters['itemId']!,
                            ),
                          ),
                        ],
                      ),
                    ],
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

  // Leaving the area, back to the Book list or anywhere else, locks it
  // again.
  var inArea = false;
  void moved() {
    final now = Routes.inLockedBooks(
      router.routerDelegate.currentConfiguration.uri.path,
    );
    if (inArea && !now) {
      // Not while the router is still building.
      Future.microtask(() {
        if (ref.mounted) ref.read(appLockProvider.notifier).closeLockedBooks();
      });
    }
    inArea = now;
  }

  router.routerDelegate.addListener(moved);

  ref.onDispose(() {
    router.routerDelegate.removeListener(moved);
    router.dispose();
    hasStarted.dispose();
    areaOpen.dispose();
  });

  return router;
});
