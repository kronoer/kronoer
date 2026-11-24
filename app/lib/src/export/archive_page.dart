import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The style of the one button at the bottom of an [ArchivePage].
ButtonStyle archiveButtonStyle(BuildContext context) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56)),
  textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleMedium),
);

/// The pages of an Export or an Import: an icon in a circle, a title, what to
/// know, what is under way or what came of it, and one button at the bottom.
class ArchivePage extends StatelessWidget {
  const ArchivePage({
    super.key,
    required this.icon,
    required this.title,
    required this.button,
    this.text,
    this.content,
    this.note,
    this.error = false,
  });

  final KIcons icon;
  final String title;
  final String? text;

  /// What goes under [text]: a progress bar, steps, or a list.
  final Widget? content;
  final String? note;
  final Widget button;

  /// Whether the icon is in the error colors.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.xxl + Space.l,
              Space.xl,
              Space.l,
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: error
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                  ),
                  child: Center(
                    child: KIcon(
                      icon,
                      size: 36,
                      color: error
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: Space.xl),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (text case final text?) ...[
                  const SizedBox(height: Space.l),
                  Text(text, style: muted, textAlign: TextAlign.center),
                ],
                if (content case final content?) ...[
                  const SizedBox(height: Space.xl),
                  content,
                ],
                if (note case final note?) ...[
                  const SizedBox(height: Space.xl),
                  Text(
                    note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.l,
            Space.l,
            Space.l,
            Space.xl,
          ),
          child: button,
        ),
      ],
    );
  }
}

/// A progress bar with how far it has come under it, and the percent. With
/// no [fraction] yet, the bar only moves.
class ArchiveProgress extends StatelessWidget {
  const ArchiveProgress({
    super.key,
    required this.fraction,
    required this.count,
    required this.percent,
    required this.semanticsLabel,
  });

  final double? fraction;

  /// How many of how many, or empty.
  final String count;

  /// The percent as text, shown only with a [fraction].
  final String percent;

  /// What the bar is of, for screen readers.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: fraction,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          semanticsLabel: semanticsLabel,
        ),
        const SizedBox(height: Space.s),
        Row(
          children: [
            Expanded(child: Text(count, style: small)),
            // The bar reads out its percent already.
            if (fraction != null)
              ExcludeSemantics(child: Text(percent, style: small)),
          ],
        ),
      ],
    );
  }
}
