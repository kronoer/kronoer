import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:material_ui/material_ui.dart';

/// How long Kronoer may be in the background before App lock asks again.
enum LockAgain {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5));

  const LockAgain(this.after);

  final Duration after;
}

/// App lock as set in Settings: on this device only, never in an export or
/// synced.
@immutable
class AppLockSettings {
  const AppLockSettings({
    this.on = false,
    this.lockAgain = LockAgain.oneMinute,
    this.suggested = false,
  });

  final bool on;
  final LockAgain lockAgain;

  /// Whether the Book list's App lock card is done with: closed with "Not now",
  /// or App lock was turned on. It is not shown again.
  final bool suggested;

  @override
  bool operator ==(Object other) =>
      other is AppLockSettings &&
      other.on == on &&
      other.lockAgain == lockAgain &&
      other.suggested == suggested;

  @override
  int get hashCode => Object.hash(on, lockAgain, suggested);
}

/// App lock's settings and what it is doing now.
@immutable
class AppLockState {
  const AppLockState({
    this.on = false,
    this.lockAgain = LockAgain.oneMinute,
    this.locked = false,
    this.screenLockSet = true,
    this.blocksScreenshots = false,
    this.turnedOff = false,
    this.suggested = false,
    this.deviceRead = false,
    this.lockedBooksOpen = false,
  });

  final bool on;
  final LockAgain lockAgain;

  /// Whether the lock screen covers the app.
  final bool locked;

  /// Whether the device has a screen lock; without one App lock cannot
  /// turn on.
  final bool screenLockSet;

  /// Whether hiding Kronoer from Recents also blocks screenshots on this
  /// device (before Android 13).
  final bool blocksScreenshots;

  /// Whether App lock just turned itself off because the device's screen
  /// lock was removed, and the user has not been told yet.
  final bool turnedOff;

  /// See [AppLockSettings.suggested].
  final bool suggested;

  /// Whether [screenLockSet] and [blocksScreenshots] have been read from a
  /// real device; until then, or without one, they are guesses.
  final bool deviceRead;

  /// Whether the Locked Books area is open: the user gave the device's lock
  /// for it, from the Book list's link or the Trash's row, and has not left
  /// it, nor gone to the background, since. It does not depend on App lock
  /// being on.
  final bool lockedBooksOpen;

  /// Whether Kronoer's content is kept out of Recents: while App lock is on,
  /// and while the Locked Books area is open.
  bool get hidesRecents => on || lockedBooksOpen;

  /// Whether the Book list may suggest App lock: it is off, the device can
  /// use it, and the user has not already answered.
  bool get canSuggest => deviceRead && screenLockSet && !on && !suggested;

  AppLockState copyWith({
    bool? on,
    LockAgain? lockAgain,
    bool? locked,
    bool? screenLockSet,
    bool? blocksScreenshots,
    bool? turnedOff,
    bool? suggested,
    bool? deviceRead,
    bool? lockedBooksOpen,
  }) => AppLockState(
    on: on ?? this.on,
    lockAgain: lockAgain ?? this.lockAgain,
    locked: locked ?? this.locked,
    screenLockSet: screenLockSet ?? this.screenLockSet,
    blocksScreenshots: blocksScreenshots ?? this.blocksScreenshots,
    turnedOff: turnedOff ?? this.turnedOff,
    suggested: suggested ?? this.suggested,
    deviceRead: deviceRead ?? this.deviceRead,
    lockedBooksOpen: lockedBooksOpen ?? this.lockedBooksOpen,
  );

  @override
  bool operator ==(Object other) =>
      other is AppLockState &&
      other.on == on &&
      other.lockAgain == lockAgain &&
      other.locked == locked &&
      other.screenLockSet == screenLockSet &&
      other.blocksScreenshots == blocksScreenshots &&
      other.turnedOff == turnedOff &&
      other.suggested == suggested &&
      other.deviceRead == deviceRead &&
      other.lockedBooksOpen == lockedBooksOpen;

  @override
  int get hashCode => Object.hash(
    on,
    lockAgain,
    locked,
    screenLockSet,
    blocksScreenshots,
    turnedOff,
    suggested,
    deviceRead,
    lockedBooksOpen,
  );
}

