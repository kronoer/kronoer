import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The file the user picked for an Archive, open for writing.
class ArchiveTarget {
  const ArchiveTarget({
    required this.uri,
    required this.name,
    required this.fd,
  });

  /// Where the file is, for deleting it or saying it is done.
  final String uri;

  /// The file's name as the user's storage shows it, which may differ from
  /// the one suggested.
  final String name;

  /// The open file, handed over to the core, which closes it.
  final int fd;
}

/// The device's side of an Export: the system's file picker, and keeping the
/// screen on while an Archive is written.
abstract interface class ExportPlatform {
  /// Asks the user where to save a new Archive, suggesting [name], and opens
  /// the file. Null when the picker is closed without a choice.
  ///
  /// Until [finishArchive] or [deleteArchive], the file counts as
  /// unfinished: should Kronoer be stopped before then, the next launch
  /// deletes it.
  Future<ArchiveTarget?> createArchive(String name);

  /// The Archive is whole: it is kept.
  Future<void> finishArchive(ArchiveTarget target);

  /// Deletes an Archive that did not finish, so no part of one is left.
  Future<void> deleteArchive(ArchiveTarget target);

  /// Keeps the screen from turning off, or lets it again.
  Future<void> keepScreenOn(bool on);
}

/// Android's, through the app's own platform channel.
class AndroidExportPlatform implements ExportPlatform {
  const AndroidExportPlatform();

  static const _channel = MethodChannel('app.kronoer/export');

  @override
  Future<ArchiveTarget?> createArchive(String name) async {
    final picked = await _channel.invokeMapMethod<String, Object?>(
      'createArchive',
      name,
    );
    if (picked == null) return null;
    return ArchiveTarget(
      uri: picked['uri']! as String,
      name: picked['name']! as String,
      fd: picked['fd']! as int,
    );
  }

  @override
  Future<void> finishArchive(ArchiveTarget target) =>
      _channel.invokeMethod<void>('finishArchive', target.uri);

  @override
  Future<void> deleteArchive(ArchiveTarget target) =>
      _channel.invokeMethod<void>('deleteArchive', target.uri);

  @override
  Future<void> keepScreenOn(bool on) =>
      _channel.invokeMethod<void>('keepScreenOn', on);
}

/// No device to ask, as in tests and the gallery: the picker is always
/// closed without a choice.
class NoExportPlatform implements ExportPlatform {
  const NoExportPlatform();

  @override
  Future<ArchiveTarget?> createArchive(String name) async => null;

  @override
  Future<void> finishArchive(ArchiveTarget target) async {}

  @override
  Future<void> deleteArchive(ArchiveTarget target) async {}

  @override
  Future<void> keepScreenOn(bool on) async {}
}

final exportPlatformProvider = Provider<ExportPlatform>(
  (ref) => const NoExportPlatform(),
);
