import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/settings/about_screen.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// Covers the whole app with the lock screen while App lock is locked.
///
/// The app stays built underneath, so whatever screen was open, a draft
/// included, is there again after unlocking; it is not painted, reachable
/// by touch or a screen reader, or popped by the back button meanwhile.
/// Also tells the user once when App lock turned itself off.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Added before the router's own, so back reaches this first.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back on the lock screen does nothing, rather than popping the screens
  /// underneath.
  @override
  Future<bool> didPopRoute() async => ref.read(appLockProvider).locked;

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((lock) => lock.locked));

    ref.listen(appLockProvider.select((lock) => lock.locked), (_, locked) {
      // The keyboard goes; the field keeps its text.
      if (locked) FocusManager.instance.primaryFocus?.unfocus();
    });
    ref.listen(appLockProvider.select((lock) => lock.turnedOff), (_, told) {
      if (told) unawaited(_showTurnedOff());
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !locked,
          child: Offstage(offstage: locked, child: widget.child),
        ),
        if (locked) const LockScreen(),
      ],
    );
  }

  Future<void> _showTurnedOff() async {
    final notifier = ref.read(appLockProvider.notifier);
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    notifier.noticeShown();
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => const _TurnedOffDialog(),
    );
    if (openSettings == true && mounted) {
      ref.read(routerProvider).go(Routes.settings);
    }
  }
}

/// "App lock turned off": the device's screen lock was removed.
class _TurnedOffDialog extends StatelessWidget {
  const _TurnedOffDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.appLockTurnedOffTitle),
      content: Text(l10n.appLockTurnedOffMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.settings),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}

/// "Kronoer is locked": the app icon, a line on how to unlock, and "Unlock".
/// It asks by itself when it first shows and when Kronoer comes back from
/// the background; after the prompt is closed, it waits for the button.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _askIfDue);
    // The prompt needs Kronoer in front; on a launch it may not be yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) _askIfDue();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _askIfDue() {
    if (!mounted) return;
    if (ref.read(appLockProvider.notifier).takePromptDue()) _ask();
  }

  void _ask() {
    final title = AppLocalizations.of(context).unlockPrompt;
    unawaited(ref.read(appLockProvider.notifier).unlock(title: title));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 40),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(),
                        const SizedBox(height: Space.xl),
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.lockedTitle,
                            style: theme.textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: Space.l),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Text(
                            l10n.lockedMessage,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: _ask,
                icon: const KIcon(KIcons.fingerprintPattern, size: 20),
                label: Text(l10n.unlock),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
