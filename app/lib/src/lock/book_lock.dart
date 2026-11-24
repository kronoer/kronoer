import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/lock/app_lock_platform.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:material_ui/material_ui.dart';

/// Locks or unlocks Books after the device's own lock is given, as in Book
/// info and the Book list's selection mode. Returns whether it was done.
///
/// On a phone without a screen lock nothing can be asked for, so it says so
/// instead, with a way to Android's security settings. A lock is not
/// encryption: the Books' Entries are sealed the same either way.
Future<bool> setBooksLockedWithPrompt(
  BuildContext context,
  WidgetRef ref,
  Iterable<String> ids, {
  required bool locked,
}) async {
  final l10n = AppLocalizations.of(context);
  final notifier = ref.read(appLockProvider.notifier);
  if (!ref.read(appLockProvider).screenLockSet) {
    await showNoScreenLockDialog(context, ref);
    return false;
  }
  final unlock = await notifier.confirm(
    title: locked ? l10n.lockBookPrompt : l10n.unlockBookPrompt,
  );
  if (!context.mounted) return false;
  switch (unlock) {
    case Unlock.unlocked:
      await ref
          .read(bookRepositoryProvider)
          .setBooksLocked(ids, locked: locked);
      return true;
    case Unlock.noScreenLock:
      await showNoScreenLockDialog(context, ref);
      return false;
    case Unlock.cancelled || Unlock.failed:
      return false;
  }
}

/// Opens the Book terkunci page after the device's own lock is given, from
/// the Book list's link. On a phone without a screen lock, as after an
/// Import or on a second phone, it says so instead: nothing is unlocked, and
/// nothing is lost.
Future<void> openLockedBooks(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  if (!ref.read(appLockProvider).screenLockSet) {
    await showNoScreenLockDialog(context, ref);
    return;
  }
  final notifier = ref.read(appLockProvider.notifier);
  final unlock = await notifier.openLockedBooks(
    title: l10n.openLockedBooksPrompt,
  );
  if (!context.mounted) {
    notifier.closeLockedBooks();
    return;
  }
  switch (unlock) {
    case Unlock.unlocked:
      context.go(Routes.lockedBooks);
    case Unlock.noScreenLock:
      await showNoScreenLockDialog(context, ref);
    case Unlock.cancelled || Unlock.failed:
      break;
  }
}

/// "Pasang kunci layar dulu": a Book cannot be locked, unlocked, or opened
/// on a phone without a screen lock. Buka pengaturan opens Android's
/// security settings.
Future<void> showNoScreenLockDialog(BuildContext context, WidgetRef ref) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.noScreenLockTitle),
        content: Text(l10n.noScreenLockMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.openDeviceSettings),
          ),
        ],
      );
    },
  );
  if (open == true) openSecuritySettings(ref);
}

/// Opens Android's security settings, where a screen lock is set; the time
/// away does not count for App lock.
void openSecuritySettings(WidgetRef ref) {
  ref.read(appLockProvider.notifier).expectOwnTrip();
  unawaited(ref.read(appLockPlatformProvider).openSecuritySettings());
}
