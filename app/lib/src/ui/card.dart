import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/open_ink_well.dart';
import 'package:material_ui/material_ui.dart';

class KCard extends StatelessWidget {
  const KCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    // The pressed effect covers the card's images too.
    child: OpenInkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(Space.l), child: child),
    ),
  );
}
