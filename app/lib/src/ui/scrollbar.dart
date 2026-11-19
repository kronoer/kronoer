import 'package:flutter/scheduler.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// A scrollbar thumb for long lists that can be dragged, and shows [label]
/// beside it while it is dragged.
///
/// [child] is the scroll view that [controller] is attached to.
class LabeledScrollbar extends StatefulWidget {
  const LabeledScrollbar({
    super.key,
    required this.controller,
    required this.label,
    required this.child,
  });

  final ScrollController controller;

  /// Where the list is now, such as the month at its top. Read only while
  /// the thumb is dragged, after each frame.
  final String? Function() label;

  final Widget child;

  @override
  State<LabeledScrollbar> createState() => _LabeledScrollbarState();
}

class _LabeledScrollbarState extends State<LabeledScrollbar> {
  static const _thumbLength = 56.0;
  static const _thumbThickness = 4.0;
  static const _labelHeight = 32.0;

  var _dragging = false;

  /// Thumb position while dragging, from 0 (top) to 1 (bottom). The scroll
  /// extent of a lazy list changes as it builds, so the thumb follows the
  /// finger, not the extent.
  var _dragFraction = 0.0;
  String? _label;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(LabeledScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  ScrollPosition? get _position =>
      widget.controller.hasClients ? widget.controller.position : null;

  void _start(double fraction) => setState(() {
    _dragging = true;
    _dragFraction = fraction;
    _label = widget.label();
  });

  void _drag(double by) {
    final position = _position;
    if (position == null) return;

    _dragFraction = (_dragFraction + by).clamp(0.0, 1.0);
    position.jumpTo(_dragFraction * position.maxScrollExtent);

    // The list lays out at its new offset in the next frame; read the label
    // after that.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dragging) return;
      final label = widget.label();
      if (label != _label) setState(() => _label = label);
    });
  }

  void _end() => setState(() => _dragging = false);

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      // The list grew or shrank without scrolling.
      onNotification: (_) {
        _rebuild();
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [widget.child, ..._thumb(context, constraints.maxHeight)],
        ),
      ),
    );
  }

  List<Widget> _thumb(BuildContext context, double height) {
    final position = _position;
    if (position == null ||
        !position.hasContentDimensions ||
        position.maxScrollExtent <= 0) {
      return const [];
    }

    final travel = height - 2 * Space.m - _thumbLength;
    if (travel <= 0) return const [];

    final fraction = _dragging
        ? _dragFraction
        : (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    final top = Space.m + fraction * travel;
    final scheme = Theme.of(context).colorScheme;
    final label = _label;

    // Screen readers scroll the list itself.
    return [
      Positioned(
        top: top,
        right: 0,
        width: Space.touch,
        height: _thumbLength,
        child: ExcludeSemantics(
          child: GestureDetector(
            key: const ValueKey('scrollbarThumb'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => _start(fraction),
            onVerticalDragUpdate: (details) => _drag(details.delta.dy / travel),
            onVerticalDragEnd: (_) => _end(),
            onVerticalDragCancel: _end,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(right: Space.xs),
                width: _thumbThickness,
                height: _thumbLength,
                decoration: BoxDecoration(
                  color: scheme.outline,
                  borderRadius: BorderRadius.circular(_thumbThickness / 2),
                ),
              ),
            ),
          ),
        ),
      ),
      if (_dragging && label != null)
        Positioned(
          top: top + (_thumbLength - _labelHeight) / 2,
          right: Space.l,
          height: _labelHeight,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.inverseSurface,
                borderRadius: BorderRadius.circular(_labelHeight / 2),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onInverseSurface),
              ),
            ),
          ),
        ),
    ];
  }
}
