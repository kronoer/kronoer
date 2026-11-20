import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// One of an Entry's Images, opened from the repository.
///
/// The decrypted bytes only ever live in memory. Decoded images stay in
/// Flutter's image cache, keyed by Entry, Image, and variant, so scrolling
/// back to an Image does not open its blob again.
@immutable
class EntryImageProvider extends ImageProvider<EntryImageProvider> {
  const EntryImageProvider(
    this.repository, {
    required this.entryId,
    required this.imageId,
    required this.thumbnail,
  });

  final EntryRepository repository;
  final String entryId;
  final String imageId;
  final bool thumbnail;

  @override
  Future<EntryImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    EntryImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: 'EntryImage($imageId${thumbnail ? ', thumbnail' : ''})',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await repository.image(
        entryId,
        imageId,
        thumbnail: thumbnail,
      );
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (error) {
      debugPrint('Image $imageId did not open: $error');
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is EntryImageProvider &&
      identical(other.repository, repository) &&
      other.entryId == entryId &&
      other.imageId == imageId &&
      other.thumbnail == thumbnail;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(repository), entryId, imageId, thumbnail);
}

/// One of an Entry's Images, filling its box: the thumbnail for small
/// places, the full image where it is seen large.
class EntryImage extends ConsumerWidget {
  const EntryImage({
    required this.entryId,
    required this.imageId,
    this.thumbnail = true,
    this.fit = BoxFit.cover,
    this.zoomable = false,
    super.key,
  });

  final String entryId;
  final String imageId;
  final bool thumbnail;
  final BoxFit fit;

  /// Decodes every pixel, for a view that zooms in.
  final bool zoomable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = EntryImageProvider(
      ref.watch(entryRepositoryProvider),
      entryId: entryId,
      imageId: imageId,
      thumbnail: thumbnail,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // A full image is decoded no wider than it is shown, unless it can
        // be zoomed into.
        final decodeWidth =
            !thumbnail && !zoomable && constraints.hasBoundedWidth
            ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .ceil()
            : null;
        return Image(
          image: ResizeImage.resizeIfNeeded(decodeWidth, null, provider),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              frame == null && !wasSynchronouslyLoaded
              ? const ImageLoading()
              : child,
          errorBuilder: (_, _, _) => const BrokenImage(),
        );
      },
    );
  }
}

/// Where an Image will be once it is ready.
class ImageLoading extends StatelessWidget {
  const ImageLoading({this.busy = false, super.key});

  /// Shows that work is going on, for an Image still being prepared.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: busy
          ? Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.onSurfaceVariant,
                  semanticsLabel: AppLocalizations.of(context).imagePreparing,
                ),
              ),
            )
          : null,
    );
  }
}

/// Stands in for an Image that cannot be opened.
class BrokenImage extends StatelessWidget {
  const BrokenImage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: KIcon(
          KIcons.imageOff,
          color: scheme.onSurfaceVariant,
          semanticLabel: AppLocalizations.of(context).imageUnreadable,
        ),
      ),
    );
  }
}
