import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// A Book insight in one card: how many Entries, words, and photos the Book
/// holds, side by side, each a large number over its label. Numbers are
/// written in full, with the locale's thousands separator. It has no title
/// and cannot be tapped.
class BookInsightCard extends StatelessWidget {
  const BookInsightCard(this.insight, {super.key});

  final BookInsight insight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = NumberFormat.decimalPattern(l10n.localeName);
    final counts = [
      (insight.entryCount, l10n.insightEntries),
      (insight.wordCount, l10n.insightWords),
      (insight.imageCount, l10n.insightPhotos),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.all(Radius.circular(Radii.l)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Space.l,
            horizontal: Space.s,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (count, label)) in counts.indexed) ...[
                  if (i > 0)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: Space.xs,
                      endIndent: Space.xs,
                      color: scheme.outlineVariant,
                    ),
                  Expanded(
                    // The number and its label are read as one.
                    child: MergeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 2,
                          children: [
                            // A long number shrinks rather than wraps.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                number.format(count),
                                maxLines: 1,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              label(count),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
