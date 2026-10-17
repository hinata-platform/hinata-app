import 'dart:async';

import 'package:flutter/services.dart';

import '../../models/time_models.dart';
import '../live_activity_push_registry.dart';
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
  ///
  /// With [push] a new activity is requested for server updates (HIN-103):
  /// iOS makes a key for it, and its push token arrives through [onPushToken].
  /// An adopted activity keeps whatever it was requested with.
  Future<String?> start(Map<String, Object?> content, {bool push = false}) =>
      _channel.invokeMethod<String>('start', {...content, 'push': push});

  /// Hands every push token iOS issues for one of our activities to
  /// [handler]: the first one, and every rotation after it.
  void onPushToken(void Function(LiveActivityPushToken token) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'pushToken') return;
      final args = call.arguments;
      if (args is! Map) return;
      final ref = args['ref'];
      final token = args['token'];
      final key = args['key'];
      if (ref is! String || token is! String || key is! String) return;
      handler(LiveActivityPushToken(ref: ref, token: token, key: key));
    });
  }

  /// False when the activity is gone (swiped away, ended by the system).
  Future<bool> update(String ref, Map<String, Object?> content) async =>
      await _channel.invokeMethod<bool>('update', {'ref': ref, ...content}) ??
      false;

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
///
/// With background updates switched on (HIN-103) a new activity is requested
/// for server pushes, and its token is registered while that switch stays on
/// and the activity lives. The server then moves it along through a phase
/// change or a stop on another device, sealed under a key only this phone and
/// the server hold.
class LiveActivitySurface extends TimerSurface {
  LiveActivitySurface({
    LiveActivityChannel channel = const LiveActivityChannel(),
    LiveActivityPushRegistry? registry,
  }) : _channel = channel,
       _registry = registry;

  final LiveActivityChannel _channel;
  final LiveActivityPushRegistry? _registry;

  /// The push token of [_ref] as iOS issued it, registered or not.
  LiveActivityPushToken? _token;

  /// The token the server holds for us right now.
  String? _registered;

  /// Whether the last state asked for background updates.
  bool _wantsPush = false;

  /// The activity this run started or adopted.
  String? _ref;

  /// The timer whose activity the person swiped away; a new one goes up only
  /// for the next timer.
  DateTime? _gone;

  DateTime? _stretch(TimerSurfaceState state) => state.startedAt;

  @override
  String get id => 'live-activity';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(SurfacePlatform.ios);

  @override
  Future<void> init(TimerSurfaceHost host) async {
    if (_registry != null) _channel.onPushToken(_onToken);
  }

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _wantsPush = state.backgroundUpdates && _registry != null;
    final content = liveActivityContent(state);
    if (content == null) {
      await _end();
      return;
    }
    final ref = _ref;
    if (ref != null) {
      // Swiped away by the person: not brought back for the same timer.
      if (!await _channel.update(ref, content)) _gone = _stretch(state);
      if (_gone != null) {
        _ref = null;
        await _unregister();
      } else {
        await _syncRegistration();
      }
      return;
    }
    if (_gone == _stretch(state)) return;
    _gone = null;
    // A timer read back from the cache may be one that ended elsewhere a
    // minute ago. Something new goes up only for what the server said in this
    // run; the next state after the refresh brings it.
    if (!state.confirmed) return;
    _ref = await _channel.start(content, push: _wantsPush);
    await _syncRegistration();
  }

  void _onToken(LiveActivityPushToken token) {
    _token = token;
    unawaited(_syncRegistration());
  }

  /// Registers the token of the current activity while background updates
  /// are on, and takes it back as soon as they are not.
  Future<void> _syncRegistration() async {
    final registry = _registry;
    if (registry == null) return;
    final token = _token;
    final current = token != null && token.ref == _ref ? token : null;
    final wanted = _wantsPush ? current?.token : null;
    if (wanted == _registered) return;
    await _unregister();
    if (wanted == null || current == null) return;
    if (await registry.register(current)) _registered = wanted;
  }

  Future<void> _unregister() async {
    final registered = _registered;
    _registered = null;
    if (registered != null) await _registry?.unregister(registered);
  }

  Future<void> _end() async {
    final ref = _ref;
    _ref = null;
    _token = null;
    await _unregister();
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
    _token = null;
    await _unregister();
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
///
/// A countdown or a Pomodoro phase that ends in an alarm has the system's
/// countdown instead (HIN-106), so the activity steps aside for it. The
/// widgets read the same content with [yieldToAlarm] off: they show the timer
/// whether or not an alarm rings at its end.
Map<String, Object?>? liveActivityContent(
  TimerSurfaceState state, {
  DateTime? now,
  bool yieldToAlarm = true,
}) {
  final startedAt = state.startedAt;
  final dismissAt = timerSurfaceDismissAt(state);
  if (!state.running ||
      !state.runningSurface ||
      (yieldToAlarm && state.alarmMode && state.endsAt != null) ||
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
    // The words the widget extension draws once a state arrives from the
    // server, which carries times and nothing to read (HIN-103). Kept on this
    // phone beside the activity's key, never sent.
    'words': {
      'running': texts.running,
      'onBreak': texts.onBreak,
      'countdownOver': texts.countdownOver,
      'workOver': texts.workOver,
      'breakOver': texts.breakOver,
    },
  };
}
