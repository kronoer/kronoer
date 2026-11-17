import 'package:kronoer/src/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.m,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: ExcludeSemantics(
                child: VectorGraphic(
                  loader: AssetBytesLoader(
                    isDark
                        ? 'assets/brand/rings_dark.svg'
                        : 'assets/brand/rings.svg',
                  ),
                  width: 120,
                  height: 120,
                ),
              ),
            ),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