/// How long after asking for an own trip the app may go to the background
/// and still count it as one.
const _tripWindow = Duration(seconds: 5);

/// App lock: asks for the device's own lock before Kronoer shows anything,
/// on launch and after [AppLockSettings.lockAgain] in the background.
///
/// It is never used for encryption: the store opens the same whether the
/// app is locked or not. Going to the background for something Kronoer
/// started itself, such as the photo picker or the prompt, is not time
/// away: wrap those in [ownTrip], or call [expectOwnTrip] before one that
/// is not awaited.
class AppLockNotifier extends Notifier<AppLockState> {
  /// When Kronoer went to the background, if the clock is running.
  DateTime? _awaySince;
  Timer? _lockTimer;

  /// Own trips running now.
  var _trips = 0;
  DateTime? _tripExpected;

  /// Whether Kronoer is in the background on an own trip.
  var _awayOnTrip = false;

  /// Whether the lock screen should ask by itself the next time Kronoer is
  /// in front: after a launch or time away, not after a prompt closes.
  var _promptDue = false;

  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  AppLockState build() {
    final saved = ref.read(savedSettingsProvider).appLock;
    final lifecycle = AppLifecycleListener(onHide: _hidden, onShow: _shown);
    ref.onDispose(() {
      lifecycle.dispose();
      _lockTimer?.cancel();
    });
    _promptDue = saved.on;
    // The app just opened.
    Future.microtask(_checkDevice);
    return AppLockState(
      on: saved.on,
      lockAgain: saved.lockAgain,
      locked: saved.on,
      suggested: saved.suggested,
    );
  }

  /// Turns App lock on after the device's lock is given. Returns whether it
  /// is on.
  Future<bool> turnOn({required String title}) async {
    if (state.on) return true;
    final unlock = await ownTrip(() => _platform.authenticate(title: title));
    if (!ref.mounted) return false;
    switch (unlock) {
      case Unlock.unlocked:
        _setOn(true);
        return true;
      case Unlock.noScreenLock:
        state = state.copyWith(screenLockSet: false);
        return false;
      case Unlock.cancelled || Unlock.failed:
        return false;
    }
  }

  /// Turns App lock off after the device's lock is given. Returns whether it
  /// is off.
  Future<bool> turnOff({required String title}) async {
    if (!state.on) return true;
    final unlock = await ownTrip(() => _platform.authenticate(title: title));
    if (!ref.mounted) return false;
    switch (unlock) {
      case Unlock.unlocked || Unlock.noScreenLock:
        _setOn(false);
        return true;
      case Unlock.cancelled || Unlock.failed:
        return false;
    }
  }

  void setLockAgain(LockAgain lockAgain) {
    state = state.copyWith(lockAgain: lockAgain);
    _save();
  }

  /// Asks for the device's lock, and takes the lock screen away when it is
  /// given.
  Future<void> unlock({required String title}) async {
    _promptDue = false;
    if (!state.locked) return;
    final unlock = await ownTrip(() => _platform.authenticate(title: title));
    if (!ref.mounted) return;
    switch (unlock) {
      case Unlock.unlocked:
        state = state.copyWith(locked: false);
      case Unlock.noScreenLock:
        _turnedOffByDevice();
      case Unlock.cancelled || Unlock.failed:
        break;
    }
  }

  /// Asks for the device's lock for something other than App lock, such as
  /// locking a Book. Without a screen lock on the device, it says so in
  /// [AppLockState.screenLockSet].
  Future<Unlock> confirm({required String title}) async {
    final unlock = await ownTrip(() => _platform.authenticate(title: title));
    if (ref.mounted && unlock == Unlock.noScreenLock) {
      state = state.copyWith(screenLockSet: false);
    }
    return unlock;
  }

  /// Opens the Locked Books area after the device's lock is given, whether
  /// App lock is on or not. Lock again does not apply to it: it locks again
  /// when the user leaves it ([closeLockedBooks]) or Kronoer goes to the
  /// background.
  Future<Unlock> openLockedBooks({required String title}) async {
    final unlock = await confirm(title: title);
    if (ref.mounted && unlock == Unlock.unlocked) {
      state = state.copyWith(lockedBooksOpen: true);
      _applyRecents();
    }
    return unlock;
  }

