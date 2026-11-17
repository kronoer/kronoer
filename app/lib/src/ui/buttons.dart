import 'package:material_ui/material_ui.dart';

ButtonStyle destructiveTextButton(ColorScheme scheme) =>
    TextButton.styleFrom(foregroundColor: scheme.error);

ButtonStyle destructiveMenuItem(ColorScheme scheme) => MenuItemButton.styleFrom(
  foregroundColor: scheme.error,
  iconColor: scheme.error,
);
