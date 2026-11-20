import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:kronoer/src/entries/entry.dart';

/// How many characters a query needs before it is searched.
const searchMinLength = 2;

/// Whether [query] is long enough to search.
bool isSearchable(String query) =>
    query.trim().characters.length >= searchMinLength;

/// One Entry found by a search.
@immutable
class SearchHit {
  const SearchHit({required this.entry, required this.snippet});

  final Entry entry;

  /// A short part of the text around the match, with each matching word
  /// between [matchStart] and [matchEnd]. Never show it as is: see
  /// `snippetSpans`.
  final String snippet;
}

/// Marks the start of a match in a snippet.
const matchStart = '\u{e000}';

/// Marks the end of a match in a snippet.
const matchEnd = '\u{e001}';

/// A page of search results.
@immutable
class SearchResults {
  const SearchResults({
    required this.hits,
    required this.total,
    required this.perBook,
  });

  /// The matching Entries on this page, newest Entry date first.
  final List<SearchHit> hits;

  /// How many Entries match in all, within the Book searched if one was given.
  final int total;

  /// How many Entries match in each Book, by Book ID, ignoring the Book
  /// searched.
  final Map<String, int> perBook;
}

abstract interface class SearchRepository {
  /// Entries in which every word of [query] starts a word, newest Entry date
  /// first, within the Book [bookId] if given. Letters match with or without
  /// diacritics.
  Future<SearchResults> search(
    String query, {
    String? bookId,
    required int limit,
    int offset = 0,
  });
}
