import 'package:hinata/core/timer_surfaces/timer_surface.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

/// A surface that records what it was asked to do, and can be told to fail.
class RecordingSurface extends TimerSurface {
  RecordingSurface(this.id, {this.failing = false});

  @override
  final String id;

  bool failing;

  final List<TimerSurfaceState> applied = [];
  final List<bool> ended = [];
  final List<Duration> ticks = [];
  int clears = 0;
  TimerSurfaceHost? host;

  @override
  TimerSurfaceCapabilities get capabilities =>
      const TimerSurfaceCapabilities(phaseEndNotification: true);

  void _maybeFail() {
    if (failing) throw StateError('surface $id is broken');
  }

  @override
  Future<void> init(TimerSurfaceHost host) async => this.host = host;

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _maybeFail();
    applied.add(state);
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {
    _maybeFail();
    ended.add(foreground);
  }

  @override
  void tick(Duration shown) {
    _maybeFail();
    ticks.add(shown);
  }

  @override
  Future<void> clear() async => clears++;

  @override
  Future<void> dispose() async {}
}

/// A HydratedBloc store that lives in memory.
class MemoryStorage implements Storage {
  final Map<String, dynamic> values = {};

  @override
  dynamic read(String key) => values[key];

  @override
  Future<void> write(String key, dynamic value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<void> close() async {}
}
