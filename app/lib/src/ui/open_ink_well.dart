import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// How long an [OpenInkWell] waits after a tap before it opens, so the tap
/// effect shows before the next screen covers it.
const openDelay = Duration(milliseconds: 150);

/// A tap target that opens another screen: a Book row, an Entry card, the
/// Book title.
///
/// Unlike a plain [InkWell], its pressed effect is painted over [child], so
/// images and Covers do not hide it. And it calls [onTap] [openDelay] after
/// the tap: in a scrolling list a quick tap only starts the effect when the
/// finger lifts, and opening right then would cover it with the page
/// transition. A second tap during that wait does nothing. With animations
/// turned off, it opens right away.
///
/// When [opens] is false, as when a tap selects rather than opens, [onTap]
/// is called right away.
class OpenInkWell extends StatefulWidget {
  const OpenInkWell({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.opens = true,
    this.customBorder,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Called right away on a long press.
  final VoidCallback? onLongPress;

  /// Whether [onTap] opens another screen, and so waits [openDelay].
  final bool opens;

  /// The shape of the pressed effect; a rectangle when null.
  final ShapeBorder? customBorder;

  @override
  State<OpenInkWell> createState() => _OpenInkWellState();
}

class _OpenInkWellState extends State<OpenInkWell>
    with SingleTickerProviderStateMixin {
  // A ticker rather than a timer: it runs on frames, like the effect it waits
  // for, and it stops with the screen when that is covered.
  late final Ticker _opening = createTicker((elapsed) {
    if (elapsed < openDelay) return;
    _opening.stop();
    widget.onTap?.call();
  });

  @override
  void dispose() {
    _opening.dispose();
    super.dispose();
  }

  void _handleTap() {
    final onTap = widget.onTap;
    if (onTap == null || _opening.isActive) return;
    if (!widget.opens || MediaQuery.disableAnimationsOf(context)) {
      onTap();
      return;
    }
    _opening.start();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    // A light state layer, not the theme's grey highlight: it lies over the
    // content, so the text must stay readable through it.
    final layer = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      child: _HitAllStack(
        children: [
          widget.child,
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: enabled ? _handleTap : null,
                onLongPress: widget.onLongPress,
                customBorder: widget.customBorder,
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed) ||
                      states.contains(WidgetState.focused)) {
                    return layer.withValues(alpha: 0.10);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return layer.withValues(alpha: 0.08);
                  }
                  return Colors.transparent;
                }),
                splashColor: layer.withValues(alpha: 0.10),
                excludeFromSemantics: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A [Stack] that hit-tests every child, not just the top one, so a tap on
/// the ink layer also reaches the content under it.
class _HitAllStack extends Stack {
  const _HitAllStack({super.children});

  @override
  RenderStack createRenderObject(BuildContext context) => _RenderHitAllStack(
    alignment: alignment,
    textDirection: textDirection ?? Directionality.maybeOf(context),
    fit: fit,
    clipBehavior: clipBehavior,
  );
}

class _RenderHitAllStack extends RenderStack {
  _RenderHitAllStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var hit = false;
    var child = lastChild;
    while (child != null) {
      final box = child;
      final data = box.parentData! as StackParentData;
      hit =
          result.addWithPaintOffset(
            offset: data.offset,
            position: position,
            hitTest: (result, transformed) =>
                box.hitTest(result, position: transformed),
          ) ||
          hit;
      child = data.previousSibling;
    }
    return hit;
  }
}
