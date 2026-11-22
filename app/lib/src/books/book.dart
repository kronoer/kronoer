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
