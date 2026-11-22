import 'package:flutter/foundation.dart';

@immutable
class Book {
  const Book({
    required this.id,
    required this.name,
    this.description = '',
    this.coverId,
    required this.lastActivityAt,
    this.pinned = false,
    this.inTimeline = true,
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

  /// Whether the user pinned the Book on this device. Pinned Books come
  /// first in the Book list.
  final bool pinned;

  /// Whether the Book's Entries show in the Timeline on this device: true
  /// unless the user keeps it out. Nothing else changes for a Book kept out.
  final bool inTimeline;

  Book copyWith({
    String? name,
    String? description,
    String? Function()? coverId,
    DateTime? lastActivityAt,
    bool? pinned,
    bool? inTimeline,
  }) => Book(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    coverId: coverId == null ? this.coverId : coverId(),
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    pinned: pinned ?? this.pinned,
    inTimeline: inTimeline ?? this.inTimeline,
  );
}

@immutable
class BookSummary {
  const BookSummary({
    required this.book,
    this.lastEntryText,
    this.lastEntryImageCount = 0,
    this.entryCount = 0,
  });

  final Book book;

  /// The text of the Entry changed most recently: `null` when the Book has no Entries, empty
  /// when that Entry has only Images.
  final String? lastEntryText;

  /// How many Images the Entry changed most recently has.
  final int lastEntryImageCount;

  /// How many Entries the Book has.
  final int entryCount;
}

/// A Book insight: how many Entries, words, and Images a Book holds. It
/// describes the Book and never judges how often the user writes.
@immutable
class BookInsight {
  const BookInsight({
    this.entryCount = 0,
    this.wordCount = 0,
    this.imageCount = 0,
  });

  /// Every Entry in the Book.
  final int entryCount;

  /// The words in the text of all the Book's Entries. Text style marks are
  /// not words.
  final int wordCount;

  /// Every Image of the Book's Entries. The Cover is not one.
  final int imageCount;

  @override
  bool operator ==(Object other) =>
      other is BookInsight &&
      other.entryCount == entryCount &&
      other.wordCount == wordCount &&
      other.imageCount == imageCount;

  @override
  int get hashCode => Object.hash(entryCount, wordCount, imageCount);

  @override
  String toString() => 'BookInsight($entryCount, $wordCount, $imageCount)';
}
