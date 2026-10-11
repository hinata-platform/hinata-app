import 'package:flutter/foundation.dart';

import 'timer_surface.dart';
import 'timer_surface_state.dart';

/// Hands one state to every surface, and keeps a broken one from taking the
/// others down.
///
/// A surface is applied only when its state changed. One that fails twice is
/// left alone for the rest of the run (two strikes, like the chime): a plugin
/// missing on one desktop must not throw on every tick of the timer.
class TimerSurfaceCoordinator {
  TimerSurfaceCoordinator(this.surfaces);

  final List<TimerSurface> surfaces;

  static const int strikes = 2;

  final Map<String, TimerSurfaceState> _applied = {};
  final Map<String, int> _failures = {};

  bool _live(TimerSurface surface) => (_failures[surface.id] ?? 0) < strikes;

  /// Whether [surface] was put aside after repeated failures.
  bool isQuarantined(TimerSurface surface) => !_live(surface);

  /// The union of what the working surfaces can do.
  TimerSurfaceCapabilities get capabilities => surfaces
      .where(_live)
      .fold(TimerSurfaceCapabilities.none, (all, s) => all | s.capabilities);

  Future<void> init(TimerSurfaceHost host) async {
    for (final surface in surfaces) {
      await _guard(surface, () => surface.init(host));
    }
  }

  Future<void> apply(TimerSurfaceState state) async {
    for (final surface in surfaces.where(_live)) {
      if (_applied[surface.id] == state) continue;
      final ok = await _guard(surface, () => surface.apply(state));
      if (ok) _applied[surface.id] = state;
    }
  }

  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {
    for (final surface in surfaces.where(_live)) {
      await _guard(
        surface,
        () => surface.phaseEnded(state, foreground: foreground),
      );
    }
  }

  void tick(Duration shown) {
    for (final surface in surfaces.where(_live)) {
      try {
        surface.tick(shown);
      } catch (error) {
        _strike(surface, error);
      }
    }
  }

  /// Clears every surface and forgets what each one shows, so the next state
  /// is applied in full. Also the quarantined ones: a surface that failed to
  /// draw may still have drawn something.
  Future<void> clearAll() async {
    for (final surface in surfaces) {
      try {
        await surface.clear();
      } catch (error) {
        debugPrint('Timer surface ${surface.id} did not clear: $error');
      }
    }
    _applied.clear();
  }

  /// Forgets what was applied, so the same state is drawn again (after the
  /// app comes back to the front, when the system may have dropped things).
  void invalidate() => _applied.clear();

  Future<void> dispose() async {
    for (final surface in surfaces) {
      try {
        await surface.dispose();
      } catch (_) {
        // Going away anyway.
      }
    }
  }

  Future<bool> _guard(TimerSurface surface, Future<void> Function() run) async {
    try {
      await run();
      return true;
    } catch (error) {
      _strike(surface, error);
      return false;
    }
  }

  void _strike(TimerSurface surface, Object error) {
    final count = (_failures[surface.id] ?? 0) + 1;
    _failures[surface.id] = count;
    debugPrint('Timer surface ${surface.id} failed ($count): $error');
  }
}
