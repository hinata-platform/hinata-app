import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hinata_device_lock/hinata_device_lock.dart';

import '../api/api_client.dart';
import '../models/time_models.dart';
import '../repositories/time_repository.dart';
import '../storage/app_storage.dart';
import '../timer_surfaces/adapters/home_widget_surface.dart';
import '../timer_surfaces/adapters/live_activity_surface.dart';
import '../timer_surfaces/adapters/local_notifications_surface.dart';
import '../timer_surfaces/surface_platform.dart';
import '../timer_surfaces/timer_surface.dart';
import '../timer_surfaces/timer_surface_state.dart';
import '../timer_surfaces/background/timer_surface_snapshot.dart';

/// What a button outside the app may do to the timer without opening it
/// (HIN-103). Never a start, and never anything that carries content.
enum TimerBackgroundCommand {
  stop,
  advancePhase;

  /// The command of a widget or tile link, `hinata://timer/<command>`.
  static TimerBackgroundCommand? fromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'hinata' || uri.host != 'timer') {
      return null;
    }
    return switch (uri.pathSegments.firstOrNull) {
      'stop' => stop,
      'advancePhase' => advancePhase,
      _ => null,
    };
  }

  /// The command of a notification button.
  static TimerBackgroundCommand? fromNotificationAction(String? actionId) =>
      switch (actionId) {
        TimerNotificationAction.stop => stop,
        TimerNotificationAction.advance => advancePhase,
        _ => null,
      };
}

/// How a background action ended. Nothing of it is sent; on Android a press
/// that did nothing says so in a short notification, and the app reconciles
/// with the server when it next opens.
enum TimerBackgroundOutcome {
  done,

  /// No timer was running any more (stopped elsewhere a moment ago).
  nothingRunning,

  /// The screen was locked; the person is told to unlock and try again.
  locked,

  /// Signed out, the session was ended, or no server.
  signedOut,

  /// The server said no or was not reached.
  failed,
}

/// Runs one [TimerBackgroundCommand] in a background isolate and redraws the
/// surfaces this isolate can reach.
///
/// It is the same request the button in the app makes, against the server's
/// timer as it is now: a stop names the timer it ends, a phase change the
/// phase it turns, so a press that arrives after the timer changed elsewhere
/// does no harm. An expired access token is refreshed like in the app: the
/// server's refresh tokens belong to the device's session and stay valid
/// after a refresh, so the running app keeps working with the pair it holds.
/// Only a refused refresh ends the session.
class TimerBackgroundAction {
  TimerBackgroundAction({
    required this.time,
    required this.surfaces,
    required this.snapshot,
    this.lock = const HinataDeviceLock(),
    this.unlockGrace = const Duration(seconds: 3),
    this.unlockPoll = const Duration(milliseconds: 250),
  });

  final TimeRepository time;

  /// The surfaces this isolate redraws: the widgets, Android's notifications
  /// and, on iOS, the Live Activity.
  final List<TimerSurface> surfaces;
  final TimerSurfaceSnapshot snapshot;
  final HinataDeviceLock lock;
  final Duration unlockGrace;
  final Duration unlockPoll;

  Future<TimerBackgroundOutcome> run(TimerBackgroundCommand command) async {
    if (await _stillLocked()) return TimerBackgroundOutcome.locked;
    try {
      final timer = await time.timer();
      if (timer == null) {
        await _redraw(null);
        return TimerBackgroundOutcome.nothingRunning;
      }
      final next = await _act(command, timer);
      await _redraw(next);
      return TimerBackgroundOutcome.done;
    } on ApiFailure catch (error) {
      if (error.statusCode == 401) return TimerBackgroundOutcome.signedOut;
      return TimerBackgroundOutcome.failed;
    } catch (error) {
      debugPrint('Background timer action failed: $error');
      return TimerBackgroundOutcome.failed;
    }
  }

  /// Whether the device stays locked for [unlockGrace].
  ///
  /// The Quick Settings tile asks for the unlock itself (`unlockAndRun`) and
  /// sends the command the moment the PIN is accepted, while the keyguard is
  /// still on its way out. Without the grace that tap was refused as locked.
  /// A device that is really locked is still locked when the grace is over.
  Future<bool> _stillLocked() async {
    final until = DateTime.now().add(unlockGrace);
    while (await lock.isLocked()) {
      if (!DateTime.now().isBefore(until)) return true;
      await Future<void>.delayed(unlockPoll);
    }
    return false;
  }

