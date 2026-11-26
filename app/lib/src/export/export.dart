import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/export/export_platform.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/storage/storage.dart';

/// One Archive being written.
abstract interface class ArchiveWrite {
  /// The Entries and Images written so far.
  int get done;

  /// The Entries and Images the Archive holds, Covers included; 0 until the
  /// write knows.
  int get total;

  /// Stops at the next Entry or Image; [finished] then fails with
  /// [StoreFailureKind.cancelled].
  void cancel();

  /// Completes once the Archive is whole, or fails with a [StoreFailure].
  Future<void> get finished;

  /// Lets go of the write, once [finished] has completed.
  void dispose();
}

/// Writes Archives of every Book not in the Trash.
abstract interface class ArchiveWriter {
  /// Starts writing an Archive into the open file [fd], which it takes over.
  ArchiveWrite write(int fd, {required DateTime exportedAt});
}

/// The core store's: the Archive is written in Rust, off the UI's thread.
class CoreArchiveWriter implements ArchiveWriter {
  const CoreArchiveWriter(this._store);

  final CoreStore _store;

  @override
  ArchiveWrite write(int fd, {required DateTime exportedAt}) {
    final job = ExportJob();
    return _CoreArchiveWrite(
      job,
      _store.exportArchiveToFd(
        fd: fd,
        exportedAt: exportedAt.millisecondsSinceEpoch,
        job: job,
      ),
    );
  }
}

class _CoreArchiveWrite implements ArchiveWrite {
  _CoreArchiveWrite(this._job, Future<ExportSummaryItem> summary)
    : finished = summary.then((_) {});

  final ExportJob _job;

  @override
  final Future<void> finished;

  @override
  int get done => _job.done();

  @override
  int get total => _job.total();

  @override
  void cancel() => _job.cancel();

  @override
  void dispose() => _job.dispose();
}

/// Only the core's store writes Archives; `InMemoryStore` does not.
final archiveWriterProvider = Provider<ArchiveWriter>(
  (ref) => throw UnsupportedError('Export needs the core store'),
);

/// The name an Archive is suggested under: the day it is made, in this
/// device's time zone.
String archiveFileName(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'kronoer-${local.year}-${two(local.month)}-${two(local.day)}.zip';
}

/// How many Entries an Export would write: every Entry not in the Trash,
/// those in Locked Books included. Null until both lists are read.
final exportableEntryCountProvider = Provider<int?>((ref) {
  final books = ref.watch(bookSummariesProvider).value;
  final locked = ref.watch(lockedBookSummariesProvider).value;
  if (books == null || locked == null) return null;
  return [...books, ...locked].fold<int>(0, (sum, b) => sum + b.entryCount);
});

/// When an Export from this device last finished, as it started; null if
/// none has.
class LastExportNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => ref.read(savedSettingsProvider).lastExport;

  void exported(DateTime at) {
    state = at;
    savePreference(ref, (preferences) => saveLastExport(preferences, at));
  }
}

final lastExportProvider = NotifierProvider<LastExportNotifier, DateTime?>(
  LastExportNotifier.new,
);

/// Why an Export failed, for what its page says.
enum ExportFailure {
  /// The storage the user picked is full.
  storageFull,

  /// The file could not be written for another reason.
  writeFailed,

  /// Kronoer's own store could not be read.
  storeFailed,
}

/// Where an Export is.
@immutable
sealed class ExportState {
  const ExportState();
}

/// Nothing is being written: the page warns and offers the picker.
class ExportReady extends ExportState {
  const ExportReady();

  @override
  bool operator ==(Object other) => other is ExportReady;

  @override
  int get hashCode => 0;
}

/// An Archive is being written.
class ExportRunning extends ExportState {
  const ExportRunning({this.done = 0, this.total = 0});

  final int done;

  /// 0 until the Export knows.
  final int total;

  @override
  bool operator ==(Object other) =>
      other is ExportRunning && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);
}

/// The last Export failed, and its unfinished file was deleted.
class ExportFailed extends ExportState {
  const ExportFailed(this.failure);

  final ExportFailure failure;

  @override
  bool operator ==(Object other) =>
      other is ExportFailed && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;
}

/// What came of one Export.
sealed class ExportOutcome {
  const ExportOutcome();
}

/// The Archive is whole, saved under [name].
class ExportSaved extends ExportOutcome {
  const ExportSaved(this.name);

