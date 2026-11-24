import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Something the device must allow or set first, and a button to the
/// device settings where that is done.
class DeviceSettingsBox extends StatelessWidget {
  const DeviceSettingsBox({
    required this.message,
    required this.onOpen,
    super.key,
  });

  final String message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      // Lined up with the row titles.
      padding: const EdgeInsetsDirectional.fromSTEB(64, 0, Space.xl, Space.s),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          // The button's own padding lines its label up with the text.
          padding: const EdgeInsetsDirectional.fromSTEB(4, 12, Space.l, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: Text(message, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: onOpen,
                child: Text(l10n.openDeviceSettings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
