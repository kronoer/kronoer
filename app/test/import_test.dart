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
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
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
    final row = find.widgetWithText(ListTile, 'Import');
    await tester.scrollUntilVisible(row, 100);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);
    expect(find.text('Import from an archive'), findsOneWidget);
  }

  /// Taps Choose file and lets the import start; its spinner keeps moving,
  /// so this does not settle.
  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Choose file'));
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
        'Choose an archive file exported from Kronoer. Entries that are '
        'already here are skipped, so nothing is overwritten.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('reads nothing when the picker is closed', (tester) async {
    platform.picked = null;
    await launch(tester);
    await openImport(tester);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();

    expect(platform.opened, 1);
    expect(reader.reads, isEmpty);
    expect(find.text('Import from an archive'), findsOneWidget);
  });

  testWidgets('shows its steps, and Cancel stops it and leaves nothing', (
    tester,
  ) async {
    await launch(tester);
    await openImport(tester);
    await pick(tester);

    expect(reader.reads, [42]);
    expect(platform.screenOn, [true]);
    expect(find.text('Importing…'), findsOneWidget);
    expect(find.text('kronoer-2026-11-02.zip'), findsOneWidget);
    expect(find.text('Checking the archive'), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);

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
    expect(find.text('Archive checked'), findsOneWidget);
    expect(find.text('4 Books, 177 Entries, 640 photos'), findsOneWidget);
    expect(find.text('Adding what is missing'), findsOneWidget);
    expect(find.text('2 Books and 31 Entries new'), findsOneWidget);
    expect(find.text('19 of 31 Entries'), findsOneWidget);
    expect(find.text('61%'), findsOneWidget);
    expect(
      find.text(
        'Nothing changes until the import is done. Cancel leaves nothing '
        'behind.',
      ),
      findsOneWidget,
    );

    // Back does not leave a running Import.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Importing…'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Import from an archive'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
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
        _book('My Book', existing: 120),
        _book('Liburan', inTrash: true, trashed: 5),
        _book('Rahasia', added: true, locked: true, addedEntries: 12),
        _book('Resep Keluarga', added: true, addedEntries: 19),
      ]),
    );

    expect(find.text('Import done'), findsOneWidget);
    expect(
      find.text(
        '2 Books and 31 Entries added. 120 Entries were already here, so they '
        'were skipped. Nothing was overwritten.',
      ),
      findsOneWidget,
    );
    expect(find.text('New Book'), findsOneWidget);
    expect(find.text('+19'), findsOneWidget);
    expect(find.text('Locked Books'), findsOneWidget);
    expect(find.text('Names are not shown'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('Rahasia'), findsNothing, reason: 'its name is hidden');
    expect(
      find.text('In the Trash. Restore it first, then import again.'),
      findsOneWidget,
    );
    expect(find.text('5 skipped'), findsOneWidget);
    expect(find.text('120 already here'), findsOneWidget);
    expect(find.text('+0'), findsOneWidget);
    // Added to first, then Locked Books, the Trash, and the rest.
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Resep Keluarga'), lessThan(top('Locked Books')));
    expect(top('Locked Books'), lessThan(top('Liburan')));
    expect(top('Liburan'), lessThan(top('My Book')));
    expect(platform.screenOn, [true, false]);

    await tester.tap(find.text('See the result'));
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
        _book('My Book', existing: 120),
        _book('Rahasia', locked: true, existing: 57),
      ]),
    );

    expect(find.text('All already here'), findsOneWidget);
    expect(
      find.text(
        'All 4 Books and 177 Entries in this archive are already on this '
        'phone. Nothing was added or changed.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  group('a refused archive', () {
    for (final (kind, text) in [
      (
        StoreFailureKind.archiveDamaged,
        'This file is damaged or isn\'t a Kronoer archive.',
      ),
      (
        StoreFailureKind.archiveImage,
        "A photo in this archive doesn't open, so the archive isn't complete.",
      ),
      (
        StoreFailureKind.archiveNewer,
        'This archive was made by a newer version of Kronoer. Update Kronoer, '
            'then import again.',
      ),
      (
        StoreFailureKind.failed,
        'Something went wrong while adding it. Try again.',
      ),
    ]) {
      testWidgets('says why when ${kind.name}', (tester) async {
        await launch(tester);
        await openImport(tester);
        await pick(tester);
        reader.current!.fail(kind);
        await tester.pumpAndSettle();

        expect(find.text('This archive can\'t be imported'), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(
          find.text('Nothing was added. This phone stays as it was.'),
          findsOneWidget,
        );
        expect(platform.screenOn, [true, false]);

        await tester.tap(find.text('Choose another file'));
        await tester.pump();
        await tester.pump();
        expect(platform.opened, 2);
        expect(find.text('Importing…'), findsOneWidget);
        reader.current!.fail(StoreFailureKind.cancelled);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('a picker that fails says the file is damaged', (tester) async {
      platform.error = StateError('the provider gave no file');
      await launch(tester);
      await openImport(tester);
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(reader.reads, isEmpty);
      expect(
        find.text('This file is damaged or isn\'t a Kronoer archive.'),
        findsOneWidget,
      );
    });
  });

  group('from Welcome', () {
    Future<void> openFromWelcome(WidgetTester tester) async {
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportScreen), findsOneWidget);
      expect(find.text('Import from an archive'), findsOneWidget);
    }

    bool started() => container.read(hasStartedProvider);

    testWidgets('an Import that adds Books starts the app, with no My Book', (
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
      expect(find.text('Import done'), findsOneWidget);
      expect(find.text('Kebun'), findsOneWidget);

      await tester.tap(find.text('See the result'));
      await tester.pumpAndSettle();
      expect(find.byType(BookListScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('My Book'), findsNothing);
    });

    testWidgets('closing it, Cancel, or a failure goes back to Welcome', (
      tester,
    ) async {
      await launch(tester, started: false);

      // ×, and Android's back.
      await openFromWelcome(tester);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await openFromWelcome(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Cancel.
      await openFromWelcome(tester);
      await pick(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(platform.screenOn, [true, false]);

      // A refused archive says why first.
      await openFromWelcome(tester);
      await pick(tester);
      reader.current!.fail(StoreFailureKind.archiveNewer);
      await tester.pumpAndSettle();
      expect(find.text('This archive can\'t be imported'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // An archive with nothing to add.
      await openFromWelcome(tester);
      await pick(tester);
      await finish(tester, _summary([]));
      expect(find.text('All already here'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(started(), isFalse);

      // Welcome works as before.
      await tester.tap(find.text('Let\'s start writing'));
      await tester.pumpAndSettle();
      expect(started(), isTrue);
      expect(await tester.runAsync(() => store.watchBooks().first), [
        isA<Book>().having((book) => book.name, 'name', 'My Book'),
      ]);
    });
  });
}
