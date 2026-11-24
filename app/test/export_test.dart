import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/export/export.dart';
import 'package:kronoer/src/export/export_platform.dart';
import 'package:kronoer/src/export/export_screen.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_app_lock_platform.dart';

/// The device's picker: it answers [picked], and remembers what is done
/// with the file.
class _FakeExportPlatform implements ExportPlatform {
  ArchiveTarget? picked = const ArchiveTarget(
    uri: 'content://downloads/kronoer',
    name: 'kronoer-2026-11-24.zip',
    fd: 42,
  );
  final suggested = <String>[];
  final finished = <String>[];
  final deleted = <String>[];
  final screenOn = <bool>[];

  @override
  Future<ArchiveTarget?> createArchive(String name) async {
    suggested.add(name);
    return picked;
  }

  @override
  Future<void> finishArchive(ArchiveTarget target) async =>
      finished.add(target.uri);

  @override
  Future<void> deleteArchive(ArchiveTarget target) async =>
      deleted.add(target.uri);

  @override
  Future<void> keepScreenOn(bool on) async => screenOn.add(on);
}

/// An Archive's write that goes only as far as the test says.
class _FakeWrite implements ArchiveWrite {
  final _finished = Completer<void>();

  @override
  int done = 0;

  @override
  int total = 0;

  bool disposed = false;

  @override
  Future<void> get finished => _finished.future;

  @override
  void cancel() => fail(StoreFailureKind.cancelled);

  void finish() => _finished.complete();

  void fail(StoreFailureKind kind) {
    if (_finished.isCompleted) return;
    _finished.completeError(StoreFailure(kind: kind, message: kind.name));
  }

  @override
  void dispose() => disposed = true;
}

class _FakeWriter implements ArchiveWriter {
  final writes = <(int, DateTime)>[];
  _FakeWrite? current;

  @override
  ArchiveWrite write(int fd, {required DateTime exportedAt}) {
    writes.add((fd, exportedAt));
    return current = _FakeWrite();
  }
}

