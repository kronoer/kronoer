import 'package:kronoer/src/theme/system_bars.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';
import 'typography.dart';

OutlineInputBorder _outline(Color color, double width) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(Radii.xs),
  borderSide: BorderSide(color: color, width: width),
);

ThemeData buildTheme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  textTheme: kronoerTextTheme,
  scaffoldBackgroundColor: scheme.surface,
  extensions: [EntryTextStyles.of(scheme)],

  actionIconTheme: ActionIconThemeData(
    backButtonIconBuilder: (_) => const KIcon(KIcons.arrowLeft),
  ),

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

  inputDecorationTheme: InputDecorationThemeData(
    border: _outline(scheme.outline, 1),
    enabledBorder: _outline(scheme.outline, 1),
    focusedBorder: _outline(scheme.primary, 2),
    errorBorder: _outline(scheme.error, 2),
    focusedErrorBorder: _outline(scheme.error, 2),
    disabledBorder: _outline(scheme.onSurface.withValues(alpha: 0.12), 1),
  ),

  dialogTheme: DialogThemeData(
    barrierColor: Colors.black.withValues(alpha: 0.4),
  ),

  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.s)),
    elevation: 3,
    insetPadding: const EdgeInsets.fromLTRB(
      Space.l,
      Space.xs,
      Space.l,
      Space.l,
    ),
  ),

  menuTheme: MenuThemeData(
    style: MenuStyle(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadiusGeometry.circular(Radii.s),
        ),
      ),
    ),
  ),

  menuButtonTheme: MenuButtonThemeData(
    style: MenuItemButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      iconSize: 20,
    ),
  ),
);
