import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/preview.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// The Kronoer wordmark. In Kronoer Preview a mini "Preview" label follows it.
class Wordmark extends ConsumerWidget {
  const Wordmark({super.key, this.height = 34});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPreview = ref.watch(isPreviewProvider);

    final wordmark = VectorGraphic(
      loader: AssetBytesLoader(
        isDark ? 'assets/brand/wordmark_dark.vec' : 'assets/brand/wordmark.vec',
      ),
      height: height,
      semanticsLabel: isPreview ? null : 'Kronoer',
      excludeFromSemantics: isPreview,
    );
    if (!isPreview) return wordmark;

    return Semantics(
      label: previewName,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s,
        children: [
          wordmark,
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(Radii.s),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                child: Text(
                  'Preview',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
