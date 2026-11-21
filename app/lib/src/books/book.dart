import 'package:flutter/foundation.dart';

@immutable
class Book {
  const Book({
    required this.id,
    required this.name,
    this.description = '',
    required this.lastActivityAt,
  });

  final String id;
  final String name;

  /// The Book's Description: plain text that may hold line breaks. Empty when
  /// the Book has none.
  final String description;
  final DateTime lastActivityAt;

  Book copyWith({
    String? name,
    String? description,
    DateTime? lastActivityAt,
  }) => Book(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
  );
}

@immutable
class BookSummary {
  const BookSummary({
    required this.book,
    this.lastEntryText,
    this.lastEntryImageCount = 0,
  });

  final Book book;

  /// The text of the Entry changed most recently: `null` when the Book has no Entries, empty
  /// when that Entry has only Images.
  final String? lastEntryText;

  /// How many Images the Entry changed most recently has.
  final int lastEntryImageCount;
}
