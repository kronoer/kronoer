import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/export/export.dart';
import 'package:kronoer/src/import/import.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/storage/core_repository.dart';
import 'package:kronoer/src/storage/storage.dart';

/// A core store in a new temporary folder, for one test.
class TestStore {
  TestStore._(this.dir, this.store) : repository = CoreRepository(store);

  /// Opens one. Call it outside a widget test's fake time: in `setUp`, or in
  /// `tester.runAsync`.
  static Future<TestStore> open() async {
    final dir = await Directory.systemTemp.createTemp('kronoer_widget_test');
    final store = await CoreStore.open(
      dir: dir.path,
      keyring: Keyring.generate(),
    );
    return TestStore._(dir, store);
  }

  final Directory dir;
  final CoreStore store;
  final CoreRepository repository;

  /// Every repository the app reads, over this store.
  List<Override> get overrides => [
    bookRepositoryProvider.overrideWithValue(repository),
    entryRepositoryProvider.overrideWithValue(repository),
    trashRepositoryProvider.overrideWithValue(repository),
    searchRepositoryProvider.overrideWithValue(repository),
    archiveWriterProvider.overrideWithValue(CoreArchiveWriter(store)),
    archiveReaderProvider.overrideWithValue(CoreArchiveReader(store)),
  ];

  Future<void> close() async {
    repository.dispose();
    store.dispose();
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the database file open; the system cleans its
      // temp folder.
    }
  }
}

/// Lets the core answer: its calls finish in real time, which a widget test's
/// fake time never gives them. Then pumps a frame, [times] over, so calls
/// that start other calls finish too.
Future<void> settleCore(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
