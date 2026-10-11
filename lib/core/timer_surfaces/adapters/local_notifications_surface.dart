import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../models/time_models.dart';
import '../phase_end_schedule.dart';
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// Action ids a notification carries back into the running app.
abstract final class TimerNotificationAction {
  static const stop = 'timer.stop';
  static const advance = 'timer.advance';

  /// The route a tap opens. Only a route: a link can never stop a timer.
  static const route = '/time/focus';
}

/// The end of an interval, and on Android the running timer, as system
/// notifications (Android, iOS, macOS, Linux).
///
/// The end is planned ahead with `zonedSchedule` where the platform can, so it
/// arrives with the app closed. Linux cannot plan ahead, so there it is shown
/// when the app notices the end while it is in the background.
class LocalNotificationsSurface extends TimerSurface {
  LocalNotificationsSurface(
    this.platform, {
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? clock,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _clock = clock ?? DateTime.now;

  final SurfacePlatform platform;
  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _clock;
  final PhaseEndPlanner _planner = PhaseEndPlanner();

  /// The ongoing notification of a running timer (Android).
  static const int runningId = 7101;

  static const String _endChannel = 'timer_end';
  static const String _runningChannel = 'timer_running';

  /// One set of buttons per kind of stretch, because a notification's
  /// buttons are its category's: a countdown only stops, a work interval offers
  /// the break, a break offers going back to work.
  static const String _countdownCategory = 'timer_countdown';
  static const String _workCategory = 'timer_work';
  static const String _breakCategory = 'timer_break';

  static String _categoryOf(TimerSurfaceState state) {
    if (state.mode != TimerMode.pomodoro) return _countdownCategory;
    return state.isBreak ? _breakCategory : _workCategory;
  }

  TimerSurfaceHost? _host;
  bool _showsRunning = false;

  /// The words the plugin was initialised with; null before the first time.
  /// Apple platforms register the action buttons at initialisation, so a new
  /// language initialises again.
  TimerSurfaceTexts? _readyWith;
  bool get _ready => _readyWith != null;
  bool get _darwin =>
      platform == SurfacePlatform.ios || platform == SurfacePlatform.macos;

  @override
  String get id => 'local-notifications';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  bool get _android => platform == SurfacePlatform.android;
  bool get _linux => platform == SurfacePlatform.linux;

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _host = host;
  }

  /// Initialises the plugin, without asking for any permission: that is asked
  /// when the person switches a notification on, never at start.
  Future<void> _ensureReady(TimerSurfaceTexts texts) async {
    if (_ready && (!_darwin || texts == _readyWith)) return;
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _countdownCategory,
          actions: [_darwinAction(TimerNotificationAction.stop, texts.stop)],
        ),
        DarwinNotificationCategory(
          _workCategory,
          actions: [
            _darwinAction(TimerNotificationAction.stop, texts.stop),
            _darwinAction(TimerNotificationAction.advance, texts.takeBreak),
          ],
        ),
        DarwinNotificationCategory(
          _breakCategory,
          actions: [
            _darwinAction(TimerNotificationAction.stop, texts.stop),
            _darwinAction(TimerNotificationAction.advance, texts.resume),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_stat_timer'),
        iOS: darwin,
        macOS: darwin,
        linux: LinuxInitializationSettings(defaultActionName: texts.appName),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    final first = !_ready;
    _readyWith = texts;
    if (first) {
      // Whatever an earlier run left planned or posted belongs to a state this
      // run has not seen (a timer stopped elsewhere, another account). Start
      // from nothing and plan again from the state at hand.
      await _plugin.cancel(id: PhaseEndSchedule.notificationId);
      await _plugin.cancel(id: runningId);
    }
  }

  static DarwinNotificationAction _darwinAction(String id, String title) =>
      DarwinNotificationAction.plain(
        id,
        title,
        options: {DarwinNotificationActionOption.foreground},
      );

  /// A tap or an action from a notification, in the running app.
  void _onResponse(NotificationResponse response) {
    final host = _host;
    if (host == null) return;
    switch (response.actionId) {
      case TimerNotificationAction.stop:
        host.end();
      case TimerNotificationAction.advance:
        host.advancePhase();
      default:
        host.openFocus();
    }
  }

  /// Acts on a tap or an action of ours that launched the app, the way the
  /// running app would have: "Stop" stops, "Take a break" turns the phase, a
  /// tap opens the focus screen (the router parks it until the app is ready).
  Future<void> handleLaunch(TimerSurfaceTexts texts) async {
    await _ensureReady(texts);
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || response == null) return;
    final id = response.id;
    if (id != PhaseEndSchedule.notificationId && id != runningId) return;
    _onResponse(response);
  }

  @override
  Future<void> apply(TimerSurfaceState state) => _quietly(() async {
    await _ensureReady(state.texts);
    await _applyPhaseEnd(state);
    if (_android) await _applyRunning(state);
  });

  /// The system says no (notifications not allowed, a plugin missing on this
  /// desktop): nothing of that reaches the person, and nothing is held against
  /// this surface either. The plan is forgotten, so the next state tries again
  /// once the person allows notifications in the system settings.
  Future<void> _quietly(Future<void> Function() run) async {
    try {
      await run();
    } on PlatformException catch (error) {
      _planner.reset();
      _showsRunning = false;
      debugPrint('Timer notification not possible: ${error.code}');
    } on MissingPluginException {
      _planner.reset();
    }
  }

  Future<void> _applyPhaseEnd(TimerSurfaceState state) async {
    // Linux plans nothing ahead; its notification is shown in [phaseEnded].
    if (_linux) return;
    switch (_planner.next(state, _clock())) {
      case PhaseEndKeep():
        return;
      case PhaseEndCancel():
        await _plugin.cancel(id: PhaseEndSchedule.notificationId);
      case PhaseEndPlan(:final at):
        await _plugin.zonedSchedule(
          id: PhaseEndSchedule.notificationId,
          scheduledDate: tz.TZDateTime.from(at, tz.UTC),
          title: state.texts.appName,
          body: state.endText,
          payload: TimerNotificationAction.route,
          notificationDetails: _endDetails(state),
          androidScheduleMode: await _scheduleMode(),
        );
    }
  }

  /// Exact where the person allowed it, otherwise inexact: a few minutes late
  /// is better than not at all, and `USE_EXACT_ALARM` is not ours to claim.
  Future<AndroidScheduleMode> _scheduleMode() async {
    if (!_android) return AndroidScheduleMode.exactAllowWhileIdle;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  NotificationDetails _endDetails(TimerSurfaceState state) {
    final pomodoro = state.mode == TimerMode.pomodoro;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _endChannel,
        state.texts.appName,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.private,
        timeoutAfter: PhaseEndSchedule.expiry.inMilliseconds,
        autoCancel: true,
        actions: [
          AndroidNotificationAction(
            TimerNotificationAction.stop,
            state.texts.stop,
            showsUserInterface: true,
          ),
          if (pomodoro)
            AndroidNotificationAction(
              TimerNotificationAction.advance,
              state.isBreak ? state.texts.resume : state.texts.takeBreak,
              showsUserInterface: true,
            ),
        ],
      ),
      iOS: DarwinNotificationDetails(categoryIdentifier: _categoryOf(state)),
      macOS: DarwinNotificationDetails(categoryIdentifier: _categoryOf(state)),
      linux: LinuxNotificationDetails(
        timeout: LinuxNotificationTimeout.fromDuration(PhaseEndSchedule.expiry),
        category: LinuxNotificationCategory.presence,
      ),
    );
  }

