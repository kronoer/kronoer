import 'package:kronoer/src/entries/image_placeholder.dart';
import 'package:material_ui/material_ui.dart';

/// One image, full screen. Placeholder until the read view story.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({required this.imageId, super.key});

  final String imageId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ImagePlaceholder(imageId),
        ),
      ),
    );
  }
}
