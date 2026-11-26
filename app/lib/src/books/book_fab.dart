import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// Marks the FAB while it flies between the Book list and a Book.
@visibleForTesting
const fabInFlightKey = ValueKey('fab-in-flight');

/// Holds the FAB of the Book list ("New Book") or of a Book (the pen), so
/// going between them the one FAB changes in place: it narrows or widens,
/// the plus and the pen cross-fade, and the label fades in only once there
/// is room for it.
///
/// [child] must be a [FloatingActionButton] with `heroTag: null`, so it
/// builds no Hero of its own.
class BookFab extends StatelessWidget {
  const BookFab({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(
    tag: BookFab,
    flightShuttleBuilder: (flightContext, animation, _, _, _) =>
        AnimatedBuilder(
          animation: animation,
          // The animation is the Book's route's, both ways: 0 is the Book
          // list's FAB, 1 is the Book's.
          builder: (context, _) => _FabInFlight(wide: 1 - animation.value),
        ),
    child: child,
  );
}

/// The FAB between its two looks, filling the box the Hero gives it.
/// [wide] is 1 for the Book list's extended FAB, 0 for the Book's round one.
class _FabInFlight extends StatelessWidget {
  const _FabInFlight({required this.wide}) : super(key: fabInFlightKey);

  final double wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;

    // Same as the FAB's Material 3 defaults, which both ends use.
    return Material(
      color: theme.colorScheme.primaryContainer,
      elevation: 6,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      // The label is never drawn outside the FAB.
      clipBehavior: Clip.antiAlias,
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: 0,
        maxWidth: double.infinity,
        child: Padding(
          // Where the icon sits in both FABs: 16 from the start.
          padding: const EdgeInsetsDirectional.only(start: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 24,
                child: Stack(
                  children: [
                    Opacity(
                      opacity: 1 - wide,
                      child: KIcon(KIcons.pen, size: 24, color: color),
                    ),
                    Opacity(
                      opacity: wide,
                      child: KIcon(KIcons.plus, size: 24, color: color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: const Interval(0.6, 1).transform(wide.clamp(0, 1)),
                child: Text(
                  AppLocalizations.of(context).newBook,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
