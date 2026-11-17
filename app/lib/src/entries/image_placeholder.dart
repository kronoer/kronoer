import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder(this.imageId, {super.key});

  final String imageId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surfaceContainerHighest,
    ];

    return ColoredBox(
      color: colors[imageId.hashCode % colors.length],
      child: Center(child: KIcon(KIcons.image, color: scheme.onSurfaceVariant)),
    );
  }
}
