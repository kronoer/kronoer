import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/trash/trash.dart';

/// Every Book and Entry in the Trash, the one deleted most recently first.
final trashProvider = StreamProvider.autoDispose<List<TrashItem>>(
  (ref) => ref.watch(trashRepositoryProvider).watchTrash(),
);

/// How many days the Trash keeps what is deleted. Kept alive, like a
/// setting, so a dialog can read it at once.
final trashDaysProvider = StreamProvider<int>(
  (ref) => ref.watch(trashRepositoryProvider).watchTrashDays(),
);