  final String name;
}

/// The picker was closed without a choice: nothing was written.
class ExportNotStarted extends ExportOutcome {
  const ExportNotStarted();
}

/// "Cancel" stopped the Export, and its file was deleted.
class ExportCancelled extends ExportOutcome {
  const ExportCancelled();
}

/// The Export failed; see [ExportFailed].
class ExportNotSaved extends ExportOutcome {
  const ExportNotSaved();
}

/// How often the progress page reads how far an Export has come.
const exportProgressInterval = Duration(milliseconds: 100);

/// Runs Exports, one at a time: the picker, then the Archive's write, with
/// its progress, "Cancel", and what happens to the file when it does not
/// finish.
///
/// It does not ask for the device's lock; the Export page does that first,
/// when there is a Locked Book.
class ExportNotifier extends Notifier<ExportState> {
  ArchiveWrite? _write;

  @override
  ExportState build() => const ExportReady();

  /// Asks where to save, then writes the Archive there. While it runs, the
  /// state is [ExportRunning].
  Future<ExportOutcome> run() async {
    if (state is ExportRunning) return const ExportNotStarted();
    final platform = ref.read(exportPlatformProvider);
    final exportedAt = ref.read(clockProvider)();

    final ArchiveTarget? target;
    try {
      target = await ref
          .read(appLockProvider.notifier)
          .ownTrip(() => platform.createArchive(archiveFileName(exportedAt)));
    } on Object catch (error) {
      debugPrint('The picker for an Archive failed: $error');
      state = const ExportFailed(ExportFailure.writeFailed);
      return const ExportNotSaved();
    }
    if (target == null) return const ExportNotStarted();

    state = const ExportRunning();
    unawaited(_quietly(platform.keepScreenOn(true)));
    final ArchiveWrite write;
    try {
      write = ref
          .read(archiveWriterProvider)
          .write(target.fd, exportedAt: exportedAt);
    } on Object catch (error) {
      debugPrint('An Archive did not start: $error');
      return _failed(platform, target, ExportFailure.storeFailed);
    }
    _write = write;
    final timer = Timer.periodic(exportProgressInterval, (_) => _report());
    try {
      await write.finished;
      _report();
      await _quietly(platform.finishArchive(target));
      ref.read(lastExportProvider.notifier).exported(exportedAt);
      state = const ExportReady();
      return ExportSaved(target.name);
    } on StoreFailure catch (failure) {
      if (failure.kind == StoreFailureKind.cancelled) {
        await _quietly(platform.deleteArchive(target));
        state = const ExportReady();
        return const ExportCancelled();
      }
      debugPrint('An Archive failed: ${failure.kind.name}: ${failure.message}');
      return _failed(platform, target, switch (failure.kind) {
        StoreFailureKind.storageFull => ExportFailure.storageFull,
        StoreFailureKind.writeFailed ||
        StoreFailureKind.unsupported => ExportFailure.writeFailed,
        _ => ExportFailure.storeFailed,
      });
    } on Object catch (error) {
      debugPrint('An Archive failed: $error');
      return _failed(platform, target, ExportFailure.storeFailed);
    } finally {
      timer.cancel();
      _write = null;
      write.dispose();
      unawaited(_quietly(platform.keepScreenOn(false)));
    }
  }

  /// "Cancel": stops the Export at the next Entry or Image.
  void cancel() => _write?.cancel();

  /// Leaves a failed Export's page: the next one starts from the warning.
  void dismissFailure() {
    if (state is ExportFailed) state = const ExportReady();
  }

  void _report() {
    final write = _write;
    if (write == null || state is! ExportRunning) return;
    final now = ExportRunning(done: write.done, total: write.total);
    if (now != state) state = now;
  }

  Future<ExportOutcome> _failed(
    ExportPlatform platform,
    ArchiveTarget target,
    ExportFailure failure,
  ) async {
    await _quietly(platform.deleteArchive(target));
    state = ExportFailed(failure);
    return const ExportNotSaved();
  }

  /// A platform call whose failure changes nothing for the user.
  static Future<void> _quietly(Future<void> call) =>
      call.catchError((Object error) {
        debugPrint('An Export platform call failed: $error');
      });
}

final exportProvider = NotifierProvider<ExportNotifier, ExportState>(
  ExportNotifier.new,
);
