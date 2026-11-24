import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/export/export.dart';
import 'package:kronoer/src/import/import.dart';
import 'package:kronoer/src/import/import_platform.dart';
import 'package:kronoer/src/import/import_screen.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings_screen.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:kronoer/src/welcome/welcome_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_app_lock_platform.dart';

/// The device's picker: it answers [picked], and counts how often it opens.
class _FakeImportPlatform implements ImportPlatform {
  ArchiveSource? picked = const ArchiveSource(
    name: 'kronoer-2026-11-02.zip',
    fd: 42,
  );
  Object? error;
  int opened = 0;
  final screenOn = <bool>[];

  @override
  Future<ArchiveSource?> openArchive() async {
    opened++;
    if (error case final error?) throw error;
    return picked;
  }

  @override
  Future<void> keepScreenOn(bool on) async => screenOn.add(on);
}

/// An archive's import that goes only as far as the test says.
class _FakeRead implements ArchiveRead {
  final _finished = Completer<ImportSummaryItem>();

  @override
  ImportProgressItem progress = importNotChecked;

  bool disposed = false;

  @override
  Future<ImportSummaryItem> get finished => _finished.future;

  @override
  void cancel() => fail(StoreFailureKind.cancelled);

  void finish(ImportSummaryItem summary) => _finished.complete(summary);

  void fail(StoreFailureKind kind) {
    if (_finished.isCompleted) return;
    _finished.completeError(StoreFailure(kind: kind, message: kind.name));
  }

  @override
  void dispose() => disposed = true;
}

class _FakeReader implements ArchiveReader {
  final reads = <int>[];
  _FakeRead? current;

  @override
  ArchiveRead read(int fd) {
    reads.add(fd);
    return current = _FakeRead();
  }
}

ImportedBookItem _book(
  String name, {
  bool added = false,
  bool locked = false,
  bool inTrash = false,
  int addedEntries = 0,
  int existing = 0,
  int trashed = 0,
}) => ImportedBookItem(
  id: name,
  name: name,
  added: added,
  locked: locked,
  inTrash: inTrash,
  addedEntryCount: addedEntries,
  existingEntryCount: existing,
  trashedEntryCount: trashed,
);

ImportSummaryItem _summary(List<ImportedBookItem> books) => ImportSummaryItem(
  bookCount: 4,
  entryCount: 177,
  imageCount: 640,
  books: books,
);

