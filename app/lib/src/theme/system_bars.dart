import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// System bar colors for one color scheme: the status bar shows the surface
/// behind it, and the navigation bar uses the surface color.
SystemUiOverlayStyle systemBarsFor(ColorScheme scheme) {
  final icons = scheme.brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;

  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: scheme.brightness, // iOS
    systemNavigationBarColor: scheme.surface,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}
