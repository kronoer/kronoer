import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/open_ink_well.dart';
import 'package:material_ui/material_ui.dart';

class KCard extends StatelessWidget {
  const KCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.opens = true,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether [onTap] opens another screen; see [OpenInkWell.opens].
  final bool opens;

  /// The card's color; the theme's when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    clipBehavior: Clip.antiAlias,
    // The pressed effect covers the card's images too.
    child: OpenInkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      opens: opens,
      child: Padding(padding: const EdgeInsets.all(Space.l), child: child),
    ),
  );
}
