import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/theme/bottom_bar_style.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The three tabs, Books, Timeline, and Settings, behind a bottom
/// navigation. Each tab keeps its own screen and scroll position.
///
/// Back from Timeline or Settings goes to the Book tab; back from the Book
/// tab leaves the app, unless its screen handles back itself
/// ([HandleBackOnTab]). Tapping the active tab scrolls it to the top.
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
  late final _backs = [
    for (final _ in widget.tabs) _BackClaim()..addListener(_backChanged),
  ];

  @override
  void dispose() {
    for (final notifier in _reselected) {
      notifier.dispose();
    }
    for (final back in _backs) {
      back.dispose();
    }
    super.dispose();
  }

  // PopScope tells the system whether the app handles back itself, so it
  // must know at once when a tab's screen starts or stops handling it.
  void _backChanged() => setState(() {});

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
    final onBack = _backs[current].onBack;

    return PopScope(
      canPop: current == 0 && onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (onBack != null) {
          onBack();
        } else {
          widget.shell.goBranch(0);
        }
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
                    child: _TabReselect(
                      notifier: _reselected[i],
                      back: _backs[i],
                      child: tab,
                    ),
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

/// What a tab's screen does on back instead of the shell, if anything.
class _BackClaim extends ChangeNotifier {
  VoidCallback? onBack;
  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Called after a frame, by when the shell may be gone.
  void claim(VoidCallback? onBack) {
    if (_disposed) return;
    if ((onBack == null) == (this.onBack == null)) {
      this.onBack = onBack;
      return;
    }
    this.onBack = onBack;
    notifyListeners();
  }
}

/// Hands a tab's screens the notifier that fires when the tab is tapped
/// again, and the claim on back. Screens listen to them rather than depend on
/// them: nothing rebuilds.
class _TabReselect extends InheritedWidget {
  const _TabReselect({
    required this.notifier,
    required this.back,
    required super.child,
  });

  final _Reselected notifier;
  final _BackClaim back;

  @override
  bool updateShouldNotify(_TabReselect oldWidget) =>
      notifier != oldWidget.notifier || back != oldWidget.back;
}

/// While [onBack] is set, back on this tab calls it instead of going to the
/// Book tab or leaving the app, as the Book list does while Books are
/// selected.
///
/// A [PopScope] inside a tab is not enough: the shell's own one tells Android
/// whether the app handles back at all, so without this the system would
/// close the app without asking it.
class HandleBackOnTab extends StatefulWidget {
  const HandleBackOnTab({super.key, required this.onBack, required this.child});

  final VoidCallback? onBack;
  final Widget child;

  @override
  State<HandleBackOnTab> createState() => _HandleBackOnTabState();
}

class _HandleBackOnTabState extends State<HandleBackOnTab> {
  _BackClaim? _back;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final back = context.getInheritedWidgetOfExactType<_TabReselect>()?.back;
    if (back == _back) return;
    _back?.claim(null);
    _back = back;
    _claim();
  }

  @override
  void didUpdateWidget(HandleBackOnTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _claim();
  }

  @override
  void dispose() {
    final back = _back;
    WidgetsBinding.instance.addPostFrameCallback((_) => back?.claim(null));
    super.dispose();
  }

  /// Hands the shell [HandleBackOnTab.onBack] after this frame: the shell
  /// rebuilds when it changes, and it cannot during this build.
  void _claim() {
    final onBack = widget.onBack;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _back?.claim(onBack);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Scrolls the tab's main list, the [PrimaryScrollController] of its screen,
/// to the top when its tab is tapped while it is open, or does [onReselect]
/// instead.
class ScrollToTopOnReselect extends StatefulWidget {
  const ScrollToTopOnReselect({
    super.key,
    required this.child,
    this.onReselect,
  });

  final Widget child;

  /// What a tap on the open tab does, in place of scrolling to the top.
  final VoidCallback? onReselect;

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
    final onReselect = widget.onReselect;
    if (onReselect != null) return onReselect();
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
          destination(KIcons.timeline, l10n.timeline),
          destination(KIcons.settings, l10n.settings),
        ],
      ),
    );
  }
}
