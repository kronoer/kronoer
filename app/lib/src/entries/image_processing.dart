import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The longest side of a stored full image, in pixels.
const fullImageSize = 2048;

/// The longest side of a stored thumbnail, in pixels.
const thumbnailSize = 512;

const _fullQuality = 85;
const _thumbnailQuality = 80;

/// One Image ready to store: two JPEGs that carry nothing but pixels.
@immutable
class ProcessedImage {
  const ProcessedImage({required this.full, required this.thumbnail});

  final Uint8List full;
  final Uint8List thumbnail;
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
/// The platform's decoder reads it, so any format the device reads works,
/// and turns it upright by its EXIF orientation. Only the pixels go on: they
/// are scaled down (never up) and encoded again as JPEG, so no metadata
/// (EXIF with its location, XMP, IPTC) survives. Decoding runs on the
/// engine's own threads and encoding in a separate isolate, never on the UI
/// thread.
Future<ProcessedImage> processImage(Uint8List bytes) async {
  final ui.Image image;
  try {
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      getTargetSize: (width, height) {
        final longest = max(width, height);
        if (longest <= fullImageSize) return const ui.TargetImageSize();
        final scale = fullImageSize / longest;
        return ui.TargetImageSize(
          width: max(1, (width * scale).round()),
          height: max(1, (height * scale).round()),
        );
      },
    );
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  } on Object catch (error) {
    throw UnreadableImage(error);
  }

  try {
    final pixels = await image.toByteData();
    if (pixels == null) throw const UnreadableImage('No pixels');
    final width = image.width;
    final height = image.height;
    return await Isolate.run(() => _encode(pixels, width, height));
  } finally {
    image.dispose();
  }
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
