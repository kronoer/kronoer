import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/theme/bottom_bar_style.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The three tabs, Book, Linimasa, and Pengaturan, behind a bottom
/// navigation. Each tab keeps its own screen and scroll position.
///
/// Back from Linimasa or Pengaturan goes to the Book tab; back from the Book
/// tab leaves the app. Tapping the active tab scrolls it to the top.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.shell, required this.tabs});

  final StatefulNavigationShell shell;

  /// One navigator per tab, in the order of the bottom navigation.
  final List<Widget> tabs;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final _reselected = [for (final _ in widget.tabs) _Reselected()];

  @override
  void dispose() {
    for (final notifier in _reselected) {
      notifier.dispose();
    }
    super.dispose();
  }

  void _select(int index) {
    if (index == widget.shell.currentIndex) {
      _reselected[index].fire();
    } else {
      widget.shell.goBranch(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.shell.currentIndex;

    return PopScope(
      canPop: current == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.shell.goBranch(0);
      },
      child: Scaffold(
        body: Stack(
          children: [
            for (final (i, tab) in widget.tabs.indexed)
              Offstage(
                offstage: i != current,
                child: TickerMode(
                  enabled: i == current,
                  // Heroes on hidden tabs must not fly to the next screen.
                  child: HeroMode(
                    enabled: i == current,
                    child: _TabReselect(notifier: _reselected[i], child: tab),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _NavigationBar(
          selected: current,
          onSelect: _select,
        ),
      ),
    );
  }
}

class _Reselected extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Hands a tab's screens the notifier that fires when the tab is tapped
/// again. Screens listen to it rather than depend on it: nothing rebuilds.
class _TabReselect extends InheritedWidget {
  const _TabReselect({required this.notifier, required super.child});

  final _Reselected notifier;

  @override
  bool updateShouldNotify(_TabReselect oldWidget) =>
      notifier != oldWidget.notifier;
}

/// Scrolls the tab's main list, the [PrimaryScrollController] of its screen,
/// to the top when its tab is tapped while it is open.
class ScrollToTopOnReselect extends StatefulWidget {
  const ScrollToTopOnReselect({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollToTopOnReselect> createState() => _ScrollToTopOnReselectState();
}

class _ScrollToTopOnReselectState extends State<ScrollToTopOnReselect> {
  _Reselected? _reselected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reselected = context
        .getInheritedWidgetOfExactType<_TabReselect>()
        ?.notifier;
    if (reselected == _reselected) return;
    _reselected?.removeListener(_scrollToTop);
    _reselected = reselected?..addListener(_scrollToTop);
  }

  @override
  void dispose() {
    _reselected?.removeListener(_scrollToTop);
    super.dispose();
  }

  void _scrollToTop() {
    final controller = PrimaryScrollController.maybeOf(context);
    if (controller == null || !controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NavigationBar extends StatelessWidget {
  const _NavigationBar({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final label = theme.textTheme.labelMedium!;

    NavigationDestination destination(KIcons icon, String text) =>
        NavigationDestination(
          icon: KIcon(icon, color: scheme.onSurfaceVariant),
          selectedIcon: KIcon(icon, filled: true, color: scheme.primary),
          label: text,
        );

    return DecoratedBox(
      decoration: theme.extension<BottomBarStyle>()!.decoration,
      child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: onSelect,
        height: 64,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? label.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                )
              : label.copyWith(color: scheme.onSurfaceVariant),
        ),
        destinations: [
          destination(KIcons.book, l10n.tabBooks),
          destination(KIcons.queue, l10n.timeline),
          destination(KIcons.settings, l10n.settings),
        ],
      ),
    );
  }
}
