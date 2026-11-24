import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kronoer/src/export/export.dart';
import 'package:kronoer/src/import/import.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/storage/core_repository.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app starts with on an open [store]: the repositories over it, the
/// [saved] settings, and whether the user has started.
///
/// Throws a [StoreFailure] if the store cannot list its Books.
Future<List<Override>> launchOverrides({
  required CoreStore store,
  required SharedPreferencesAsync preferences,
  required SavedSettings saved,
}) async {
  final hasBooks = (await store.listBooks()).isNotEmpty;
  final started = await hasStartedAtLaunch(
    preferences,
    saved,
    hasBooks: hasBooks,
  );

  final repository = CoreRepository(store);
  return [
    ...saved.overrides(preferences),
    bookRepositoryProvider.overrideWithValue(repository),
    entryRepositoryProvider.overrideWithValue(repository),
    trashRepositoryProvider.overrideWithValue(repository),
    searchRepositoryProvider.overrideWithValue(repository),
    archiveWriterProvider.overrideWithValue(CoreArchiveWriter(store)),
    archiveReaderProvider.overrideWithValue(CoreArchiveReader(store)),
    hasStartedProvider.overrideWith(() => HasStartedNotifier(started)),
  ];
}
