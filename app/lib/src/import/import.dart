import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/import/import_platform.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/rust/api/store.dart';

/// One archive being imported.
abstract interface class ArchiveRead {
  /// How far it has come.
  ImportProgressItem get progress;

  /// Stops it at the next Entry or Image, changing nothing; [finished] then
  /// fails with [StoreFailureKind.cancelled].
  void cancel();

  /// Completes with what was added, all at once, or fails with a
  /// [StoreFailure], having added nothing.
  Future<ImportSummaryItem> get finished;

  /// Lets go of the read, once [finished] has completed.
  void dispose();
}

/// Imports archives into the store.
abstract interface class ArchiveReader {
  /// Starts importing the archive in the open file [fd], which it takes over.
  ArchiveRead read(int fd);
}

/// The core store's: the archive is checked and added in Rust, off the UI's
/// thread.
class CoreArchiveReader implements ArchiveReader {
  const CoreArchiveReader(this._store);

  final CoreStore _store;

  @override
  ArchiveRead read(int fd) {
    final job = ImportJob();
    return _CoreArchiveRead(job, _store.importArchiveFromFd(fd: fd, job: job));
  }
}

class _CoreArchiveRead implements ArchiveRead {
  _CoreArchiveRead(this._job, this.finished);

  final ImportJob _job;

  @override
  final Future<ImportSummaryItem> finished;

  @override
  ImportProgressItem get progress => _job.progress();

  @override
  void cancel() => _job.cancel();

  @override
  void dispose() => _job.dispose();
}

/// Only the core's store imports archives; `InMemoryStore` does not.
final archiveReaderProvider = Provider<ArchiveReader>(
  (ref) => throw UnsupportedError('Import needs the core store'),
);

/// How far an Import is before its archive is checked.
const importNotChecked = ImportProgressItem(
  checked: false,
  bookCount: 0,
  entryCount: 0,
  imageCount: 0,
  newBookCount: 0,
  newEntryCount: 0,
  done: 0,
);

/// The totals of an Import, over its Books.
extension ImportTotals on ImportSummaryItem {
  /// How many Books it added.
  int get addedBookCount => books.where((book) => book.added).length;

  /// How many Entries it added.
  int get addedEntryCount =>
      books.fold(0, (sum, book) => sum + book.addedEntryCount);

  /// How many Entries this device already had.
  int get existingEntryCount =>
      books.fold(0, (sum, book) => sum + book.existingEntryCount);

  /// How many new Entries were skipped because their Book is in the Trash.
  int get trashedEntryCount =>
      books.fold(0, (sum, book) => sum + book.trashedEntryCount);

  /// Whether this device had everything in the archive: nothing was added,
  /// and nothing waits for a Book to come out of the Trash.
  bool get hadAll =>
      addedBookCount == 0 && addedEntryCount == 0 && trashedEntryCount == 0;
}

/// Why an Import added nothing, for what its page says.
enum ImportFailure {
  /// The file is not a whole Kronoer archive, or could not be read.
  damaged,

  /// The archive was made by a newer version of Kronoer.
  newer,

  /// A photo in the archive does not open, or is too large.
  image,

  /// Kronoer's own store failed.
  storeFailed,
}

/// Where an Import is.
@immutable
sealed class ImportState {
  const ImportState();
}

/// Nothing is being imported: the page offers the picker.
class ImportReady extends ImportState {
  const ImportReady();

  @override
  bool operator ==(Object other) => other is ImportReady;

  @override
  int get hashCode => 0;
}

/// The archive [name] is being checked, then added.
class ImportRunning extends ImportState {
  const ImportRunning(this.name, [this.progress = importNotChecked]);

  final String name;
  final ImportProgressItem progress;

  @override
  bool operator ==(Object other) =>
      other is ImportRunning &&
      other.name == name &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(name, progress);
}

/// The last Import added nothing, for this reason.
class ImportFailed extends ImportState {
  const ImportFailed(this.failure);

  final ImportFailure failure;

  @override
  bool operator ==(Object other) =>
      other is ImportFailed && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;
}

/// The last Import is done, with what it added.
class ImportFinished extends ImportState {
  const ImportFinished(this.summary);

  final ImportSummaryItem summary;

  @override
  bool operator ==(Object other) =>
      other is ImportFinished && other.summary == summary;

  @override
  int get hashCode => summary.hashCode;
}

/// How often the progress page reads how far an Import has come.
const importProgressInterval = Duration(milliseconds: 100);

/// Runs Imports, one at a time: the picker, then the archive's check and
/// what is added, with its progress and Batal.
///
/// It does not ask for the device's lock: the archive can be read without
/// Kronoer anyway.
class ImportNotifier extends Notifier<ImportState> {
  ArchiveRead? _read;

  @override
  ImportState build() => const ImportReady();

  /// Asks for an archive, then imports it. While it runs, the state is
  /// [ImportRunning]; then [ImportFinished] or [ImportFailed], or
  /// [ImportReady] again when the picker is closed or Batal stops it.
  Future<void> run() async {
    if (state is ImportRunning) return;
    final platform = ref.read(importPlatformProvider);

    final ArchiveSource? source;
    try {
      source = await ref
          .read(appLockProvider.notifier)
          .ownTrip(platform.openArchive);
    } on Object catch (error) {
      debugPrint('The picker for an archive failed: $error');
      state = const ImportFailed(ImportFailure.damaged);
      return;
    }
    if (source == null) return;

    state = ImportRunning(source.name);
    unawaited(_quietly(platform.keepScreenOn(true)));
    final ArchiveRead read;
    try {
      read = ref.read(archiveReaderProvider).read(source.fd);
    } on Object catch (error) {
      debugPrint('An Import did not start: $error');
      state = const ImportFailed(ImportFailure.storeFailed);
      unawaited(_quietly(platform.keepScreenOn(false)));
      return;
    }
    _read = read;
    final timer = Timer.periodic(importProgressInterval, (_) => _report());
    try {
      final summary = await read.finished;
      state = ImportFinished(summary);
    } on StoreFailure catch (failure) {
      if (failure.kind == StoreFailureKind.cancelled) {
        state = const ImportReady();
        return;
      }
      debugPrint('An Import failed: ${failure.kind.name}: ${failure.message}');
      state = ImportFailed(switch (failure.kind) {
        StoreFailureKind.archiveDamaged => ImportFailure.damaged,
        StoreFailureKind.archiveNewer => ImportFailure.newer,
        StoreFailureKind.archiveImage => ImportFailure.image,
        _ => ImportFailure.storeFailed,
      });
    } on Object catch (error) {
      debugPrint('An Import failed: $error');
      state = const ImportFailed(ImportFailure.storeFailed);
    } finally {
      timer.cancel();
      _read = null;
      read.dispose();
      unawaited(_quietly(platform.keepScreenOn(false)));
    }
  }

  /// Batal: stops the Import at the next Entry or Image, adding nothing.
  void cancel() => _read?.cancel();

  /// Leaves a finished or failed Import's page: the next one starts from
  /// the picker.
  void dismiss() {
    if (state is ImportFailed || state is ImportFinished) {
      state = const ImportReady();
    }
  }

  void _report() {
    final read = _read;
    final current = state;
    if (read == null || current is! ImportRunning) return;
    final now = ImportRunning(current.name, read.progress);
    if (now != state) state = now;
  }

  /// A platform call whose failure changes nothing for the user.
  static Future<void> _quietly(Future<void> call) =>
      call.catchError((Object error) {
        debugPrint('An Import platform call failed: $error');
      });
}

final importProvider = NotifierProvider<ImportNotifier, ImportState>(
  ImportNotifier.new,
);
