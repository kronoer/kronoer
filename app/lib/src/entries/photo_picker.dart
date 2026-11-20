import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kronoer/src/entries/image_processing.dart';

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

  /// A photo taken with the camera app; null when none is taken.
  Future<PickedPhoto?> camera();
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => _DevicePicker());

/// Turns picked bytes into an Image ready to store.
final imageProcessorProvider =
    Provider<Future<ProcessedImage> Function(Uint8List bytes)>(
      (ref) => processImage,
    );

class _DevicePicker implements PhotoPicker {
  final _picker = ImagePicker();

  @override
  Future<List<PickedPhoto>> gallery({required int limit}) async => [
    for (final file in await _picker.pickMultiImage(limit: limit))
      _FilePhoto(file),
  ];

  @override
  Future<PickedPhoto?> camera() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
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
