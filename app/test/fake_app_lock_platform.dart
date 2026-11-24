import 'dart:async';

import 'package:kronoer/src/lock/app_lock_platform.dart';

/// The device as App lock sees it. Each prompt answers [answer], or waits
/// for [holding] when that is set.
class FakeAppLockPlatform implements AppLockPlatform {
  @override
  bool get real => true;

  bool screenLock = true;
  bool blocks = false;
  bool? recentsHidden;
  Unlock answer = Unlock.unlocked;
  Completer<Unlock>? holding;
  final prompts = <String>[];
  int securityOpened = 0;

  @override
  Future<bool> screenLockSet() async => screenLock;

  @override
  Future<bool> blocksScreenshots() async => blocks;

  @override
  Future<void> hideRecents(bool hide) async => recentsHidden = hide;

  @override
  Future<Unlock> authenticate({required String title}) {
    prompts.add(title);
    return holding?.future ?? Future.value(answer);
  }

  @override
  Future<void> openSecuritySettings() async => securityOpened++;
}
