import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry_providers.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The images of one Entry, full screen and always dark. Swipe between
/// them, pinch to zoom.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({
    required this.bookId,
    required this.entryId,
    required this.imageId,
    super.key,
  });

  final String bookId;
  final String entryId;

  /// The image shown first.
  final String imageId;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  PageController? _pages;
  var _index = 0;

  /// While an image is zoomed in, a swipe pans it instead of turning pages.
  var _zoomed = false;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final imageIds = ref.watch(entryProvider(widget.entryId)).value?.imageIds;

    if (imageIds != null && _pages == null) {
      _index = imageIds.indexOf(widget.imageId).clamp(0, imageIds.length);
      _pages = PageController(initialPage: _index);
    }

    return Theme(
      data: buildTheme(darkColorScheme),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: l10n.close,
            color: Colors.white,
            onPressed: () =>
                context.go(Routes.entry(widget.bookId, widget.entryId)),
            icon: const KIcon(KIcons.x),
          ),
          title: imageIds == null || imageIds.isEmpty
              ? null
              : Text(
                  l10n.imagePosition(_index + 1, imageIds.length),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: Colors.white),
                ),
        ),
        body: imageIds == null || imageIds.isEmpty
            ? const SizedBox.shrink()
            : Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      physics: _zoomed
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemCount: imageIds.length,
                      onPageChanged: (i) => setState(() {
                        _index = i;
                        _zoomed = false;
                      }),
                      itemBuilder: (_, i) => _ZoomableImage(
                        entryId: widget.entryId,
                        imageId: imageIds[i],
                        onZoomed: (zoomed) {
                          if (zoomed != _zoomed) {
                            setState(() => _zoomed = zoomed);
                          }
                        },
                      ),
                    ),
                  ),
                  _PageDots(count: imageIds.length, index: _index),
                ],
              ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.entryId,
    required this.imageId,
    required this.onZoomed,
  });

  final String entryId;
  final String imageId;
  final ValueChanged<bool> onZoomed;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transform,
      maxScale: 4,
      onInteractionEnd: (_) =>
          widget.onZoomed(_transform.value.getMaxScaleOnAxis() > 1.01),
      child: EntryImage(
        entryId: widget.entryId,
        imageId: widget.imageId,
        thumbnail: false,
        fit: BoxFit.contain,
        zoomable: true,
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(height: 72);

    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, Space.xl, 0, 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: Space.s,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: i == index ? 1 : 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
