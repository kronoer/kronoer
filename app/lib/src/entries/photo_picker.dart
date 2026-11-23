import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/lock/app_lock.dart';

/// A photo handed over by the gallery or the camera.
abstract interface class PickedPhoto {
  Future<Uint8List> read();

  /// Deletes the file the picker or camera wrote for it.
  Future<void> discard();
}

/// Where photos come from. Both ways go through other apps (the system photo
/// picker and the camera app), so the app asks for no storage or camera
/// permission.
abstract interface class PhotoPicker {
  /// Up to [limit] photos from the gallery, in the order picked; empty when
  /// nothing is picked.
  Future<List<PickedPhoto>> gallery({required int limit});

  /// One photo from the gallery; null when none is picked.
  Future<PickedPhoto?> galleryPhoto();

  /// A photo taken with the camera app; null when none is taken.
  Future<PickedPhoto?> camera();
}

/// The device's pickers. Going to them is an own trip for App lock: the
/// time spent picking does not count as time away.
final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => _DevicePicker(ref.read(appLockProvider.notifier).ownTrip),
);

/// Turns picked bytes into an Image ready to store.
final imageProcessorProvider =
    Provider<Future<ProcessedImage> Function(Uint8List bytes)>(
      (ref) => processImage,
    );

class _DevicePicker implements PhotoPicker {
  _DevicePicker(this._trip);

  final _picker = ImagePicker();
  final Future<T> Function<T>(Future<T> Function() trip) _trip;

  @override
  Future<List<PickedPhoto>> gallery({required int limit}) async => [
    for (final file in await _trip(() => _picker.pickMultiImage(limit: limit)))
      _FilePhoto(file),
  ];

  @override
  Future<PickedPhoto?> galleryPhoto() => _pickOne(ImageSource.gallery);

  @override
  Future<PickedPhoto?> camera() => _pickOne(ImageSource.camera);

  Future<PickedPhoto?> _pickOne(ImageSource source) async {
    final file = await _trip(() => _picker.pickImage(source: source));
    return file == null ? null : _FilePhoto(file);
  }
}

/// A photo the picker copied into the app's cache.
class _FilePhoto implements PickedPhoto {
  _FilePhoto(this._file);

  final XFile _file;

  /// The picker puts each copy in a folder of its own, named by a UUID.
  static final _copyFolder = RegExp(
    r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
  );

  @override
  Future<Uint8List> read() => _file.readAsBytes();

  @override
  Future<void> discard() async {
    final file = File(_file.path);
    try {
      await file.delete();
      final folder = file.parent;
      if (_copyFolder.hasMatch(
        folder.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
      )) {
        await folder.delete();
      }
    } on FileSystemException catch (error) {
      debugPrint('A picked photo was not deleted: $error');
    }
  }
}