  /// Locks the Locked Books area again: the user left it.
  void closeLockedBooks() {
    if (!state.lockedBooksOpen) return;
    state = state.copyWith(lockedBooksOpen: false);
    _applyRecents();
  }

  /// Whether the lock screen should ask by itself now; asking once uses it
  /// up.
  bool takePromptDue() {
    final due = _promptDue && state.locked;
    _promptDue = false;
    return due;
  }

  /// "Not now" on the Book list's card: it is not shown again.
  void dismissSuggestion() {
    if (state.suggested) return;
    state = state.copyWith(suggested: true);
    _save();
  }

  /// The user has been told App lock turned itself off.
  void noticeShown() => state = state.copyWith(turnedOff: false);

  /// Runs [trip], something Kronoer starts that takes it to the background
  /// for a while, such as the photo picker or the prompt. Time away on it
  /// does not count.
  Future<T> ownTrip<T>(Future<T> Function() trip) async {
    _trips++;
    try {
      return await trip();
    } finally {
      _trips--;
    }
  }

  /// Kronoer is about to open something that takes it to the background and
  /// is not awaited, such as the device's settings: that time away does not
  /// count.
  void expectOwnTrip() => _tripExpected = _now();

  bool get _onTrip {
    if (_trips > 0) return true;
    final expected = _tripExpected;
    return expected != null && _now().difference(expected) < _tripWindow;
  }

  void _hidden() {
    _lockTimer?.cancel();
    if (_onTrip) {
      _awayOnTrip = true;
      return;
    }
    // Recents stay hidden until Kronoer is back: what Recents shows is the
    // screen going away now.
    if (state.lockedBooksOpen) state = state.copyWith(lockedBooksOpen: false);
    if (!state.on) return;
    _awaySince = _now();
    final after = state.lockAgain.after;
    if (after == Duration.zero) {
      _lock();
    } else {
      // Locks while away, so the app comes back already covered. If the
      // device holds Kronoer's timers back, the check on return does it.
      _lockTimer = Timer(after, _lock);
    }
  }

  void _shown() {
    _lockTimer?.cancel();
    final since = _awaySince;
    _awaySince = null;
    if (_awayOnTrip) {
      _awayOnTrip = false;
      _tripExpected = null;
    } else {
      if (state.on && since != null) {
        final away = _now().difference(since);
        // A clock turned back counts as away too.
        if (away.isNegative || away >= state.lockAgain.after) _lock();
      }
      if (state.locked) _promptDue = true;
    }
    unawaited(_checkDevice());
  }

  void _lock() {
    if (!ref.mounted || !state.on) return;
    _promptDue = true;
    if (!state.locked) state = state.copyWith(locked: true);
  }

  /// Reads whether the device has a screen lock. App lock on without one
  /// turns itself off: nothing could unlock it.
  Future<void> _checkDevice() async {
    try {
      final set = await _platform.screenLockSet();
      final blocks = await _platform.blocksScreenshots();
      if (!ref.mounted) return;
      state = state.copyWith(
        screenLockSet: set,
        blocksScreenshots: blocks,
        deviceRead: _platform.real,
      );
      if (state.on && !set) {
        _turnedOffByDevice();
      } else {
        await _platform.hideRecents(state.hidesRecents);
      }
    } on Object catch (error) {
      debugPrint('App lock could not read the device: $error');
    }
  }

  void _turnedOffByDevice() {
    state = state.copyWith(screenLockSet: false, turnedOff: true);
    _setOn(false);
  }

  void _setOn(bool on) {
    // Once on, by the card or in Settings, the card has done its job.
    state = state.copyWith(
      on: on,
      locked: false,
      suggested: on || state.suggested,
    );
    _save();
    _applyRecents();
  }

  void _applyRecents() => unawaited(
    _platform.hideRecents(state.hidesRecents).catchError((Object error) {
      debugPrint('Recents could not be changed: $error');
    }),
  );

  void _save() {
    final settings = AppLockSettings(
      on: state.on,
      lockAgain: state.lockAgain,
      suggested: state.suggested,
    );
    savePreference(ref, (preferences) => saveAppLock(preferences, settings));
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(
  AppLockNotifier.new,
);
