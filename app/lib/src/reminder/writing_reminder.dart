import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/reminder/reminder_platform.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/settings/saved_settings.dart';
import 'package:kronoer/src/settings/settings.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:material_ui/material_ui.dart';

/// The Writing reminder's time when none was picked: 20.00.
const defaultReminderTime = TimeOfDay(hour: 20, minute: 0);

/// The Writing reminder as set in Settings: on this device only, never in an
/// export or synced.
@immutable
class WritingReminder {
  const WritingReminder({
    this.on = false,
    this.time = defaultReminderTime,
    this.skipIfWritten = false,
    this.blocked = false,
  });

  final bool on;
  final TimeOfDay time;

  /// Whether a day the user already created an Entry on goes without one.
  final bool skipIfWritten;

  /// Whether the device does not let Kronoer notify: asked and denied, or
  /// turned off in the device settings while the reminder is on. Not saved.
  final bool blocked;

  WritingReminder copyWith({
    bool? on,
    TimeOfDay? time,
    bool? skipIfWritten,
    bool? blocked,
  }) => WritingReminder(
    on: on ?? this.on,
    time: time ?? this.time,
    skipIfWritten: skipIfWritten ?? this.skipIfWritten,
    blocked: blocked ?? this.blocked,
  );

  @override
  bool operator ==(Object other) =>
      other is WritingReminder &&
      other.on == on &&
      other.time == time &&
      other.skipIfWritten == skipIfWritten &&
      other.blocked == blocked;

  @override
  int get hashCode => Object.hash(on, time, skipIfWritten, blocked);
}

/// Whether [a] and [b] fall on the same day in this device's time zone.
bool isSameLocalDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// The day whose reminder is skipped, as its local midnight: today, when
/// [skipIfWritten] is on and an Entry was last created today; else null.
DateTime? skippedDay({
  required DateTime now,
  required DateTime? lastEntryCreated,
  required bool skipIfWritten,
}) {
  if (!skipIfWritten || lastEntryCreated == null) return null;
  if (!isSameLocalDay(lastEntryCreated, now)) return null;
  final today = now.toLocal();
  return DateTime(today.year, today.month, today.day);
}

/// When the next reminder comes, in local time: today at [time] if that is
/// still ahead and today is not [skipped], else tomorrow at [time].
DateTime nextReminder({
  required DateTime now,
  required TimeOfDay time,
  DateTime? skipped,
}) {
  final local = now.toLocal();
  final today = DateTime(
    local.year,
    local.month,
    local.day,
    time.hour,
    time.minute,
  );
  final skipToday = skipped != null && isSameLocalDay(skipped, local);
  if (today.isAfter(local) && !skipToday) return today;
  // By the calendar, not by 24 hours, so a daylight saving change keeps
  // the time.
  return DateTime(
    local.year,
    local.month,
    local.day + 1,
    time.hour,
    time.minute,
  );
}

/// The language the notification is written in: the app's, as at
/// scheduling time.
AppLocalizations reminderLocalizations(LanguageChoice choice) =>
    lookupAppLocalizations(choice.locale ?? deviceLanguage());

/// The Writing reminder: its settings, and the one notification scheduled
/// on the device to match them.
///
/// Scheduling is redone when the app opens or comes back, and when the
/// settings, the app language, or today's Entries change; the device redoes
/// it after a restart or a time zone change. It never reads the store: an
/// Entry created today is known from [entryCreated].
class WritingReminderNotifier extends Notifier<WritingReminder> {
  DateTime? _lastEntryCreated;

  /// Whether the device is asking to notify; the app comes back from that
  /// dialog before the answer does.
  var _asking = false;

  ReminderPlatform get _platform => ref.read(reminderPlatformProvider);

  @override
  WritingReminder build() {
    final saved = ref.read(savedSettingsProvider);
    _lastEntryCreated = saved.lastEntryCreated;

    ref.listen(languageProvider, (_, _) => unawaited(sync()));
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(sync()));
    ref.onDispose(lifecycle.dispose);
    _platform.onOpened(() => ref.read(routerProvider).go(Routes.books));
    // The app just opened.
    Future.microtask(sync);

    return saved.writingReminder;
  }

  /// Turns the reminder on, asking to notify first. Returns whether it is
  /// on: when the device does not allow it, it stays off and [state] is
  /// [WritingReminder.blocked].
  Future<bool> turnOn() async {
    if (_asking) return false;
    // The switch moves at once, and back if the answer is no.
    state = state.copyWith(on: true);
    _asking = true;
    final bool allowed;
    try {
      allowed = await _platform.requestPermission();
    } on Object catch (error) {
      debugPrint('Could not ask to notify: $error');
      state = state.copyWith(on: false);
      return false;
    } finally {
      _asking = false;
    }
    if (!allowed) {
      state = state.copyWith(on: false, blocked: true);
      return false;
    }
    _set(state.copyWith(on: true, blocked: false));
    await sync();
    return true;
  }

  Future<void> turnOff() async {
    _set(state.copyWith(on: false));
    await sync();
  }

  Future<void> setTime(TimeOfDay time) async {
    _set(state.copyWith(time: time));
    await sync();
  }

  Future<void> setSkipIfWritten(bool skip) async {
    _set(state.copyWith(skipIfWritten: skip));
    await sync();
  }

  /// An Entry was just created: with "Skip if I already wrote" on, today's
  /// reminder is dropped.
  Future<void> entryCreated() async {
    final now = ref.read(clockProvider)();
    _lastEntryCreated = now;
    savePreference(
      ref,
      (preferences) => saveLastEntryCreated(preferences, now),
    );
    if (state.on && state.skipIfWritten) await sync();
  }

  /// Schedules the notification as the settings say, or cancels it.
  Future<void> sync() async {
    if (_asking) return;
    try {
      final allowed = await _platform.notificationsAllowed();
      if (!ref.mounted) return;
      final blocked = !allowed && (state.on || state.blocked);
      if (blocked != state.blocked) state = state.copyWith(blocked: blocked);

      if (!state.on) {
        await _platform.cancel();
        return;
      }
      final now = ref.read(clockProvider)();
      final skipped = skippedDay(
        now: now,
        lastEntryCreated: _lastEntryCreated,
        skipIfWritten: state.skipIfWritten,
      );
      final l10n = reminderLocalizations(ref.read(languageProvider));
      await _platform.schedule(
        ReminderSchedule(
          first: nextReminder(now: now, time: state.time, skipped: skipped),
          time: state.time,
          skipped: skipped,
          text: l10n.reminderNotificationText,
        ),
      );
    } on Object catch (error) {
      // Tried again the next time the app opens.
      debugPrint('The Writing reminder could not be scheduled: $error');
    }
  }

  void _set(WritingReminder reminder) {
    state = reminder;
    savePreference(
      ref,
      (preferences) => saveWritingReminder(preferences, reminder),
    );
  }
}

final writingReminderProvider =
    NotifierProvider<WritingReminderNotifier, WritingReminder>(
      WritingReminderNotifier.new,
    );
