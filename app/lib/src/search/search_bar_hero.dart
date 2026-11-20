import 'dart:ui' show lerpDouble;

import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// Marks the search bar while it moves between the Book list and search.
const searchBarInFlightKey = ValueKey('search-bar-in-flight');

/// Holds the search bar on the Book list and the field of the search across
/// all Books. Both are the same 52dp pill, so opening search only moves the
/// bar up into place, its search icon turning into the back arrow; back
/// moves it down again.
class SearchBarHero extends StatelessWidget {
  const SearchBarHero({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(
    tag: SearchBarHero,
    flightShuttleBuilder: (flightContext, animation, _, _, _) =>
        AnimatedBuilder(
          animation: animation,
          // The search route's animation, both ways: 0 is the Book list's
          // bar, 1 is the search field.
          builder: (context, _) => _BarInFlight(open: animation.value),
        ),
    child: child,
  );
}

/// The bar between its two looks, filling the box the Hero gives it.
class _BarInFlight extends StatelessWidget {
  const _BarInFlight({required this.open}) : super(key: searchBarInFlightKey);

  final double open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final t = open.clamp(0.0, 1.0);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // The search icon (22dp, 20 in) becomes the back arrow (24dp, 16
          // in); the hint stays 12 after it.
          SizedBox(width: lerpDouble(20, 16, t)),
          SizedBox(
            width: lerpDouble(22, 24, t),
            height: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 1 - t,
                  child: KIcon(KIcons.search, size: 22, color: muted),
                ),
                Opacity(
                  opacity: t,
                  child: KIcon(
                    KIcons.arrowLeft,
                    size: 24,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              AppLocalizations.of(context).searchAllBooks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The search across all Books comes in by fading through: the Book list
/// fades out, then search fades in, while its bar moves up on its own.
Widget fadeThrough(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final background = Theme.of(context).scaffoldBackgroundColor;
  return Stack(
    fit: StackFit.expand,
    children: [
      FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.35, curve: Curves.easeOut),
        ),
        child: ColoredBox(color: background),
      ),
      FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0.35, 1, curve: Curves.easeIn),
        ),
        child: child,
      ),
    ],
  );
}
