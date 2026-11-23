import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What came of asking for the device's lock.
enum Unlock {
  /// The user proved it is them.
  unlocked,

  /// The user closed the prompt.
  cancelled,

  /// The device has no screen lock, so nothing can be asked for.
  noScreenLock,

  /// The prompt did not come up, or ended in an error of its own.
  failed,
}

/// The device's side of App lock: its own lock, and keeping Kronoer out of
/// Recents. Kronoer has no PIN or code of its own.
abstract interface class AppLockPlatform {
  /// Whether the device has a PIN, pattern, or password.
  Future<bool> screenLockSet();

  /// Whether hiding Kronoer from Recents also blocks screenshots, as it
  /// does before Android 13.
  Future<bool> blocksScreenshots();

  /// Keeps Kronoer's content out of Recents, or lets it show again.
  Future<void> hideRecents(bool hide);

  /// Asks for the device's lock through the system prompt titled [title].
  Future<Unlock> authenticate({required String title});

  /// Opens the device's security settings, where a screen lock is set.
  Future<void> openSecuritySettings();
}

/// Android's, through the app's own platform channel.
class AndroidAppLockPlatform implements AppLockPlatform {
  const AndroidAppLockPlatform();

  static const _channel = MethodChannel('app.kronoer/app_lock');

  @override
  Future<bool> screenLockSet() async =>
      await _channel.invokeMethod<bool>('screenLockSet') ?? false;

  @override
  Future<bool> blocksScreenshots() async =>
      await _channel.invokeMethod<bool>('blocksScreenshots') ?? false;

  @override
  Future<void> hideRecents(bool hide) =>
      _channel.invokeMethod<void>('hideRecents', hide);

  @override
  Future<Unlock> authenticate({required String title}) async {
    final outcome = await _channel.invokeMethod<String>('authenticate', {
      'title': title,
    });
    return Unlock.values.asNameMap()[outcome] ?? Unlock.failed;
  }

  @override
  Future<void> openSecuritySettings() =>
      _channel.invokeMethod<void>('openSecuritySettings');
}

/// No device to ask, as in tests and the gallery: a screen lock is set, and
/// every prompt unlocks.
class NoAppLockPlatform implements AppLockPlatform {
  const NoAppLockPlatform();

  @override
  Future<bool> screenLockSet() async => true;

  @override
  Future<bool> blocksScreenshots() async => false;

  @override
  Future<void> hideRecents(bool hide) async {}

  @override
  Future<Unlock> authenticate({required String title}) async => Unlock.unlocked;

  @override
  Future<void> openSecuritySettings() async {}
}

final appLockPlatformProvider = Provider<AppLockPlatform>(
  (ref) => const NoAppLockPlatform(),
);