void main() {
  final now = DateTime(2026, 11, 24, 19, 40);
  late InMemoryStore store;
  late _FakeImportPlatform platform;
  late _FakeReader reader;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryStore(clock: () => now);
    platform = _FakeImportPlatform();
    reader = _FakeReader();
  });
  tearDown(() => store.dispose());

  /// Opens Settings; or Welcome, when the user has not [started].
  Future<void> launch(WidgetTester tester, {bool started = true}) async {
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          savedSettingsProvider.overrideWithValue(const SavedSettings()),
          inMemoryStoreProvider.overrideWithValue(store),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(started)),
          appLockPlatformProvider.overrideWithValue(FakeAppLockPlatform()),
          importPlatformProvider.overrideWithValue(platform),
          archiveReaderProvider.overrideWithValue(reader),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(KronoerApp)),
    );
    if (!started) {
      expect(find.byType(WelcomeScreen), findsOneWidget);
      return;
    }
    container.read(routerProvider).go(Routes.settings);
    await tester.pumpAndSettle();
  }

  Future<void> openImport(WidgetTester tester) async {
    final row = find.widgetWithText(ListTile, 'Impor');
    await tester.scrollUntilVisible(row, 100);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);
    expect(find.text('Impor dari arsip'), findsOneWidget);
  }

  /// Taps Pilih file and lets the import start; its spinner keeps moving,
  /// so this does not settle.
  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Pilih file'));
    await tester.pump();
    await tester.pump();
    await tester.pump(importProgressInterval * 2);
  }

  /// Ends the running import with [summary].
  Future<void> finish(WidgetTester tester, ImportSummaryItem summary) async {
    reader.current!.finish(summary);
    await tester.pumpAndSettle();
  }

  testWidgets('the Settings row opens the Import page', (tester) async {
    await launch(tester);
    await openImport(tester);
    expect(
      find.text(
        'Pilih file arsip hasil ekspor Kronoer. Entry yang sudah ada akan '
        'dilewati, jadi tidak ada yang ditimpa.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('reads nothing when the picker is closed', (tester) async {
    platform.picked = null;
    await launch(tester);
    await openImport(tester);
    await tester.tap(find.text('Pilih file'));
    await tester.pumpAndSettle();

    expect(platform.opened, 1);
    expect(reader.reads, isEmpty);
    expect(find.text('Impor dari arsip'), findsOneWidget);
  });

  testWidgets('shows its steps, and Batal stops it and leaves nothing', (
    tester,
  ) async {
    await launch(tester);
    await openImport(tester);
    await pick(tester);

    expect(reader.reads, [42]);
    expect(platform.screenOn, [true]);
    expect(find.text('Mengimpor…'), findsOneWidget);
    expect(find.text('kronoer-2026-11-02.zip'), findsOneWidget);
    expect(find.text('Memeriksa arsip'), findsOneWidget);
    expect(find.byTooltip('Tutup'), findsNothing);

    reader.current!.progress = const ImportProgressItem(
      checked: true,
      bookCount: 4,
      entryCount: 177,
      imageCount: 640,
      newBookCount: 2,
      newEntryCount: 31,
      done: 19,
    );
    await tester.pump(importProgressInterval * 2);
    expect(find.text('Arsip diperiksa'), findsOneWidget);
    expect(find.text('4 Book, 177 Entry, 640 foto'), findsOneWidget);
    expect(find.text('Menambahkan yang belum ada'), findsOneWidget);
    expect(find.text('2 Book dan 31 Entry baru'), findsOneWidget);
    expect(find.text('19 dari 31 Entry'), findsOneWidget);
    expect(find.text('61%'), findsOneWidget);
    expect(
      find.text(
        'Belum ada yang berubah sampai impor selesai. '
        'Batal tidak meninggalkan apa pun.',
      ),
      findsOneWidget,
    );

    // Back does not leave a running Import.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Mengimpor…'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Impor dari arsip'), findsOneWidget);
    expect(find.text('Pilih file'), findsOneWidget);
    expect(platform.screenOn, [true, false]);
    expect(reader.current!.disposed, isTrue);
  });

  testWidgets('says what it added, one row per Book', (tester) async {
    await launch(tester);
    await openImport(tester);
    await pick(tester);
    await finish(
      tester,
      _summary([
        _book('Buku Saya', existing: 120),
        _book('Liburan', inTrash: true, trashed: 5),
        _book('Rahasia', added: true, locked: true, addedEntries: 12),
        _book('Resep Keluarga', added: true, addedEntries: 19),
      ]),
    );

    expect(find.text('Impor selesai'), findsOneWidget);
    expect(
      find.text(
        '2 Book dan 31 Entry ditambahkan. 120 Entry sudah ada, jadi '
        'dilewati. Tidak ada yang ditimpa.',
      ),
      findsOneWidget,
    );
    expect(find.text('Book baru'), findsOneWidget);
    expect(find.text('+19'), findsOneWidget);
    expect(find.text('Book terkunci'), findsOneWidget);
    expect(find.text('Namanya tidak ditampilkan'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('Rahasia'), findsNothing, reason: 'its name is hidden');
    expect(
      find.text('Ada di Sampah. Pulihkan dulu, lalu impor lagi.'),
      findsOneWidget,
    );
    expect(find.text('5 dilewati'), findsOneWidget);
    expect(find.text('120 sudah ada'), findsOneWidget);
    expect(find.text('+0'), findsOneWidget);
    // Added to first, then Locked Books, the Trash, and the rest.
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Resep Keluarga'), lessThan(top('Book terkunci')));
    expect(top('Book terkunci'), lessThan(top('Liburan')));
    expect(top('Liburan'), lessThan(top('Buku Saya')));
    expect(platform.screenOn, [true, false]);

    await tester.tap(find.text('Lihat hasilnya'));
    await tester.pumpAndSettle();
    expect(find.byType(BookListScreen), findsOneWidget);
    expect(
      container.read(lastExportProvider),
      isNull,
      reason: 'an Import is not an Export',
    );
  });

  testWidgets('says when this phone had everything already', (tester) async {
    await launch(tester);
    await openImport(tester);
    await pick(tester);
    await finish(
      tester,
      _summary([
        _book('Buku Saya', existing: 120),
        _book('Rahasia', locked: true, existing: 57),
      ]),
    );

    expect(find.text('Semua sudah ada'), findsOneWidget);
    expect(
      find.text(
        'Semua 4 Book dan 177 Entry di arsip ini sudah ada di HP ini. '
        'Tidak ada yang ditambahkan atau diubah.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Selesai'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  group('a refused archive', () {
    for (final (kind, text) in [
      (
        StoreFailureKind.archiveDamaged,
        'File ini rusak atau bukan arsip Kronoer.',
      ),
      (
        StoreFailureKind.archiveImage,
        'Ada foto di arsip ini yang tidak bisa dibuka, jadi arsipnya tidak '
            'lengkap.',
      ),
      (
        StoreFailureKind.archiveNewer,
        'Arsip ini dibuat oleh Kronoer versi yang lebih baru. Perbarui '
            'Kronoer dulu, lalu impor lagi.',
      ),
      (
        StoreFailureKind.failed,
        'Ada yang gagal saat menambahkannya. Coba lagi.',
      ),
    ]) {
      testWidgets('says why when ${kind.name}', (tester) async {
        await launch(tester);
        await openImport(tester);
        await pick(tester);
        reader.current!.fail(kind);
        await tester.pumpAndSettle();

        expect(find.text('Arsip tidak bisa diimpor'), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(
          find.text(
            'Tidak ada yang ditambahkan. Isi HP ini tetap seperti sebelumnya.',
          ),
          findsOneWidget,
        );
        expect(platform.screenOn, [true, false]);

        await tester.tap(find.text('Pilih file lain'));
        await tester.pump();
        await tester.pump();
        expect(platform.opened, 2);
        expect(find.text('Mengimpor…'), findsOneWidget);
        reader.current!.fail(StoreFailureKind.cancelled);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('a picker that fails says the file is damaged', (tester) async {
      platform.error = StateError('the provider gave no file');
      await launch(tester);
      await openImport(tester);
      await tester.tap(find.text('Pilih file'));
      await tester.pumpAndSettle();

      expect(reader.reads, isEmpty);
      expect(
        find.text('File ini rusak atau bukan arsip Kronoer.'),
        findsOneWidget,
      );
    });
  });

  group('from Welcome', () {
    Future<void> openFromWelcome(WidgetTester tester) async {
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Impor'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportScreen), findsOneWidget);
      expect(find.text('Impor dari arsip'), findsOneWidget);
    }

    bool started() => container.read(hasStartedProvider);

    testWidgets('an Import that adds Books starts the app, with no Buku Saya', (
      tester,
    ) async {
      await launch(tester, started: false);
      await openFromWelcome(tester);
      await pick(tester);
      await finish(
        tester,
        _summary([
          _book('Kebun', added: true, addedEntries: 12),
          _book('Liburan', added: true, addedEntries: 19),
        ]),
      );

      expect(started(), isTrue);
      // The summary stays open until the user leaves it.
      expect(find.text('Impor selesai'), findsOneWidget);
      expect(find.text('Kebun'), findsOneWidget);

      await tester.tap(find.text('Lihat hasilnya'));
      await tester.pumpAndSettle();
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('Buku Saya'), findsNothing);
    });

    testWidgets('closing it, Batal, or a failure goes back to Welcome', (
      tester,
    ) async {
      await launch(tester, started: false);

      // ×, and Android's back.
      await openFromWelcome(tester);
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      await openFromWelcome(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Batal.
      await openFromWelcome(tester);
      await pick(tester);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(platform.screenOn, [true, false]);

      // A refused archive says why first.
      await openFromWelcome(tester);
      await pick(tester);
      reader.current!.fail(StoreFailureKind.archiveNewer);
      await tester.pumpAndSettle();
      expect(find.text('Arsip tidak bisa diimpor'), findsOneWidget);
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      // An archive with nothing to add.
      await openFromWelcome(tester);
      await pick(tester);
      await finish(tester, _summary([]));
      expect(find.text('Semua sudah ada'), findsOneWidget);
      await tester.tap(find.text('Selesai'));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(started(), isFalse);

      // Welcome works as before.
      await tester.tap(find.text('Yuk, mulai cerita'));
      await tester.pumpAndSettle();
      expect(started(), isTrue);
      expect(await tester.runAsync(() => store.watchBooks().first), [
        isA<Book>().having((book) => book.name, 'name', 'Buku Saya'),
      ]);
    });
  });
}
