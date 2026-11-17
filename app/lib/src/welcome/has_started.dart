import 'package:flutter_riverpod/flutter_riverpod.dart';

class HasStartedNotifier extends Notifier<bool> {
  HasStartedNotifier([this._initial = false]);

  final bool _initial;

  @override
  bool build() => _initial;

  void markStarted() => state = true;
}

final hasStartedProvider = NotifierProvider<HasStartedNotifier, bool>(
  HasStartedNotifier.new,
);
