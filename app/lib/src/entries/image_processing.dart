import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:kronoer/src/entries/time_taken.dart';

/// The longest side of a stored full image, in pixels.
const fullImageSize = 2048;

/// The longest side of a stored thumbnail, in pixels.
const thumbnailSize = 512;

const _fullQuality = 85;
const _thumbnailQuality = 80;

/// One Image ready to store: two JPEGs that carry nothing but pixels.
@immutable
class ProcessedImage {
  const ProcessedImage({
    required this.full,
    required this.thumbnail,
    this.timeTaken,
  });

  final Uint8List full;
  final Uint8List thumbnail;

  /// The time the photo was taken, read from its EXIF, for the editor to
  /// offer as the Entry date. Only in memory: it is never stored.
  final DateTime? timeTaken;
}

/// The bytes are not an image the device can decode.
class UnreadableImage implements Exception {
  const UnreadableImage(this.cause);

  final Object cause;

  @override
  String toString() => 'UnreadableImage: $cause';
}

/// Turns a photo into the full image and thumbnail an Entry stores.
///
/// Only the pixels go on: turned upright by the EXIF orientation, scaled
/// down (never up), and encoded again as JPEG, so no metadata (EXIF with its
/// location, XMP, IPTC) survives. Nothing runs on the UI thread. The time the
/// photo was taken is read beside them, in its own isolate, and never stored.
Future<ProcessedImage> processImage(Uint8List bytes) async {
  final timeTaken = Isolate.run(() => readTimeTaken(bytes));
  final ui.Image image;
  try {
    image = await decodePhoto(bytes, maxSide: fullImageSize);
  } on Object {
    unawaited(timeTaken.then((_) {}, onError: (_) {}));
    rethrow;
  }
  try {
    final encoded = await encodeImage(image);
    return ProcessedImage(
      full: encoded.full,
      thumbnail: encoded.thumbnail,
      timeTaken: await timeTaken,
    );
  } finally {
    image.dispose();
  }
}

/// Decodes a photo upright, by its EXIF orientation, scaled down so its
/// longest side is at most [maxSide] (never up). The platform's decoder reads
/// it on the engine's own threads, so any format the device reads works.
Future<ui.Image> decodePhoto(Uint8List bytes, {required int maxSide}) async {
  try {
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      getTargetSize: (width, height) {
        final longest = max(width, height);
        if (longest <= maxSide) return const ui.TargetImageSize();
        final scale = maxSide / longest;
        return ui.TargetImageSize(
          width: max(1, (width * scale).round()),
          height: max(1, (height * scale).round()),
        );
      },
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  } on Object catch (error) {
    throw UnreadableImage(error);
  }
}

/// Encodes an image as it is, in a separate isolate, as the full image and a
/// thumbnail whose longest side is at most [thumbnailSize]. Only the pixels
/// go on, so no metadata survives.
Future<ProcessedImage> encodeImage(ui.Image image) async {
  final pixels = await image.toByteData();
  if (pixels == null) throw const UnreadableImage('No pixels');
  final width = image.width;
  final height = image.height;
  return Isolate.run(() => _encode(pixels, width, height));
}

/// Encodes premultiplied RGBA [pixels] as the full image and thumbnail.
ProcessedImage _encode(ByteData pixels, int width, int height) {
  final rgba = pixels.buffer.asUint8List(
    pixels.offsetInBytes,
    pixels.lengthInBytes,
  );
  // JPEG has no transparency: what is see-through is laid on white.
  final rgb = Uint8List(width * height * 3);
  for (var i = 0, o = 0; i < rgba.length; i += 4, o += 3) {
    final clear = 255 - rgba[i + 3];
    rgb[o] = rgba[i] + clear;
    rgb[o + 1] = rgba[i + 1] + clear;
    rgb[o + 2] = rgba[i + 2] + clear;
  }
  final full = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
  );

  final longest = max(width, height);
  final thumbnail = longest <= thumbnailSize
      ? full
      : img.copyResize(
          full,
          width: width >= height ? thumbnailSize : null,
          height: width >= height ? null : thumbnailSize,
          interpolation: img.Interpolation.average,
        );

  return ProcessedImage(
    full: img.encodeJpg(full, quality: _fullQuality),
    thumbnail: img.encodeJpg(thumbnail, quality: _thumbnailQuality),
  );
}
