import 'package:material_ui/material_ui.dart';

TextStyle _ui(double size, double line, int weight) => TextStyle(
  fontFamily: 'PlusJakartaSans',
  fontSize: size,
  height: line / size,
  fontWeight: FontWeight.values[weight ~/ 100 - 1],

  // Set the axis too, so the variable font really changes weight.
  fontVariations: [FontVariation.weight(weight.toDouble())],
);

final kronoerTextTheme = TextTheme(
  headlineLarge: _ui(32, 40, 400),
  headlineSmall: _ui(24, 32, 500),
  titleLarge: _ui(22, 28, 600),
  titleMedium: _ui(16, 24, 600),
  titleSmall: _ui(14, 20, 600),
  bodyLarge: _ui(16, 24, 400),
  bodyMedium: _ui(14, 20, 400),
  bodySmall: _ui(13, 18, 400),
  labelLarge: _ui(14, 20, 600),
  labelMedium: _ui(12, 16, 600),
  labelSmall: _ui(11, 16, 500),
);

TextStyle _entry(double size, double line, Color color) => TextStyle(
  fontFamily: 'Literata',
  fontSize: size,
  height: line / size,
  color: color,
  fontVariations: [
    const FontVariation.weight(400),
    FontVariation.opticalSize(size),
  ],
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
