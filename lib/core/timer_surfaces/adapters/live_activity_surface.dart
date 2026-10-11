import 'package:flutter/services.dart';

import '../../models/time_models.dart';
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// The moment a local copy of [state] goes away by itself: a day after the
/// start, or an hour after the end of the stretch, whichever comes first.
///
/// One rule for the Live Activity and the widgets, so neither outlives the
/// other on the lock screen.
DateTime? timerSurfaceDismissAt(TimerSurfaceState state) {
  final startedAt = state.startedAt;
  if (startedAt == null) return null;
  final byDay = state.validUntil ?? startedAt.add(timerSurfaceLifetime);
  final endsAt = state.endsAt;
  if (endsAt == null) return byDay;
  final byEnd = endsAt.add(const Duration(hours: 1));
  return byEnd.isBefore(byDay) ? byEnd : byDay;
}

/// The longest description a lock-screen surface carries. ActivityKit allows
/// 4 KB for attributes and content together; a sentence is plenty.
const int lockScreenLabelMax = 120;

String? clipLockScreenLabel(String? label) {
  if (label == null) return null;
  final runes = label.runes.toList();
  if (runes.length <= lockScreenLabelMax) return label;
  return '${String.fromCharCodes(runes.take(lockScreenLabelMax - 1))}…';
}

/// The native side of the Live Activity, behind one seam so tests hand a fake.
///
/// `hinata/live_activity` in the iOS runner (`HinataLiveActivityChannel`).
/// The channel keeps at most one activity: [start] adopts one that is already
/// there (after a relaunch) and ends any extra.
class LiveActivityChannel {
  const LiveActivityChannel([
    this._channel = const MethodChannel('hinata/live_activity'),
  ]);

  final MethodChannel _channel;

  /// Whether the person allows Live Activities for this app.
  Future<bool> areActivitiesEnabled() async =>
      await _channel.invokeMethod<bool>('areActivitiesEnabled') ?? false;

  /// Requests or adopts the activity and draws [content]. The opaque ref of
  /// the activity, or null where the system refused (switched off, or the app
  /// is not in front to ask).
  Future<String?> start(Map<String, Object?> content) =>
      _channel.invokeMethod<String>('start', content);

  Future<void> update(String ref, Map<String, Object?> content) =>
      _channel.invokeMethod<void>('update', {'ref': ref, ...content});

  /// Ends the activity at once.
  Future<void> end(String ref) =>
      _channel.invokeMethod<void>('end', {'ref': ref});

  /// Ends every activity of this app, also one a previous run left behind.
  Future<void> endAll() => _channel.invokeMethod<void>('endAll');
}

/// The running timer as a Live Activity on the lock screen, in the Dynamic
/// Island and in StandBy (iOS 16.1 and later).
///
/// Local only: the app starts, updates and ends it while it runs, and the
/// system ticks the time (`Text(timerInterval:)`) without a single update. A
/// suspended app updates nothing, so the end of a stretch shows through
/// `staleDate`, and the activity goes away by itself at
/// [timerSurfaceDismissAt] at the latest.
class LiveActivitySurface extends TimerSurface {
  LiveActivitySurface({
    LiveActivityChannel channel = const LiveActivityChannel(),
  }) : _channel = channel;

  final LiveActivityChannel _channel;

  /// The activity this run started or adopted.
  String? _ref;

  @override
  String get id => 'live-activity';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(SurfacePlatform.ios);

  @override
  Future<void> init(TimerSurfaceHost host) async {}

  @override
  Future<void> apply(TimerSurfaceState state) async {
    final content = liveActivityContent(state);
    if (content == null) {
      await _end();
      return;
    }
    final ref = _ref;
    if (ref != null) {
      await _channel.update(ref, content);
      return;
    }
    // A timer read back from the cache may be one that ended elsewhere a
    // minute ago. Something new goes up only for what the server said in this
    // run; the next state after the refresh brings it.
    if (!state.confirmed) return;
    _ref = await _channel.start(content);
  }

  Future<void> _end() async {
    final ref = _ref;
    _ref = null;
    // Also without a ref of ours: an activity of an earlier run, adopted by
    // nobody yet, must not keep a stopped timer ticking on the lock screen.
    if (ref != null) {
      await _channel.end(ref);
    } else {
      await _channel.endAll();
    }
  }

  /// The end of a stretch shows through `staleDate`; nothing to do here.
  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  @override
  Future<void> clear() async {
    _ref = null;
    await _channel.endAll();
  }

  @override
  Future<void> dispose() async {}
}

/// What the Live Activity of [state] draws, or null when it has none.
///
/// The words come from the app in the reader's language; the activity itself
/// has no strings but its gallery name. No ids: the activity is a display of
/// the timer and never needs to know which record it is.
Map<String, Object?>? liveActivityContent(
  TimerSurfaceState state, {
  DateTime? now,
}) {
  final startedAt = state.startedAt;
  final dismissAt = timerSurfaceDismissAt(state);
  if (!state.running ||
      !state.runningSurface ||
      startedAt == null ||
      dismissAt == null ||
      !dismissAt.isAfter((now ?? DateTime.now()).toUtc())) {
    return null;
  }
  final texts = state.texts;
  return {
    'mode': state.mode?.name ?? TimerMode.stopwatch.name,
    'phase': state.phase?.name,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endsAt': state.endsAt?.millisecondsSinceEpoch,
    'dismissAt': dismissAt.millisecondsSinceEpoch,
    'title': state.isBreak ? texts.onBreak : texts.running,
    'staleTitle': state.endsAt == null ? null : state.endText,
    'label': clipLockScreenLabel(state.lockScreenLabel),
  };
}
