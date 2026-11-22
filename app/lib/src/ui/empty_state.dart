import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// Space left below an empty state, which puts it half as far above the
/// middle of the space it fills.
const emptyStateLift = 120.0;

/// A message centered a little above the middle of the space it fills, which
/// must be bounded in height. Without a [message], the title stands alone.
/// Over it are Kronoer's rings, or [icon] in their place.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon});

  final String title;
  final String? message;
  final KIcons? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        // The space below lifts it 60dp above the middle, like the design and
        // the search empty states. It scrolls when it does not fit.
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          0,
          Space.xl,
          emptyStateLift,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.m,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: ExcludeSemantics(
                child: icon != null
                    ? KIcon(icon!, size: 56, color: scheme.onSurfaceVariant)
                    : VectorGraphic(
                        loader: AssetBytesLoader(
                          isDark
                              ? 'assets/brand/rings_dark.vec'
                              : 'assets/brand/rings.vec',
                        ),
                        width: 120,
                        height: 120,
                      ),
              ),
            ),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            if (message case final message?)
              Text(
                message,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
