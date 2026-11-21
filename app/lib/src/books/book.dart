import 'package:flutter/foundation.dart';

@immutable
class Book {
  const Book({
    required this.id,
    required this.name,
    this.description = '',
    this.coverId,
    required this.lastActivityAt,
  });

  final String id;
  final String name;

  /// The Book's Description: plain text that may hold line breaks. Empty when
  /// the Book has none.
  final String description;

  /// The Image ID of the Book's Cover, new with every new Cover; `null` when
  /// the Book has none.
  final String? coverId;
  final DateTime lastActivityAt;

  Book copyWith({
    String? name,
    String? description,
    String? Function()? coverId,
    DateTime? lastActivityAt,
  }) => Book(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    coverId: coverId == null ? this.coverId : coverId(),
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
