import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:widgetkit_macos/widgetkit_macos.dart';

import '../../models/time_models.dart';
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';
import 'live_activity_surface.dart';

/// The App Group the widgets on iOS and macOS read from.
const String timerWidgetAppGroup = 'group.com.ahmadre.hinata';

/// The one record the widgets read.
const String timerWidgetKey = 'hinata_timer';

/// The widget kind on iOS and macOS, and the provider class on Android.
const String timerWidgetKind = 'HinataTimerWidget';
const String timerWidgetAndroidProvider =
    'com.ahmadre.hinata.TimerWidgetProvider';

/// The shared store of the widgets, behind one seam so tests hand a fake.
class TimerWidgetStore {
  const TimerWidgetStore({this.backgroundAction});

  /// The action behind the widget buttons and the Quick Settings tile
  /// (HIN-103): a top-level function home_widget runs in a background engine
  /// with a `hinata://timer/<command>` link. Null leaves the buttons inert.
  final Future<void> Function(Uri?)? backgroundAction;

  Future<void> init() async {
    await HomeWidget.setAppGroupId(timerWidgetAppGroup);
    final action = backgroundAction;
    if (action != null) await HomeWidget.registerInteractivityCallback(action);
  }

  /// Writes [record] (an empty one with null) and asks the widgets to draw.
  ///
  /// Never a null: home_widget 0.9.4 hands it to iOS as `NSNull`, and
  /// `UserDefaults` throws on that, which takes the whole app down. Both
  /// native readers take an empty record for none.
  Future<void> write(String? record) async {
    await HomeWidget.saveWidgetData<String>(timerWidgetKey, record ?? '');
    await HomeWidget.updateWidget(
      iOSName: timerWidgetKind,
      qualifiedAndroidName: timerWidgetAndroidProvider,
    );
  }
}

/// The store of the Mac's widgets (HIN-108): home_widget has no macOS, so the
/// same record goes into the same App Group through `widgetkit_macos`.
class MacTimerWidgetStore extends TimerWidgetStore {
  MacTimerWidgetStore({WidgetKitMacos? kit})
    : _kit = kit ?? WidgetKitMacos(appGroup: timerWidgetAppGroup);

  final WidgetKitMacos _kit;

  @override
  Future<void> init() async {}

  /// An empty record for none, as on iOS: the widget reads the same way.
  @override
  Future<void> write(String? record) async {
    await _kit.saveWidgetData(timerWidgetKey, record ?? '');
    await _kit.reloadTimelines(timerWidgetKind);
  }
}

/// The running timer in the home-screen widgets (iOS and Android), the
/// lock-screen widgets (iOS), and the desktop and Notification Center widgets
/// on a Mac (HIN-108).
///
/// The widgets tick on their own (`Text(_, style: .timer)`, a `Chronometer`)
/// and fall back to idle at `validUntil` without the app or the network, so
/// the app writes on a change of state only.
class HomeWidgetSurface extends TimerSurface {
  HomeWidgetSurface(this.platform, {TimerWidgetStore? store})
    : _store = store ?? const TimerWidgetStore();

  final SurfacePlatform platform;
  final TimerWidgetStore _store;

  /// The last record written, so an unchanged one is not written again.
  String? _written;
  bool _hasWritten = false;

  /// The words of the idle widget from the last state that carried any. An
  /// idle state carries none, and the widget has to say something then too.
  String _idle = '';

  /// The word of the idle widget's start button (iOS, HIN-105), kept the same
  /// way as [_idle].
  String _start = '';

  @override
  String get id => 'home-widget';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  @override
  Future<void> init(TimerSurfaceHost host) => _store.init();

  @override
  Future<void> apply(TimerSurfaceState state) async {
    if (state.texts.idle.isNotEmpty) _idle = state.texts.idle;
    if (state.texts.start.isNotEmpty) _start = state.texts.start;
    await _write(
      timerWidgetRecord(
        state,
        idle: _idle,
        start: platform == SurfacePlatform.ios ? _start : '',
      ),
    );
  }

  Future<void> _write(String? record) async {
    if (_hasWritten && record == _written) return;
    await _store.write(record);
    _written = record;
    _hasWritten = true;
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  /// Removes the record: the widget then shows only its gallery name.
  @override
  Future<void> clear() async {
    _idle = '';
    _start = '';
    _hasWritten = false;
    await _write(null);
  }

  @override
  Future<void> dispose() async {}
}

/// The record the widgets read for [state], as JSON.
///
/// Minimal by design: start, end, the direction, whether a break runs, when
/// the copy expires and, only with details on the lock screen switched on,
/// the description. No timer id and no other id, so nothing on the device
/// links the widget to a record on the server. Idle, [start] names the
/// button that starts a stopwatch (iOS, HIN-105); empty leaves it out.
String timerWidgetRecord(
  TimerSurfaceState state, {
  String idle = '',
  String start = '',
}) {
  final content = liveActivityContent(state);
  final startedAt = state.startedAt;
  if (content == null || startedAt == null) {
    return jsonEncode({'idle': idle, if (start.isNotEmpty) 'start': start});
  }
  final texts = state.texts;
  final endsAt = state.endsAt;
  return jsonEncode({
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endsAt': ?endsAt?.millisecondsSinceEpoch,
    'countsDown': endsAt != null,
    if (state.phase != null) 'phaseKind': state.isBreak ? 'break' : 'work',
    'validUntil': content['dismissAt'],
    'label': ?clipLockScreenLabel(state.lockScreenLabel),
    'title': state.isBreak ? texts.onBreak : texts.running,
    if (endsAt != null) 'over': state.endText,
    // The buttons (HIN-103): they act in the background, the words are the
    // app's. A phase button only where there are phases.
    'stop': texts.stop,
    if (state.mode == TimerMode.pomodoro)
      'advance': state.isBreak ? texts.resume : texts.takeBreak,
    'idle': idle,
    // What the widget offers once this copy expires.
    if (start.isNotEmpty) 'start': start,
  });
}
