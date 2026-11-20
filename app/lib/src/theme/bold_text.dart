import 'package:material_ui/material_ui.dart';

import 'typography.dart';

/// Follows the system's Bold text setting ([MediaQuery.boldTextOf]) for
/// everything below it. Put it under the app's theme, in
/// [MaterialApp.builder].
///
/// Flutter's [Text] and [EditableText] already make their own style bold, but
/// a span inside [Text.rich] that sets its own weight keeps it, so it would
/// stay regular. Making every text style in the theme bold too covers those
/// spans, as long as they take their style from the theme. With Bold text off
/// the theme is left as it is.
class BoldTextTheme extends StatelessWidget {
  const BoldTextTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!MediaQuery.boldTextOf(context)) return child;
    return Theme(data: boldTheme(Theme.of(context)), child: child);
  }
}

/// The weight [Text] uses for Bold text.
const _bold = TextStyle(fontWeight: FontWeight.bold);

const _boldTextTheme = TextTheme(
  displayLarge: _bold,
  displayMedium: _bold,
  displaySmall: _bold,
  headlineLarge: _bold,
  headlineMedium: _bold,
  headlineSmall: _bold,
  titleLarge: _bold,
  titleMedium: _bold,
  titleSmall: _bold,
  bodyLarge: _bold,
  bodyMedium: _bold,
  bodySmall: _bold,
  labelLarge: _bold,
  labelMedium: _bold,
  labelSmall: _bold,
);

/// [theme] with every text style bold: its text themes and [EntryTextStyles].
@visibleForTesting
ThemeData boldTheme(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.merge(_boldTextTheme),
  primaryTextTheme: theme.primaryTextTheme.merge(_boldTextTheme),
  extensions: [
    for (final extension in theme.extensions.values)
      if (extension case final EntryTextStyles entry)
        entry.copyWith(
          entryBody: entry.entryBody.merge(_bold),
          entryPreview: entry.entryPreview.merge(_bold),
          entryPreviewSmall: entry.entryPreviewSmall.merge(_bold),
        )
      else
        extension,
  ],
);