  /// The running timer as a quiet ongoing notification whose clock the system
  /// runs (`usesChronometer`), so nothing here posts once a second.
  Future<void> _applyRunning(TimerSurfaceState state) async {
    final startedAt = state.startedAt;
    // The copy ends by itself at [TimerSurfaceState.validUntil], even if this
    // process never runs again to take it down.
    final left = state.validUntil?.difference(_clock().toUtc());
    if (!state.running ||
        !state.runningSurface ||
        startedAt == null ||
        (left != null && left <= Duration.zero)) {
      if (_showsRunning) await _plugin.cancel(id: runningId);
      _showsRunning = false;
      return;
    }
    final countsDown = state.endsAt != null;
    final pomodoro = state.mode == TimerMode.pomodoro;
    // Locked, the screen shows the app name and nothing else, unless the person
    // switched details on for the lock screen too.
    final lockScreen = state.lockScreenLabel != null;
    await _plugin.show(
      id: runningId,
      title: state.isBreak ? state.texts.onBreak : state.texts.running,
      body: lockScreen ? state.lockScreenLabel : state.label,
      payload: TimerNotificationAction.route,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _runningChannel,
          state.texts.running,
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          silent: true,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          timeoutAfter: left?.inMilliseconds,
          usesChronometer: true,
          chronometerCountDown: countsDown,
          when: (countsDown ? state.endsAt! : startedAt).millisecondsSinceEpoch,
          category: AndroidNotificationCategory.stopwatch,
          visibility: lockScreen
              ? NotificationVisibility.public
              : NotificationVisibility.private,
          actions: [
            AndroidNotificationAction(
              TimerNotificationAction.stop,
              state.texts.stop,
              showsUserInterface: true,
            ),
            if (pomodoro)
              AndroidNotificationAction(
                TimerNotificationAction.advance,
                state.isBreak ? state.texts.resume : state.texts.takeBreak,
                showsUserInterface: true,
              ),
          ],
        ),
      ),
    );
    _showsRunning = true;
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) => _quietly(() => _phaseEnded(state, foreground: foreground));

  Future<void> _phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {
    if (!_ready) return;
    if (foreground) {
      // The toast says it; a second announcement from the system is noise.
      await _plugin.cancel(id: PhaseEndSchedule.notificationId);
      _planner.reset();
      return;
    }
    if (_linux && state.phaseEndNotification) {
      await _plugin.show(
        id: PhaseEndSchedule.notificationId,
        title: state.texts.appName,
        body: state.endText,
        payload: TimerNotificationAction.route,
        notificationDetails: _endDetails(state),
      );
    }
  }

  @override
  Future<void> clear() => _quietly(_clear);

  Future<void> _clear() async {
    // Also before anything was applied: a cold start signed out is exactly the
    // run in which an earlier one's notification is still planned.
    await _ensureReady(_readyWith ?? TimerSurfaceTexts.empty);
    _planner.reset();
    _showsRunning = false;
    await _plugin.cancel(id: PhaseEndSchedule.notificationId);
    await _plugin.cancel(id: runningId);
  }

  @override
  Future<void> dispose() async {}
}

