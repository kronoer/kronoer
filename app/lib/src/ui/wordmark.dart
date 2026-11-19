import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 34});

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return VectorGraphic(
      loader: AssetBytesLoader(
        isDark ? 'assets/brand/wordmark_dark.svg' : 'assets/brand/wordmark.svg',
      ),
      height: height,
      semanticsLabel: 'Kronoer',
    );
  }
}
