import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// How long entering or leaving selection mode takes, and how a selected
/// item's tint and badge come and go.
const selectionDuration = Durations.medium2;

/// The curve of [selectionDuration].
const selectionCurve = Easing.standard;

/// The tint behind a selected row or card: the primary color over the
/// surface, as light as the active tab's indicator. Opaque, so a badge's ring
/// in it matches the row behind it.
Color selectedTint(ThemeData theme) {
  final scheme = theme.colorScheme;
  final alpha = theme.brightness == Brightness.dark ? 0.16 : 0.12;
  return Color.alphaBlend(
    scheme.primary.withValues(alpha: alpha),
    scheme.surface,
  );
}

/// The color the top bar fades to in selection mode: the search field's.
Color selectionBarColor(ThemeData theme) =>
    theme.colorScheme.surfaceContainerHigh;

/// The top bar of a screen with selection mode, [shown] of the way into it:
/// [normal] cross-fades to [selecting] as the bar fades to
/// [selectionBarColor]. While [isOn], only [selecting] can be tapped.
AppBar selectionAppBar(
  BuildContext context, {
  required double shown,
  required bool isOn,
  required Widget normal,
  required Widget selecting,
}) {
  final theme = Theme.of(context);
  final bar = theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
  return AppBar(
    backgroundColor: Color.lerp(bar, selectionBarColor(theme), shown),
    automaticallyImplyLeading: false,
    titleSpacing: 0,
    title: Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        SelectionLayer(shown: 1 - shown, active: !isOn, child: normal),
        if (shown > 0)
          SelectionLayer(shown: shown, active: isOn, child: selecting),
      ],
    ),
  );
}

/// The round check that marks a selected item, laid over a corner of its
/// Cover or card. It grows in when [selected], also when it first shows, and
/// shrinks away when not.
class SelectionBadge extends StatelessWidget {
  const SelectionBadge({required this.selected, this.ring, super.key});

  final bool selected;

  /// The color of the ring around it: what it sits on. [selectedTint] when
  /// null, as on a selected row.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: selected ? 1 : 0),
      duration: selectionDuration,
      curve: selectionCurve,
      builder: (_, shown, badge) => Opacity(
        opacity: shown,
        child: Transform.scale(scale: 0.4 + 0.6 * shown, child: badge),
      ),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          // A ring in the color behind keeps the badge apart from what it
          // covers.
          border: Border.all(
            color: ring ?? selectedTint(theme),
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        alignment: Alignment.center,
        child: KIcon(KIcons.check, size: 16, color: scheme.onPrimary),
      ),
    );
  }
}

/// One of two looks that cross-fade, such as the top bar in and out of
/// selection mode. Only the [active] one can be tapped or read out.
class SelectionLayer extends StatelessWidget implements PreferredSizeWidget {
  const SelectionLayer({
    required this.shown,
    required this.active,
    required this.child,
    super.key,
  });

  final double shown;
  final bool active;
  final Widget child;

  @override
  Size get preferredSize => switch (child) {
    final PreferredSizeWidget sized => sized.preferredSize,
    _ => Size.zero,
  };

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !active,
    child: ExcludeSemantics(
      excluding: !active,
      child: Opacity(opacity: shown, child: child),
    ),
  );
}

/// How far a screen is into selection mode, and what is selected: the IDs
/// of the selected items, in the order they were selected. Selection mode is
/// on while any are.
///
/// [mode] runs from 0, out of it, to 1, in it; once it is fully out again,
/// items drop their badges. The owner rebuilds on it and disposes it.
class Selection {
  Selection({required TickerProvider vsync, required VoidCallback onChanged})
    : _onChanged = onChanged,
      _controller = AnimationController(
        vsync: vsync,
        duration: selectionDuration,
      ) {
    _controller.addStatusListener((status) {
      if (status.isDismissed) onChanged();
    });
    mode = CurvedAnimation(
      parent: _controller,
      curve: selectionCurve,
      reverseCurve: selectionCurve.flipped,
    );
  }

  final VoidCallback _onChanged;
  final AnimationController _controller;
  late final CurvedAnimation mode;
  final _ids = <String>{};

  Set<String> get ids => _ids;
  bool get isOn => _ids.isNotEmpty;

  /// Whether items show a badge: while selection mode is on, or still fading
  /// out.
  bool get badges => isOn || !_controller.isDismissed;

  bool contains(String id) => _ids.contains(id);

  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    _follow();
  }

  void clear() {
    _ids.clear();
    _follow();
  }

  /// Keeps only the selected items still there.
  void retain(Set<String> there) {
    if (_ids.every(there.contains)) return;
    _ids.retainWhere(there.contains);
    _follow();
  }

  void _follow() {
    _onChanged();
    if (isOn) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void dispose() {
    mode.dispose();
    _controller.dispose();
  }
}