  /// The timer that runs after [command], or null when none does.
  Future<RunningTimer?> _act(
    TimerBackgroundCommand command,
    RunningTimer timer,
  ) async {
    switch (command) {
      case TimerBackgroundCommand.stop:
        await time.stopTimer(timerId: timer.id, endedAt: DateTime.now());
        return null;
      case TimerBackgroundCommand.advancePhase:
        if (timer.mode != TimerMode.pomodoro) return timer;
        return time.advancePhase(timerId: timer.id);
    }
  }

  Future<void> _redraw(RunningTimer? timer) async {
    final state = deriveTimerSurfaceState(
      timer,
      snapshot.prefs,
      gated: false,
      texts: snapshot.texts,
    );
    final host = _BackgroundHost();
    for (final surface in surfaces) {
      try {
        await surface.init(host);
        await surface.apply(state);
      } catch (error) {
        // One surface that cannot draw here must not keep the others from it.
        debugPrint('Background redraw of ${surface.id} failed: $error');
      }
    }
  }
}

/// A host that does nothing: a background isolate has no screen to open and
/// no app to ask. Its surfaces only draw.
class _BackgroundHost implements TimerSurfaceHost {
  @override
  bool get isForeground => false;

  @override
  Future<void> end() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> advancePhase() async {}

  @override
  void openFocus() {}

  @override
  void openRoute(String route) {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> quit() async {}
}

/// Builds the action from what is on this device and runs [command]. Signed
/// out, without the app's switches or without a server, it does nothing.
Future<TimerBackgroundOutcome> runTimerBackgroundCommand(
  TimerBackgroundCommand command,
) async {
  final snapshot = await const TimerSurfaceSnapshotStore().read();
  if (snapshot == null) return TimerBackgroundOutcome.signedOut;
  final storage = await AppStorage.create();
  if (storage.serverUrl == null || storage.accessToken == null) {
    return TimerBackgroundOutcome.signedOut;
  }
  final platform = SurfacePlatform.current;
  final notifications = LocalNotificationsSurface(
    platform,
    resetOnStart: false,
    backgroundResponse: timerNotificationBackgroundResponse,
  );
  final action = TimerBackgroundAction(
    time: TimeRepository(ApiClient(storage)),
    snapshot: snapshot,
    surfaces: [
      if (platform == SurfacePlatform.android) notifications,
      if (platform == SurfacePlatform.ios) LiveActivitySurface(),
      // Without the action: registering it again from here would make
      // home_widget start a second background engine in the middle of this
      // one's run, and the widget would never hear that the button finished.
      HomeWidgetSurface(platform),
    ],
  );
  final outcome = await action.run(command);
  final hint = switch (outcome) {
    TimerBackgroundOutcome.locked => snapshot.texts.unlockToAct,
    TimerBackgroundOutcome.signedOut ||
    TimerBackgroundOutcome.failed => snapshot.texts.actionFailed,
    _ => '',
  };
  await notifications.showActionHint(hint, snapshot.texts);
  return outcome;
}

/// The entry point of a widget button and of the Quick Settings tile: the
/// `home_widget` background callback, with a `hinata://timer/<command>` link.
@pragma('vm:entry-point')
Future<void> timerSurfaceBackgroundAction(Uri? uri) async {
  DartPluginRegistrant.ensureInitialized();
  final command = TimerBackgroundCommand.fromUri(uri);
  if (command == null) return;
  await runTimerBackgroundCommand(command);
}

/// The entry point of a notification button pressed while the app is not in
/// front. Acts only on a response that carries this installation's secret,
/// like the running app does.
@pragma('vm:entry-point')
Future<void> timerNotificationBackgroundResponse(
  NotificationResponse response,
) async {
  DartPluginRegistrant.ensureInitialized();
  final command = TimerBackgroundCommand.fromNotificationAction(
    response.actionId,
  );
  if (command == null) return;
  final secret = await installationActionToken();
  if (response.payload != '${TimerNotificationAction.route}#$secret') return;
  await runTimerBackgroundCommand(command);
}
