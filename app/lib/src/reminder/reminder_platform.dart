import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// One daily reminder, as the device schedules it.
@immutable
class ReminderSchedule {
  const ReminderSchedule({
    required this.first,
    required this.time,
    required this.text,
    this.skipped,
  });

  /// When it first comes, in local time.
  final DateTime first;

  /// The local time it comes at every day after.
  final TimeOfDay time;

  /// A day, as its local midnight, that goes without one even when the
  /// device schedules it again, as after a restart.
  final DateTime? skipped;

  /// The notification's text, in the app's language.
  final String text;
}

/// The device's side of the Writing reminder: notifying, and asking to.
abstract interface class ReminderPlatform {
  /// Whether the device lets Kronoer notify.
  Future<bool> notificationsAllowed();

  /// Asks to notify where the device asks (Android 13 and higher). Returns
  /// whether Kronoer may.
  Future<bool> requestPermission();

  /// Replaces any reminder scheduled with [schedule].
  Future<void> schedule(ReminderSchedule schedule);

  Future<void> cancel();

  /// Opens Kronoer's notification settings on the device.
  Future<void> openNotificationSettings();

  /// Calls [opened] when a reminder is tapped while the app is running.
  void onOpened(VoidCallback opened);
}

/// Android's, through the app's own platform channel.
class AndroidReminderPlatform implements ReminderPlatform {
  const AndroidReminderPlatform();

  static const _channel = MethodChannel('app.kronoer/reminder');

  @override
  Future<bool> notificationsAllowed() async =>
      await _channel.invokeMethod<bool>('notificationsAllowed') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<void> schedule(ReminderSchedule schedule) =>
      _channel.invokeMethod<void>('schedule', {
        'first': schedule.first.millisecondsSinceEpoch,
        'hour': schedule.time.hour,
        'minute': schedule.time.minute,
        'skipped': switch (schedule.skipped) {
          final day? => _localDate(day),
          null => null,
        },
        'text': schedule.text,
      });

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  @override
  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  @override
  void onOpened(VoidCallback opened) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') opened();
    });
  }

  /// The day as yyyy-MM-dd, as the device compares days.
  static String _localDate(DateTime day) {
    final local = day.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

/// Nothing to notify with, as in tests and the gallery: always allowed,
/// never notifies.
class NoReminderPlatform implements ReminderPlatform {
  const NoReminderPlatform();

  @override
  Future<bool> notificationsAllowed() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(ReminderSchedule schedule) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> openNotificationSettings() async {}

  @override
  void onOpened(VoidCallback opened) {}
}

final reminderPlatformProvider = Provider<ReminderPlatform>(
  (ref) => const NoReminderPlatform(),
);