void main() {
  final now = DateTime(2026, 11, 24, 19, 40);
  late InMemoryStore store;
  late FakeAppLockPlatform lock;
  late _FakeExportPlatform platform;
  late _FakeWriter writer;
  late Book garden;

  setUp(() async {
    store = InMemoryStore(clock: () => now);
    lock = FakeAppLockPlatform();
    platform = _FakeExportPlatform();
    writer = _FakeWriter();
    garden = await store.createBook('Kebun');
  });
  tearDown(() => store.dispose());

  Future<void> launch(
    WidgetTester tester, {
    SavedSettings saved = const SavedSettings(),
  }) async {
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          savedSettingsProvider.overrideWithValue(saved),
          inMemoryStoreProvider.overrideWithValue(store),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
          appLockPlatformProvider.overrideWithValue(lock),
          exportPlatformProvider.overrideWithValue(platform),
          archiveWriterProvider.overrideWithValue(writer),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(KronoerApp)))
        .read(routerProvider)
        .go(Routes.settings);
    await tester.pumpAndSettle();
  }

  Finder exportRow() => find.widgetWithText(ListTile, 'Ekspor');

  Future<void> showExportRow(WidgetTester tester) async {
    await tester.scrollUntilVisible(exportRow(), 100);
    await tester.pumpAndSettle();
  }

  ListTile row(WidgetTester tester) => tester.widget<ListTile>(exportRow());

  Future<void> openExport(WidgetTester tester) async {
    await showExportRow(tester);
    await tester.tap(exportRow());
    await tester.pumpAndSettle();
    expect(find.byType(ExportScreen), findsOneWidget);
    expect(find.text('Ekspor Data'), findsOneWidget);
  }

  /// Taps Pilih lokasi and lets the write start; the bar may still be
  /// moving, so this does not settle.
  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Pilih lokasi'));
    await tester.pump();
    await tester.pump();
    await tester.pump(exportProgressInterval * 2);
  }

  group('the Settings row', () {
    testWidgets('is disabled while there is no Entry outside the Trash', (
      tester,
    ) async {
      final entry = await store.createEntry(bookId: garden.id, text: 'Bibit');
      await store.trashEntries([entry.id]);
      await launch(tester);
      await showExportRow(tester);

      expect(find.text('Belum ada Entry'), findsOneWidget);
      expect(row(tester).enabled, isFalse);

      await store.createEntry(bookId: garden.id, text: 'Tunas');
      await tester.pumpAndSettle();
      expect(find.text('Belum ada Entry'), findsNothing);
      expect(find.text('Semua Book dalam satu arsip'), findsOneWidget);
      expect(row(tester).enabled, isTrue);
    });

    testWidgets('counts the Entries of Locked Books too', (tester) async {
      final hidden = await store.createBook('Rahasia');
      await store.createEntry(bookId: hidden.id, text: 'Hanya untukku');
      await store.setBooksLocked([hidden.id], locked: true);
      await launch(tester);
      await showExportRow(tester);

      expect(row(tester).enabled, isTrue);
    });

    testWidgets('says when the last Export was', (tester) async {
      await store.createEntry(bookId: garden.id, text: 'Bibit');
      await launch(
        tester,
        saved: SavedSettings(lastExport: DateTime(2026, 11, 2, 8)),
      );
      await showExportRow(tester);

      expect(find.text('Semua Book · terakhir 2 Nov 2026'), findsOneWidget);
    });
  });

  group('an Export', () {
    setUp(() async {
      await store.createEntry(bookId: garden.id, text: 'Bibit');
    });

    testWidgets('saves the Archive and says so in Settings', (tester) async {
      await launch(tester);
      await openExport(tester);
      await pick(tester);

      expect(platform.suggested, ['kronoer-2026-11-24.zip']);
      expect(writer.writes, [(42, now)]);
      expect(find.text('Mengekspor…'), findsOneWidget);
      expect(lock.prompts, isEmpty, reason: 'no Locked Book, no prompt');

      writer.current!
        ..done = 1240
        ..total = 3512;
      await tester.pump(exportProgressInterval * 2);
      expect(find.text('1.240 dari 3.512 item'), findsOneWidget);
      expect(find.text('35%'), findsOneWidget);

      writer.current!
        ..done = 3512
        ..finish();
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(
        find.text('Arsip tersimpan: kronoer-2026-11-24.zip'),
        findsOneWidget,
      );
      expect(platform.finished, ['content://downloads/kronoer']);
      expect(platform.deleted, isEmpty);
      expect(platform.screenOn, [true, false]);
      expect(writer.current!.disposed, isTrue);
      await showExportRow(tester);
      expect(find.text('Semua Book · terakhir hari ini'), findsOneWidget);
    });

    testWidgets('writes nothing when the picker is closed', (tester) async {
      platform.picked = null;
      await launch(tester);
      await openExport(tester);
      await tester.tap(find.text('Pilih lokasi'));
      await tester.pumpAndSettle();

      expect(writer.writes, isEmpty);
      expect(find.text('Ekspor Data'), findsOneWidget);
    });

    testWidgets('Batal stops it, deletes the file, and goes back', (
      tester,
    ) async {
      await launch(tester);
      await openExport(tester);
      await pick(tester);
      writer.current!
        ..done = 10
        ..total = 100;
      await tester.pump(exportProgressInterval * 2);

      // Back does not leave a running Export.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Mengekspor…'), findsOneWidget);
      expect(find.byTooltip('Tutup'), findsNothing);

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(platform.deleted, ['content://downloads/kronoer']);
      expect(platform.finished, isEmpty);
      expect(platform.screenOn, [true, false]);
      expect(find.textContaining('Arsip tersimpan'), findsNothing);
      await showExportRow(tester);
      expect(find.text('Semua Book dalam satu arsip'), findsOneWidget);
    });

    testWidgets('that fails says why, and Coba lagi starts over', (
      tester,
    ) async {
      await launch(tester);
      await openExport(tester);
      await pick(tester);
      writer.current!.fail(StoreFailureKind.storageFull);
      await tester.pumpAndSettle();

      expect(find.text('Ekspor gagal'), findsOneWidget);
      expect(
        find.text(
          'Lokasi yang dipilih tidak punya cukup ruang. '
          'File yang belum selesai sudah dihapus.',
        ),
        findsOneWidget,
      );
      expect(platform.deleted, ['content://downloads/kronoer']);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Ekspor Data'), findsOneWidget);
      expect(find.text('Pilih lokasi'), findsOneWidget);
    });
  });

  group('with a Locked Book', () {
    setUp(() async {
      final hidden = await store.createBook('Rahasia');
      await store.createEntry(bookId: hidden.id, text: 'Hanya untukku');
      await store.setBooksLocked([hidden.id], locked: true);
    });

    testWidgets('asks for the device lock before the picker', (tester) async {
      await launch(tester);
      await openExport(tester);
      await pick(tester);

      expect(lock.prompts, ['Ekspor semua Book']);
      expect(platform.suggested, hasLength(1));
      writer.current!.finish();
      await tester.pumpAndSettle();
    });

    testWidgets('a closed prompt opens no picker', (tester) async {
      lock.answer = Unlock.cancelled;
      await launch(tester);
      await openExport(tester);
      await tester.tap(find.text('Pilih lokasi'));
      await tester.pumpAndSettle();

      expect(lock.prompts, ['Ekspor semua Book']);
      expect(platform.suggested, isEmpty);
      expect(find.text('Ekspor Data'), findsOneWidget);
    });

    testWidgets('without a screen lock, says to set one', (tester) async {
      lock.screenLock = false;
      await launch(tester);
      await openExport(tester);
      await tester.tap(find.text('Pilih lokasi'));
      await tester.pumpAndSettle();

      expect(find.text('Pasang kunci layar dulu'), findsOneWidget);
      expect(lock.prompts, isEmpty);
      expect(platform.suggested, isEmpty);
    });
  });
}
