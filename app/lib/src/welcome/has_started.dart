import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/src/settings/saved_settings.dart';

/// Whether the user has gone past Welcome. Saved on the device once they
/// start, so deleting every Book later leads to the empty Book list, not back
/// to Welcome.
class HasStartedNotifier extends Notifier<bool> {
  HasStartedNotifier([this._initial = false]);

  final bool _initial;

  @override
  bool build() => _initial;

  void markStarted() {
    state = true;
    savePreference(ref, saveHasStarted);
  }
}

final hasStartedProvider = NotifierProvider<HasStartedNotifier, bool>(
  HasStartedNotifier.new,
);
