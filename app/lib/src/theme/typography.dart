import 'package:material_ui/material_ui.dart';

// All text is in the system font (Roboto on Android), like the apps people
// use every day. It has no standard semibold, so the type scale stops at 500.

TextStyle _ui(double size, double line, FontWeight weight) =>
    TextStyle(fontSize: size, height: line / size, fontWeight: weight);

final kronoerTextTheme = TextTheme(
  headlineLarge: _ui(32, 40, FontWeight.w400),
  headlineSmall: _ui(24, 32, FontWeight.w500),
  titleLarge: _ui(22, 28, FontWeight.w500),
  titleMedium: _ui(16, 24, FontWeight.w500),
  titleSmall: _ui(14, 20, FontWeight.w500),
  bodyLarge: _ui(16, 24, FontWeight.w400),
  bodyMedium: _ui(14, 20, FontWeight.w400),
  bodySmall: _ui(13, 18, FontWeight.w400),
  labelLarge: _ui(14, 20, FontWeight.w500),
  labelMedium: _ui(12, 16, FontWeight.w500),
  labelSmall: _ui(11, 16, FontWeight.w500),
);

TextStyle _entry(double size, double line, Color color) => TextStyle(
  fontSize: size,
  height: line / size,
  fontWeight: FontWeight.w400,
  color: color,
);

@immutable
class EntryTextStyles extends ThemeExtension<EntryTextStyles> {
  const EntryTextStyles({
    required this.entryBody,
    required this.entryPreview,
    required this.entryPreviewSmall,
  });

  factory EntryTextStyles.of(ColorScheme scheme) => EntryTextStyles(
    entryBody: _entry(18, 30, scheme.onSurface),
    entryPreview: _entry(16, 26, scheme.onSurface),
    entryPreviewSmall: _entry(15, 22, scheme.onSurfaceVariant),
  );

  /// Read view and editor.
  final TextStyle entryBody;

  /// Entry card inside a Book, at most 4 lines.
  final TextStyle entryPreview;

  /// Last-entry preview on the Book list, 1 line.
  final TextStyle entryPreviewSmall;

  @override
  EntryTextStyles copyWith({
    TextStyle? entryBody,
    TextStyle? entryPreview,
    TextStyle? entryPreviewSmall,
  }) => EntryTextStyles(
    entryBody: entryBody ?? this.entryBody,
    entryPreview: entryPreview ?? this.entryPreview,
    entryPreviewSmall: entryPreviewSmall ?? this.entryPreviewSmall,
  );

  @override
  EntryTextStyles lerp(EntryTextStyles? other, double t) {
    if (other == null) return this;
    return EntryTextStyles(
      entryBody: TextStyle.lerp(entryBody, other.entryBody, t)!,
      entryPreview: TextStyle.lerp(entryPreview, other.entryPreview, t)!,
      entryPreviewSmall: TextStyle.lerp(
        entryPreviewSmall,
        other.entryPreviewSmall,
        t,
      )!,
    );
  }
}
