import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/entries/image_processing.dart';

/// A Cover's width over its height: portrait 3:4 everywhere it shows.
const coverAspectRatio = 3 / 4;

/// The widest a stored Cover is, in pixels; it is then 2048 tall, and its
/// thumbnail 384×512.
const coverWidth = 1536;

/// The longest side a photo is decoded at for framing, which bounds the
/// memory a huge photo takes while keeping more pixels than a Cover stores.
const coverPhotoMaxSide = 4096;

/// Decodes a picked photo upright, for framing it as a Cover.
final coverPhotoDecoderProvider =
    Provider<Future<ui.Image> Function(Uint8List bytes)>(
      (ref) =>
          (bytes) => decodePhoto(bytes, maxSide: coverPhotoMaxSide),
    );

/// Turns the framed part of a photo into the Cover to store.
final coverProcessorProvider =
    Provider<Future<ProcessedImage> Function(ui.Image photo, Rect frame)>(
      (ref) => processCover,
    );

/// Cuts [frame], a 3:4 part of [photo] in its pixels, and encodes it as a
/// Cover: at most [coverWidth] wide and never scaled up, re-encoded from the
/// pixels so no metadata survives.
Future<ProcessedImage> processCover(ui.Image photo, Rect frame) async {
  final scale = min(1.0, coverWidth / frame.width);
  final width = max(1, (frame.width * scale).round());
  final height = max(1, (width / coverAspectRatio).round());

  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    photo,
    frame,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final framed = await picture.toImage(width, height);
  picture.dispose();
  try {
    return await encodeImage(framed);
  } finally {
    framed.dispose();
  }
}
