import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

enum BannerTone { suggestion, neutral }

class KBanner extends StatelessWidget {
  const KBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.dismissLabel,
    required this.onDismiss,
    required this.actionLabel,
    required this.onAction,
    this.tone = BannerTone.neutral,
  });

  final KIcons icon;
  final String title;
  final String message;
  final String dismissLabel;
  final VoidCallback onDismiss;
  final String actionLabel;
  final VoidCallback onAction;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isSuggestion = tone == BannerTone.suggestion;
    final foreground = isSuggestion
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Material(
      color: isSuggestion
          ? scheme.primaryContainer
          : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.m,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.m,
              children: [
                KIcon(icon, color: isSuggestion ? foreground : scheme.primary),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs,
                    children: [
                      Text(
                        title,
                        style: text.titleMedium?.copyWith(color: foreground),
                      ),
                      Text(
                        message,
                        style: text.bodyMedium?.copyWith(
                          color: isSuggestion
                              ? foreground
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: Space.s,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: isSuggestion ? foreground : scheme.primary,
                  ),
                  child: Text(dismissLabel),
                ),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
