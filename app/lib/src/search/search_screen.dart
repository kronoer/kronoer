import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry_text.dart';
import 'package:kronoer/src/entries/star_mark.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/search/highlight.dart';
import 'package:kronoer/src/search/search.dart';
import 'package:kronoer/src/search/search_bar_hero.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// How long typing pauses before what was typed is searched.
const searchDelay = Duration(milliseconds: 150);

/// How many Entries of each Book the search across all Books shows.
const resultsPerBook = 3;

/// How many Entries one page of a search in a Book loads.
const _pageSize = 20;

/// What the screen shows for one query.
sealed class _Results {
  const _Results(this.query, this.total);

  /// What was searched, as typed.
  final String query;

  /// How many Entries match.
  final int total;
}

/// Across all Books: the first results of each Book, in Book list order.
final class _AllResults extends _Results {
  const _AllResults(super.query, super.total, this.groups);

  final List<_Group> groups;
}

final class _Group {
  const _Group(this.book, this.count, this.hits);

  final Book book;
  final int count;
  final List<SearchHit> hits;
}

/// In one Book: the results loaded so far, newest Entry date first.
final class _BookResults extends _Results {
  const _BookResults(super.query, super.total, this.hits);

  final List<SearchHit> hits;
}

/// Searches Entries by their text: in every Book, or in the Book [bookId].
///
/// Results follow what is typed from [searchMinLength] characters, once
/// typing pauses for [searchDelay]. The field never lets the keyboard learn
/// from what is typed.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.bookId, this.query = '', super.key});

  /// The Book searched, or null for every Book.
  final String? bookId;

  /// What the field starts with.
  final String query;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _field = TextEditingController(text: widget.query);
  final _focus = FocusNode();
  Timer? _timer;

  /// Counts searches, so an older one that answers late is ignored.
  var _generation = 0;
  _Results? _results;
  var _loadingMore = false;

  @override
  void initState() {
    super.initState();
    if (isSearchable(widget.query)) _search(widget.query);

    // Every change to the store changes the Book list: search again, so a
    // changed or deleted Entry is never shown as it was.
    ref.listenManual(bookSummariesProvider, (previous, next) {
      final results = _results;
      if (previous?.value != null && results != null) {
        _search(results.query, atLeast: _shownCount(results));
      }
    });
  }

  /// The route's animation while waiting for it to finish before focusing.
  Animation<double>? _arriving;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.bookId != null || _arriving != null) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return;
    _arriving = animation;
    // Before the first frame the route has not started its push, and its
    // animation may read as complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (animation.isCompleted) {
        _focus.requestFocus();
      } else {
        animation.addStatusListener(_arrived);
      }
    });
  }

  void _arrived(AnimationStatus status) {
    if (!status.isCompleted) return;
    _arriving?.removeStatusListener(_arrived);
    // Until the end of this frame the Hero still holds a placeholder where
    // the field goes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Widget _heroIfAllBooks(Widget bar) =>
      widget.bookId == null ? SearchBarHero(child: bar) : bar;

  @override
  void dispose() {
    _arriving?.removeStatusListener(_arrived);
    _timer?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  static int _shownCount(_Results results) => switch (results) {
    _AllResults() => 0,
    _BookResults(:final hits) => hits.length,
  };

  void _changed(String text) {
    _timer?.cancel();
    if (!isSearchable(text)) {
      _generation++;
      setState(() => _results = null);
      return;
    }
    setState(() {});
    _timer = Timer(searchDelay, () => _search(text));
  }

  void _submitted(String text) {
    _timer?.cancel();
    if (isSearchable(text)) _search(text);
  }

  void _clear() {
    _field.clear();
    _changed('');
    _focus.requestFocus();
  }

  Future<void> _search(String query, {int atLeast = 0}) async {
    final generation = ++_generation;
    final repository = ref.read(searchRepositoryProvider);
    final bookId = widget.bookId;

    final _Results results;
    if (bookId == null) {
      final summary = await repository.search(query, limit: 0);
      final books = await ref.read(bookSummariesProvider.future);
      final groups = await Future.wait([
        for (final BookSummary(:book) in books)
          if ((summary.perBook[book.id] ?? 0) > 0)
            repository
                .search(query, bookId: book.id, limit: resultsPerBook)
                .then((page) => _Group(book, page.total, page.hits)),
      ]);
      results = _AllResults(query, summary.total, groups);
    } else {
      final page = await repository.search(
        query,
        bookId: bookId,
        limit: max(_pageSize, atLeast),
      );
      results = _BookResults(query, page.total, page.hits);
    }

    if (!mounted || generation != _generation) return;
    setState(() => _results = results);
  }

  Future<void> _loadMore() async {
    final results = _results;
    final bookId = widget.bookId;
    if (_loadingMore ||
        bookId == null ||
        results is! _BookResults ||
        results.hits.length >= results.total) {
      return;
    }

    _loadingMore = true;
    final generation = _generation;
    try {
      final page = await ref
          .read(searchRepositoryProvider)
          .search(
            results.query,
            bookId: bookId,
            limit: _pageSize,
            offset: results.hits.length,
          );
      if (!mounted || generation != _generation) return;
      setState(
        () => _results = _BookResults(results.query, page.total, [
          ...results.hits,
          ...page.hits,
        ]),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Switches a search in one Book to every Book, with what is typed. Back
  /// returns here.
  void _searchAllBooks() =>
      context.push(Routes.search(query: _field.text.trim()));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bookId = widget.bookId;
    final bookName = bookId == null
        ? null
        : ref.watch(bookProvider(bookId)).value?.name ?? '';

    final hint = bookName == null
        ? l10n.searchAllBooks
        : l10n.searchInBook(bookName);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 72,
        titleSpacing: Space.l,
        // From the Book list, the bar there moves up into this one.
        title: _heroIfAllBooks(
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: theme.colorScheme.surfaceContainerHigh,
            ),
            child: Row(
              children: [
                const BackButton(),
                Expanded(
                  child: TextField(
                    controller: _field,
                    focusNode: _focus,
                    // Across all Books the keyboard waits for the bar to
                    // arrive; see [didChangeDependencies].
                    autofocus: widget.bookId != null,
                    enableIMEPersonalizedLearning: false,
                    textInputAction: TextInputAction.search,
                    style: theme.textTheme.bodyLarge,
                    // The pill is the field: no outline in any state, or the
                    // theme's would be drawn inside it.
                    decoration:
                        InputDecoration.collapsed(
                          hintText: hint,
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ).copyWith(
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                    onChanged: _changed,
                    onSubmitted: _submitted,
                  ),
                ),
                if (_field.text.isNotEmpty)
                  IconButton(
                    tooltip: l10n.searchClear,
                    color: theme.colorScheme.onSurfaceVariant,
                    onPressed: _clear,
                    icon: const KIcon(KIcons.x, size: 22),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: switch (_results) {
        null when isSearchable(_field.text) => const SizedBox.shrink(),
        null => _Start(
          bookName == null
              ? l10n.searchStartAll
              : l10n.searchStartBook(bookName),
        ),
        _AllResults(total: 0, :final query) => _NoneAll(query),
        final _AllResults results => _AllList(results: results),
        _BookResults(total: 0, :final query) => _NoneBook(
          query: query,
          bookName: bookName ?? '',
          onSearchAll: _searchAllBooks,
        ),
        final _BookResults results => NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 600) _loadMore();
            return false;
          },
          child: _BookList(
            results: results,
            hits: results.hits,
            bookName: bookName ?? '',
            onSearchAll: _searchAllBooks,
          ),
        ),
      },
    );
  }
}

class _Start extends StatelessWidget {
  const _Start(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xxl,
        vertical: Space.xl,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

TextStyle? _metaStyle(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
  color: theme.colorScheme.onSurfaceVariant,
);

class _AllList extends StatelessWidget {
  const _AllList({required this.results});

  final _AllResults results;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = _metaStyle(theme);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.xl),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          child: Text(
            l10n.searchFoundAll(
              l10n.entryCount(results.total),
              l10n.bookCount(results.groups.length),
            ),
            style: meta,
          ),
        ),
        for (final group in results.groups) ...[
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  spacing: Space.m,
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          group.book.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    Text(l10n.entryCount(group.count), style: meta),
                  ],
                ),
              ),
              for (final hit in group.hits)
                _ResultCard(hit, query: results.query, lines: 2),
              if (group.count > group.hits.length)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => context.push(
                      Routes.bookSearch(group.book.id, query: results.query),
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const KIcon(KIcons.chevronRight, size: 18),
                    label: Text(
                      l10n.searchMore(group.count - group.hits.length),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BookList extends StatelessWidget {
  const _BookList({
    required this.results,
    required this.hits,
    required this.bookName,
    required this.onSearchAll,
  });

  final _BookResults results;
  final List<SearchHit> hits;
  final String bookName;
  final VoidCallback onSearchAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
      itemCount: hits.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: Space.m),
      itemBuilder: (context, i) {
        if (i > 0) {
          return _ResultCard(hits[i - 1], query: results.query, lines: 3);
        }
        return Row(
          spacing: Space.m,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: Space.xs),
                child: Text(
                  l10n.searchFoundBook(
                    l10n.entryCount(results.total),
                    bookName,
                  ),
                  style: _metaStyle(theme),
                ),
              ),
            ),
            TextButton(
              onPressed: onSearchAll,
              child: Text(l10n.searchAllBooks),
            ),
          ],
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(this.hit, {required this.query, required this.lines});

  final SearchHit hit;
  final String query;

  /// How many lines of the snippet show.
  final int lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final meta = _metaStyle(theme);
    final entry = hit.entry;
    final styles = theme.extension<EntryTextStyles>()!;
    final snippetStyle = lines > 2
        ? styles.entryPreview
        : styles.entryPreviewSmall.copyWith(color: theme.colorScheme.onSurface);

    return KCard(
      onTap: () =>
          context.push(Routes.entry(entry.bookId, entry.id, query: query)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: lines > 2 ? Space.s : 6,
        children: [
          Row(
            spacing: Space.m,
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMM', locale).format(entry.dateTime),
                  style: meta?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  if (entry.starred) const StarMark(),
                  Text(
                    DateFormat.Hm(locale).format(entry.dateTime),
                    style: meta,
                  ),
                ],
              ),
            ],
          ),
          Text.rich(
            snippetSpan(
              hit.snippet,
              highlightStyle(theme.colorScheme),
              TextStyleLook.of(context),
              fontSize: snippetStyle.fontSize,
            ),
            style: snippetStyle,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Shown when nothing matched, centred a little above the middle.
class _None extends StatelessWidget {
  const _None({required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.m,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: ShapeDecoration(
                shape: const CircleBorder(),
                color: scheme.surfaceContainerHigh,
              ),
              alignment: Alignment.center,
              child: KIcon(
                KIcons.search,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                height: 26 / 18,
              ),
            ),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: action,
              ),
          ],
        ),
      ),
    );
  }
}

/// The first letters of the first word of [query] to suggest searching
/// instead, or null when that word is too short to shorten.
String? _shorterStart(String query) {
  final words = query.trim().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true));
  final word = words.firstWhere((word) => word.isNotEmpty, orElse: () => '');
  final letters = word.characters;
  return letters.length > 3 ? letters.take(3).toString() : null;
}

class _NoneAll extends StatelessWidget {
  const _NoneAll(this.query);

  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final start = _shorterStart(query);

    return _None(
      title: l10n.searchNoneAll(query.trim()),
      message: start == null
          ? l10n.searchNoneHint
          : l10n.searchNoneHintExample(start),
    );
  }
}

class _NoneBook extends StatelessWidget {
  const _NoneBook({
    required this.query,
    required this.bookName,
    required this.onSearchAll,
  });

  final String query;
  final String bookName;
  final VoidCallback onSearchAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _None(
      title: l10n.searchNoneBook(query.trim(), bookName),
      message: l10n.searchNoneBookHint,
      action: FilledButton.tonalIcon(
        onPressed: onSearchAll,
        icon: const KIcon(KIcons.search, size: 20),
        label: Text(l10n.searchAllBooks),
      ),
    );
  }
}
