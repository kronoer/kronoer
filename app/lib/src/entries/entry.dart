import 'package:flutter/foundation.dart';

/// Entry text as one paragraph, for previews in lists.
String previewText(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

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
  });

  final String id;
  final String bookId;
  final String text;
  final DateTime dateTime;
  final List<String> imageIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Entry copyWith({
    String? text,
    DateTime? dateTime,
    List<String>? imageIds,
    DateTime? updatedAt,
  }) => Entry(
    id: id,
    bookId: bookId,
    text: text ?? this.text,
    dateTime: dateTime ?? this.dateTime,
    imageIds: imageIds ?? this.imageIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
