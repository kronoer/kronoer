import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The archive file the user picked, open for reading.
class ArchiveSource {
  const ArchiveSource({required this.name, required this.fd});

  /// The file's name as the user's storage shows it.
  final String name;

  /// The open file, handed over to the core, which closes it.
  final int fd;
}

/// The device's side of an Import: the system's file picker, and keeping the
/// screen on while an archive is read.
abstract interface class ImportPlatform {
  /// Asks the user for an archive file and opens it. Null when the picker is
  /// closed without a choice.
  Future<ArchiveSource?> openArchive();

  /// Keeps the screen from turning off, or lets it again.
  Future<void> keepScreenOn(bool on);
}

/// Android's, through the app's own platform channel.
class AndroidImportPlatform implements ImportPlatform {
  const AndroidImportPlatform();

  static const _channel = MethodChannel('app.kronoer/import');

  @override
  Future<ArchiveSource?> openArchive() async {
    final picked = await _channel.invokeMapMethod<String, Object?>(
      'openArchive',
    );
    if (picked == null) return null;
    return ArchiveSource(
      name: picked['name']! as String,
      fd: picked['fd']! as int,
    );
  }

  @override
  Future<void> keepScreenOn(bool on) =>
      _channel.invokeMethod<void>('keepScreenOn', on);
}

/// No device to ask, as in tests and the gallery: the picker is always
/// closed without a choice.
class NoImportPlatform implements ImportPlatform {
  const NoImportPlatform();

  @override
  Future<ArchiveSource?> openArchive() async => null;

  @override
  Future<void> keepScreenOn(bool on) async {}
}

final importPlatformProvider = Provider<ImportPlatform>(
  (ref) => const NoImportPlatform(),
);
