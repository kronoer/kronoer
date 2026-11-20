import 'package:material_ui/material_ui.dart';

/// The look of a bar pinned to the bottom of a screen, such as the editor's
/// bar: the screen's own background with a thin, faint line on top, so the
/// bar blends into the screen. The bottom navigation uses it too.
@immutable
class BottomBarStyle extends ThemeExtension<BottomBarStyle> {
  const BottomBarStyle({required this.background, required this.border});

  factory BottomBarStyle.of(ColorScheme scheme) => BottomBarStyle(
    background: scheme.surface,
    border: BorderSide(
      color: scheme.onSurface.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.08 : 0.07,
      ),
    ),
  );

  final Color background;

  /// The 1dp line along the top edge.
  final BorderSide border;

  BoxDecoration get decoration => BoxDecoration(
    color: background,
    border: Border(top: border),
  );

  @override
  BottomBarStyle copyWith({Color? background, BorderSide? border}) =>
      BottomBarStyle(
        background: background ?? this.background,
        border: border ?? this.border,
      );

  @override
  BottomBarStyle lerp(BottomBarStyle? other, double t) {
    if (other == null) return this;
    return BottomBarStyle(
      background: Color.lerp(background, other.background, t)!,
      border: BorderSide.lerp(border, other.border, t),
    );
  }
}
