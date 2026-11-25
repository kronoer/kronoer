import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/preview.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/banner.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/update/update_platform.dart';
import 'package:material_ui/material_ui.dart';

/// How often Kronoer Preview asks GitHub for a newer Preview.
const updateCheckEvery = Duration(days: 1);

/// A release's version: `major.minor.patch`, as in a tag `v0.2.0`.
@immutable
class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);

  /// `0.2.0` or `v0.2.0`; null for anything else, a pre-release such as
  /// `0.2.0-rc.1` included.
  static Version? tryParse(String text) {
    final match = RegExp(
      r'^v?(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$',
    ).firstMatch(text);
    if (match == null) return null;
    return Version(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(Version other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// The release page of [version], made here rather than taken from GitHub's
/// answer, so the banner only ever opens Kronoer's own releases.
Uri releasePage(Version version) =>
    Uri.https('github.com', '/kronoer/kronoer/releases/tag/v$version');

/// The newest published Preview in GitHub's list of [releases]: not a
/// draft, marked pre-release, and tagged with a version. Null when there is
/// none, or the list is not what GitHub sends.
Version? newestPreview(Object? releases) {
  if (releases is! List) return null;
  Version? newest;
  for (final release in releases) {
    if (release is! Map) continue;
    if (release['draft'] != false || release['prerelease'] != true) continue;
    final tag = release['tag_name'];
    final version = tag is String ? Version.tryParse(tag) : null;
    if (version != null && (newest == null || version > newest)) {
      newest = version;
    }
  }
  return newest;
}

/// Whether a check is due at [now], [lastCheck] being the last one, done or
/// failed. A clock set back makes one due too.
bool updateCheckDue(DateTime now, DateTime? lastCheck) =>
    lastCheck == null ||
    now.isBefore(lastCheck) ||
    now.difference(lastCheck) >= updateCheckEvery;

/// The check for a new Preview, as saved on this device.
@immutable
class UpdateCheck {
  const UpdateCheck({this.on = true, this.checked, this.found, this.later});

  /// "Cek versi baru" in Settings.
  final bool on;

  /// When GitHub was last asked, whether it answered or not.
  final DateTime? checked;

  /// The newest Preview GitHub listed when it last answered.
  final Version? found;

  /// The version Nanti hid the banner for.
  final Version? later;

  UpdateCheck copyWith({
    bool? on,
    DateTime? checked,
    Version? found,
    Version? later,
  }) => UpdateCheck(
    on: on ?? this.on,
    checked: checked ?? this.checked,
    found: found ?? this.found,
    later: later ?? this.later,
  );

  @override
  bool operator ==(Object other) =>
      other is UpdateCheck &&
      other.on == on &&
      other.checked == checked &&
      other.found == found &&
      other.later == later;

  @override
  int get hashCode => Object.hash(on, checked, found, later);
}

/// The Preview the banner offers, or null: the one found, while the check is
/// on, when it is newer than the [installed] one and than the one Nanti hid.
Version? updateToOffer(UpdateCheck check, {required Version? installed}) {
  final found = check.found;
  if (!check.on || found == null || installed == null) return null;
  if (!(found > installed)) return null;
  final later = check.later;
  if (later != null && !(found > later)) return null;
  return found;
}

/// Kronoer Preview's check for a newer Preview: once a day at most, when the
/// app opens or comes back, one request to GitHub's list of releases. A
/// failed request shows nothing and waits for the next day. The stable app
/// never checks; it has no internet permission.
class UpdateCheckNotifier extends Notifier<UpdateCheck> {
  var _checking = false;

  @override
  UpdateCheck build() {
    if (ref.read(isPreviewProvider)) {
      final lifecycle = AppLifecycleListener(
        onResume: () => unawaited(checkIfDue()),
      );
      ref.onDispose(lifecycle.dispose);
      // The app just opened.
      Future.microtask(checkIfDue);
    }
    return ref.read(savedSettingsProvider).updateCheck;
  }

  /// Asks GitHub when Kronoer is the Preview, the check is on, and a day has
  /// passed since it last asked.
  Future<void> checkIfDue() async {
    if (!ref.read(isPreviewProvider) || !state.on || _checking) return;
    final now = ref.read(clockProvider)();
    if (!updateCheckDue(now, state.checked)) return;
    _checking = true;
    _update(state.copyWith(checked: now));
    try {
      final info = await ref.read(packageInfoProvider.future);
      final releases = await ref
          .read(updatePlatformProvider)
          .fetchReleases(userAgent: 'KronoerPreview/${info.version}');
      final newest = newestPreview(releases);
      if (!ref.mounted) return;
      if (newest != null && newest != state.found) {
        _update(state.copyWith(found: newest));
      }
    } on Object catch (error) {
      debugPrint('The check for a new Preview failed: $error');
    } finally {
      _checking = false;
    }
  }

  /// "Cek versi baru": off, the banner goes too, and nothing is asked.
  void setOn(bool on) {
    _update(state.copyWith(on: on));
    if (on) unawaited(checkIfDue());
  }

  /// Nanti: hides the banner until a Preview newer than the one it offers.
  void later() {
    final found = state.found;
    if (found != null) _update(state.copyWith(later: found));
  }

  void _update(UpdateCheck check) {
    state = check;
    savePreference(ref, (preferences) => saveUpdateCheck(preferences, check));
  }
}

final updateCheckProvider = NotifierProvider<UpdateCheckNotifier, UpdateCheck>(
  UpdateCheckNotifier.new,
);

/// The Preview the Book list's banner offers now, or null.
final updateOfferProvider = Provider<Version?>((ref) {
  if (!ref.watch(isPreviewProvider)) return null;
  final info = ref.watch(packageInfoProvider).value;
  return updateToOffer(
    ref.watch(updateCheckProvider),
    installed: info == null ? null : Version.tryParse(info.version),
  );
});

/// The Book list's banner for a new Preview: Unduh opens its release page in
/// the browser, Nanti hides it until a newer one.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner(this.version, {super.key});

  final Version version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    Future<void> download() async {
      final messenger = ScaffoldMessenger.of(context);
      // The browser opens and the call returns; the time there is not away.
      ref.read(appLockProvider.notifier).expectOwnTrip();
      final opened = await ref
          .read(updatePlatformProvider)
          .openInBrowser(releasePage(version));
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.updateNoBrowser)));
      }
    }

    return KBanner(
      icon: KIcons.download,
      title: l10n.updateTitle('$previewName $version'),
      message: l10n.updateText,
      dismissLabel: l10n.updateLater,
      onDismiss: ref.read(updateCheckProvider.notifier).later,
      actionLabel: l10n.updateDownload,
      onAction: () => unawaited(download()),
    );
  }
}
