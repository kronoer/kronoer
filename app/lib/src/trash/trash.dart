import 'package:flutter/foundation.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/entry.dart';

/// How many days a Book or an Entry stays in the Trash, counted from when it
/// was deleted, until the user chooses otherwise. The core deletes it for good
/// after that.
const defaultTrashDays = 30;

/// The numbers of days the user can choose for the Trash to keep what is
/// deleted.
const trashDayChoices = [7, 30, 90];

/// A Book or an Entry in the Trash.
@immutable
sealed class TrashItem {
  const TrashItem({required this.deletedAt, required this.purgeAt});

  /// When it was deleted.
  final DateTime deletedAt;

  /// When it is deleted for good.
  final DateTime purgeAt;

  /// The ID of the Book or the Entry.
  String get id;

  /// How many days are left before it is deleted for good, counted up: 30
  /// just after it was deleted, 1 on its last day.
  int daysLeft(DateTime now) {
    final left = purgeAt.difference(now);
    if (left <= Duration.zero) return 0;
    return (left.inMilliseconds / Duration.millisecondsPerDay).ceil();
  }
}

/// A Book in the Trash, with the Entries that went with it.
final class TrashedBook extends TrashItem {
  const TrashedBook({
    required this.book,
    required this.entryCount,
    required super.deletedAt,
    required super.purgeAt,
  });

  final Book book;

  /// How many Entries come back with it. Entries deleted from it before are
  /// items of their own.
  final int entryCount;

  @override
  String get id => book.id;
}

/// An Entry deleted on its own.
final class TrashedEntry extends TrashItem {
  const TrashedEntry({
    required this.entry,
    required this.bookName,
    required this.bookInTrash,
    required super.deletedAt,
    required super.purgeAt,
  });

  final Entry entry;

  /// The name of its Book.
  final String bookName;

  /// Whether its Book is in the Trash too. Restoring it then asks where it
  /// goes.
  final bool bookInTrash;

  @override
  String get id => entry.id;
}

abstract interface class TrashRepository {
  /// Every Book and Entry in the Trash, the one deleted most recently first.
  Stream<List<TrashItem>> watchTrash();

  /// Moves a Book to the Trash with its Entries. It is no longer pinned or
  /// kept out of the Timeline, and restoring it does not bring that back.
  Future<void> trashBook(String id);

  /// Moves Entries to the Trash, all of them or none. Each keeps its Images
  /// and star there.
  Future<void> trashEntries(Iterable<String> ids);

  /// Takes Books and Entries out of the Trash, all of them or none. A Book
  /// comes back with the Entries that went with it. An Entry whose Book is
  /// in the Trash and not restored here goes to the Book [othersTo]; without
  /// one, its Book is restored too.
  Future<void> restore({
    Iterable<String> bookIds = const [],
    Iterable<String> entryIds = const [],
    String? othersTo,
  });

  /// Deletes Books and Entries for good, all of them or none. A Book goes
  /// with all its Entries.
  Future<void> deleteForever({
    Iterable<String> bookIds = const [],
    Iterable<String> entryIds = const [],
  });

  /// Deletes everything in the Trash for good.
  Future<void> emptyTrash();

  /// How many days the Trash keeps what is deleted: one of
  /// [trashDayChoices].
  Stream<int> watchTrashDays();

  /// Sets how many days the Trash keeps what is deleted, one of
  /// [trashDayChoices], and deletes for good at once what was deleted longer
  /// ago than that.
  Future<void> setTrashDays(int days);
}
