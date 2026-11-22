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

/// The round check that marks a selected item, laid over a corner of its
/// Cover or card. It grows in when [selected], also when it first shows, and
/// shrinks away when not.
class SelectionBadge extends StatelessWidget {
  const SelectionBadge({required this.selected, super.key});

  final bool selected;

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
          // A ring in the row's tint keeps the badge apart from the Cover.
          border: Border.all(
            color: selectedTint(theme),
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
