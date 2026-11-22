import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The small filled star on the card of a Starred Entry, by its time.
class StarMark extends StatelessWidget {
  const StarMark({super.key});

  @override
  Widget build(BuildContext context) => KIcon(
    KIcons.star,
    filled: true,
    size: 12,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    semanticLabel: AppLocalizations.of(context).starredEntry,
  );
}
