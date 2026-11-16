import 'package:kronoer/src/theme/system_bars.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';
import 'typography.dart';

ThemeData buildTheme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  textTheme: kronoerTextTheme,
  scaffoldBackgroundColor: scheme.surface,

  appBarTheme: AppBarTheme(
    backgroundColor: scheme.surface,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    toolbarHeight: 64,
    systemOverlayStyle: systemBarsFor(scheme),
  ),

  cardTheme: CardThemeData(
    color: scheme.surfaceContainerLow,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.xl),
    ),
  ),

  extensions: [EntryTextStyles.of(scheme)],
);