/// Asking for the system's permission, when the person switches something on.
///
/// The answer is never stored or sent: it is the system's to keep.
class LocalNotificationPermissions {
  LocalNotificationPermissions(
    this.platform, {
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final SurfacePlatform platform;
  final FlutterLocalNotificationsPlugin _plugin;

  /// Asks to show notifications; true when they may be shown.
  Future<bool> request() async {
    try {
      switch (platform) {
        case SurfacePlatform.android:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.requestNotificationsPermission() ??
              false;
        case SurfacePlatform.ios:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, sound: true) ??
              false;
        case SurfacePlatform.macos:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, sound: true) ??
              false;
        // Neither asks: Windows toasts and Linux desktop notifications are
        // switched off in the system's own settings, not granted to an app.
        case SurfacePlatform.linux || SurfacePlatform.windows:
          return true;
        default:
          return false;
      }
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Notification permission unavailable: ${error.code}');
      return false;
    }
  }

  /// Whether exact alarms are allowed (Android 12 and later).
  Future<bool> canScheduleExact() async {
    if (platform != SurfacePlatform.android) return true;
    try {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.canScheduleExactNotifications() ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system page for exact alarms; the answer comes on return.
  Future<void> requestExact() async {
    if (platform != SurfacePlatform.android) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestExactAlarmsPermission();
    } on PlatformException {
      // Nothing to do; inexact remains.
    }
  }
}
