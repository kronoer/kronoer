import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_repository.dart';
import 'package:kronoer/src/books/cover_processing.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// A Book's Cover, opened from the repository.
///
/// The decrypted bytes only ever live in memory. Decoded Covers stay in
/// Flutter's image cache, keyed by the Cover's ID, which is new with every
/// new Cover, so a replaced Cover is never shown from the cache.
@immutable
class BookCoverProvider extends ImageProvider<BookCoverProvider> {
  const BookCoverProvider(
    this.repository, {
    required this.bookId,
    required this.coverId,
    required this.thumbnail,
  });

  final BookRepository repository;
  final String bookId;
  final String coverId;
  final bool thumbnail;

  @override
  Future<BookCoverProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    BookCoverProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: 'BookCover($coverId${thumbnail ? ', thumbnail' : ''})',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await repository.bookCover(bookId, thumbnail: thumbnail);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (error) {
      debugPrint('The Cover of $bookId did not open: $error');
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BookCoverProvider &&
      identical(other.repository, repository) &&
      other.bookId == bookId &&
      other.coverId == coverId &&
      other.thumbnail == thumbnail;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(repository), bookId, coverId, thumbnail);
}

/// A Book's Cover filling its box: the thumbnail for small places, the full
/// image where it is seen large.
class BookCoverImage extends ConsumerWidget {
  const BookCoverImage({
    required this.bookId,
    required this.coverId,
    this.thumbnail = true,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    super.key,
  });

  final String bookId;
  final String coverId;
  final bool thumbnail;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Image(
      image: BookCoverProvider(
        ref.watch(bookRepositoryProvider),
        bookId: bookId,
        coverId: coverId,
        thumbnail: thumbnail,
      ),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null && !wasSynchronouslyLoaded
          ? const ImageLoading()
          : child,
      errorBuilder: (_, _, _) => const BrokenImage(),
    );
  }
}

/// A Book's Cover thumbnail at [width], 3:4 with corners rounded by
/// [radius]. A Book without a Cover shows a neutral tile with the Book icon
/// when [tile] is set, and nothing otherwise.
class CoverThumbnail extends StatelessWidget {
  const CoverThumbnail(
    this.book, {
    required this.width,
    required this.radius,
    this.tile = true,
    super.key,
  });

  final Book book;
  final double width;
  final double radius;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final coverId = book.coverId;
    if (coverId == null && !tile) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: width / coverAspectRatio,
          child: coverId == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Center(
                    child: KIcon(
                      KIcons.book,
                      size: width / 2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : BookCoverImage(bookId: book.id, coverId: coverId),
        ),
      ),
    );
  }
}
