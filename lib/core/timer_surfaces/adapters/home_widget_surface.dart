import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
abstract interface class TimerWidgetStore {
  /// home_widget on iOS and Android, `widgetkit_macos` on a Mac (HIN-108).
  factory TimerWidgetStore.forPlatform(
    SurfacePlatform platform, {
    Future<void> Function(Uri?)? backgroundAction,
  }) => platform == SurfacePlatform.macos
      ? MacTimerWidgetStore()
      : HomeWidgetTimerStore(backgroundAction: backgroundAction);

  /// [host] runs what a widget button asks for, on a Mac, where the app
  /// takes those requests itself.
  Future<void> init(TimerSurfaceHost host);

  /// Writes [record] (an empty one with null) and asks the widgets to draw.
  Future<void> write(String? record);
}

/// The store of the widgets on iOS and Android, through home_widget.
class HomeWidgetTimerStore implements TimerWidgetStore {
  const HomeWidgetTimerStore({this.backgroundAction});

  /// Android only: the action behind the widget buttons and the Quick
  /// Settings tile (HIN-103), a top-level function home_widget runs in a
  /// background engine with a `hinata://timer/<command>` link. The iOS
  /// buttons run App Intents (HIN-105), so it is null there.
  final Future<void> Function(Uri?)? backgroundAction;

  @override
  Future<void> init(TimerSurfaceHost host) async {
    await HomeWidget.setAppGroupId(timerWidgetAppGroup);
    final action = backgroundAction;
    if (action != null) await HomeWidget.registerInteractivityCallback(action);
  }

  /// Never a null: home_widget 0.9.4 hands it to iOS as `NSNull`, and
  /// `UserDefaults` throws on that, which takes the whole app down. Both
  /// native readers take an empty record for none.
  @override
  Future<void> write(String? record) async {
    await HomeWidget.saveWidgetData<String>(timerWidgetKey, record ?? '');
    await HomeWidget.updateWidget(
      iOSName: timerWidgetKind,
      qualifiedAndroidName: timerWidgetAndroidProvider,
    );
  }
}

/// Where a button of the Mac's widget leaves its request in the App Group.
const String timerWidgetCommandKey = 'hinata_widget_command';

/// The runner's word that a request waits under [timerWidgetCommandKey].
const MethodChannel timerWidgetCommandChannel = MethodChannel(
  'hinata/widget_commands',
);

/// The store of the Mac's widgets (HIN-108): home_widget has no macOS, so the
/// same record goes into the same App Group through `widgetkit_macos`.
///
/// It also takes the requests of the widget's buttons. macOS runs a widget's
/// intent in the extension, which has neither the network nor the session,
/// so the intent leaves the command in the App Group and wakes the app
/// (`HinataWidgetCommandChannel` in the runner); the app then makes the same
/// request as its own button. A request found at launch is the press that
/// opened the app.
class MacTimerWidgetStore implements TimerWidgetStore {
  MacTimerWidgetStore({
    WidgetKitMacos? kit,
    @visibleForTesting MethodChannel commands = timerWidgetCommandChannel,
    @visibleForTesting DateTime Function()? now,
  }) : _kit = kit ?? WidgetKitMacos(appGroup: timerWidgetAppGroup),
       _commands = commands,
       _now = now ?? DateTime.now;

  /// How old a request may be and still act: a press from before a long
  /// launch or a sign-in never starts a timer by surprise.
  static const commandPatience = Duration(seconds: 30);

  final WidgetKitMacos _kit;
  final MethodChannel _commands;
  final DateTime Function() _now;
  TimerSurfaceHost? _host;

  /// One request at a time, so two quick presses never read the same one.
  Future<void> _taking = Future.value();

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _host = host;
    _commands.setMethodCallHandler((call) async {
      if (call.method == 'command') await takeCommand();
    });
    await takeCommand();
  }

  /// Reads, removes and runs the waiting request, if any.
  @visibleForTesting
  Future<void> takeCommand() => _taking = _taking.then((_) async {
    final raw = await _kit.getWidgetData<String>(timerWidgetCommandKey);
    if (raw == null || raw.isEmpty) return;
    await _kit.saveWidgetData(timerWidgetCommandKey, null);
    final host = _host;
    if (host == null) return;
    switch (parseTimerWidgetCommand(
      raw,
      now: _now(),
      patience: commandPatience,
    )) {
      case TimerWidgetCommand.start:
        await host.start();
      case TimerWidgetCommand.stop:
        await host.end();
      case TimerWidgetCommand.advancePhase:
        await host.advancePhase();
      case null:
        break;
    }
  });

  /// An empty record for none, as on iOS: the widget reads the same way.
  @override
  Future<void> write(String? record) async {
    await _kit.saveWidgetData(timerWidgetKey, record ?? '');
    await _kit.reloadTimelines(timerWidgetKind);
  }
}

/// What a button of the Mac's widget asks for.
enum TimerWidgetCommand { start, stop, advancePhase }

/// The command in [raw] (`{"command": "stop", "at": <ms>}`, as the extension
/// writes it), or null when it is unknown, malformed, from the future or
/// older than [patience].
TimerWidgetCommand? parseTimerWidgetCommand(
  String raw, {
  required DateTime now,
  required Duration patience,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded case {'command': final String name, 'at': final int at}) {
    final age = now.difference(DateTime.fromMillisecondsSinceEpoch(at));
    // A little slack for a clock read a moment apart in two processes.
    if (age > patience || age < const Duration(seconds: -5)) return null;
    return TimerWidgetCommand.values.asNameMap()[name];
  }
  return null;
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
    : _store = store ?? TimerWidgetStore.forPlatform(platform);

  final SurfacePlatform platform;
  final TimerWidgetStore _store;

  /// The last record written, so an unchanged one is not written again.
  String? _written;
  bool _hasWritten = false;

  /// The words of the idle widget from the last state that carried any. An
  /// idle state carries none, and the widget has to say something then too.
  String _idle = '';

  /// The word of the idle widget's start button (iOS, HIN-105; a Mac), kept
  /// the same way as [_idle].
  String _start = '';

  @override
  String get id => 'home-widget';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  @override
  Future<void> init(TimerSurfaceHost host) => _store.init(host);

  @override
  Future<void> apply(TimerSurfaceState state) async {
    if (state.texts.idle.isNotEmpty) _idle = state.texts.idle;
    if (state.texts.start.isNotEmpty) _start = state.texts.start;
    await _write(
      timerWidgetRecord(
        state,
        idle: _idle,
        start: platform == SurfacePlatform.android ? '' : _start,
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
/// button that starts a stopwatch (iOS, HIN-105, and a Mac); empty leaves
/// it out.
String timerWidgetRecord(
  TimerSurfaceState state, {
  String idle = '',
  String start = '',
}) {
  final content = liveActivityContent(state, yieldToAlarm: false);
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
