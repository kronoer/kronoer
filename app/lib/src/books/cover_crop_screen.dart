import 'dart:math';
import 'dart:ui' as ui;

import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/cover_processing.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// How far a photo can be zoomed in past filling the frame.
const _maxZoom = 5.0;

/// Frames a photo as a Cover: a fixed 3:4 frame over the photo, which the
/// user drags and pinches until the part they want is inside. Always dark,
/// like the Image viewer.
///
/// Selesai calls [onDone] with the framed part in the photo's pixels and
/// closes once it finishes; the X closes without it.
///
/// The screen owns [photo] and disposes it once it is gone, after its closing
/// transition, which still draws it.
class CoverCropScreen extends StatefulWidget {
  const CoverCropScreen({required this.photo, required this.onDone, super.key});

  final ui.Image photo;
  final Future<void> Function(Rect frame) onDone;

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  /// The photo's size over its size when it just fills the frame, at least 1.
  var _zoom = 1.0;

  /// Where the photo's top left corner is, from the frame's, in logical
  /// pixels: never inside the frame, so the photo always covers it.
  Offset? _offset;

  /// The frame's size, from the last layout.
  var _frame = Size.zero;

  var _startZoom = 1.0;
  var _startOffset = Offset.zero;
  var _startFocal = Offset.zero;
  var _saving = false;

  @override
  void dispose() {
    widget.photo.dispose();
    super.dispose();
  }

  /// The photo's size at zoom 1: as small as it can be while it covers the
  /// frame.
  Size _fillSize(Size frame) {
    final photo = widget.photo;
    final scale = max(frame.width / photo.width, frame.height / photo.height);
    return Size(photo.width * scale, photo.height * scale);
  }

  Offset _clamp(Offset offset, Size shown) => Offset(
    offset.dx.clamp(_frame.width - shown.width, 0),
    offset.dy.clamp(_frame.height - shown.height, 0),
  );

  void _onScaleStart(ScaleStartDetails details, Offset frameOrigin) {
    _startZoom = _zoom;
    _startOffset = _offset!;
    _startFocal = details.focalPoint - frameOrigin;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Offset frameOrigin) {
    final zoom = (_startZoom * details.scale).clamp(1.0, _maxZoom);
    final focal = details.focalPoint - frameOrigin;
    // The point of the photo under the fingers stays under them.
    final onPhoto = (_startFocal - _startOffset) / _startZoom;
    final shown = _fillSize(_frame) * zoom;
    setState(() {
      _zoom = zoom;
      _offset = _clamp(focal - onPhoto * zoom, shown);
    });
  }

  /// The part of the photo inside the frame, in the photo's pixels.
  Rect _framed() {
    final pixelsPerPoint =
        widget.photo.width / (_fillSize(_frame).width * _zoom);
    return Rect.fromLTWH(
      -_offset!.dx * pixelsPerPoint,
      -_offset!.dy * pixelsPerPoint,
      _frame.width * pixelsPerPoint,
      _frame.height * pixelsPerPoint,
    );
  }

  Future<void> _done() async {
    if (_saving || _offset == null) return;
    setState(() => _saving = true);
    try {
      await widget.onDone(_framed());
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Theme(
      data: buildTheme(darkColorScheme),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              leading: IconButton(
                tooltip: l10n.cancel,
                color: Colors.white,
                onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const KIcon(KIcons.x),
              ),
              actionsPadding: const EdgeInsets.only(right: Space.m),
              actions: [
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Space.l),
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else
                  TextButton(onPressed: _done, child: Text(l10n.done)),
              ],
            ),
            extendBodyBehindAppBar: true,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final area = constraints.biggest;
                final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
                // Room under the frame for the hint.
                const below = 72.0;
                final width = min(
                  area.width * 0.8,
                  (area.height - top - below - Space.xl) * coverAspectRatio,
                );
                final frame = Size(width, width / coverAspectRatio);
                final origin = Offset(
                  (area.width - frame.width) / 2,
                  top + (area.height - top - below - frame.height) / 2,
                );
                final fill = _fillSize(frame);
                if (frame != _frame) {
                  _frame = frame;
                  // Centered at first; kept covering the frame after that.
                  _offset = _offset == null
                      ? Offset(
                          (frame.width - fill.width) / 2,
                          (frame.height - fill.height) / 2,
                        )
                      : _clamp(_offset!, fill * _zoom);
                }
                final shown = fill * _zoom;
                final frameRect = origin & frame;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _saving
                      ? null
                      : (details) => _onScaleStart(details, origin),
                  onScaleUpdate: _saving
                      ? null
                      : (details) => _onScaleUpdate(details, origin),
                  child: Stack(
                    children: [
                      Positioned(
                        left: origin.dx + _offset!.dx,
                        top: origin.dy + _offset!.dy,
                        width: shown.width,
                        height: shown.height,
                        child: RawImage(
                          image: widget.photo,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      Positioned.fill(
                        child: Semantics(
                          image: true,
                          label: l10n.coverCropFrame,
                          child: CustomPaint(painter: _FramePainter(frameRect)),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: frameRect.bottom + Space.xl,
                        child: ExcludeSemantics(
                          child: Text(
                            l10n.coverCropHint,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Dims everything outside the frame, and draws the frame with a grid of
/// thirds.
class _FramePainter extends CustomPainter {
  const _FramePainter(this.frame);

  final Rect frame;

  static const _radius = Radius.circular(Radii.l);

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(frame, _radius);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rounded),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas
        ..drawLine(Offset(x, frame.top), Offset(x, frame.bottom), grid)
        ..drawLine(Offset(frame.left, y), Offset(frame.right, y), grid);
    }

    canvas.drawRRect(
      rounded.deflate(1),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.frame != frame;
}
