import 'package:flutter/foundation.dart';

@immutable
class Entry {
  const Entry({
    required this.id,
    required this.bookId,
    required this.text,
    required this.dateTime,
    required this.createdAt,
    required this.updatedAt,
    this.imageIds = const [],
    this.starred = false,
  });

  final String id;
  final String bookId;
  final String text;
  final DateTime dateTime;
  final List<String> imageIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the user starred this Entry. Starring is not editing: it leaves
  /// [updatedAt] as it is.
  final bool starred;

  Entry copyWith({
    String? bookId,
    String? text,
    DateTime? dateTime,
    List<String>? imageIds,
    DateTime? updatedAt,
    bool? starred,
  }) => Entry(
    id: id,
    bookId: bookId ?? this.bookId,
    text: text ?? this.text,
    dateTime: dateTime ?? this.dateTime,
    imageIds: imageIds ?? this.imageIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    starred: starred ?? this.starred,
  );
}
