import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/storage/app_storage.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/router/app_router.dart' show rootNavigatorKey;
import '../../core/timer_surfaces/adapters/alarm_kit_surface.dart';
import '../../core/timer_surfaces/adapters/global_hotkeys_surface.dart';
import '../../core/timer_surfaces/adapters/keep_running_surface.dart';
import '../../core/timer_surfaces/adapters/local_notifications_surface.dart';
import '../../core/timer_surfaces/background/timer_surface_snapshot.dart';
import '../../core/timer_surfaces/build_timer_surfaces.dart';
import '../../core/timer_actions/api_live_activity_push_registry.dart';
import '../../core/timer_surfaces/live_activity_push_registry.dart';
import '../../core/timer_actions/intent_project_snapshot.dart';
import '../../core/timer_actions/timer_background_action.dart';
import '../../core/timer_surfaces/quick_settings_tile.dart';
import '../../core/timer_surfaces/surface_platform.dart';
import '../../core/timer_surfaces/timer_surface.dart';
import '../../core/timer_surfaces/timer_surface_clear_signal.dart';
import '../../core/timer_surfaces/timer_surface_coordinator.dart';
import '../../core/timer_surfaces/timer_surface_prefs.dart';
import '../../core/timer_surfaces/timer_surface_state.dart';
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'timer_surfaces_intro_sheet.dart';

/// Keeps the timer outside the app in step with the timer inside it.
///
/// Always mounted, above the router, and the surfaces are gated instead of the
/// widget: the first frame signed out, with the module off or before the person
/// agreed is exactly the moment a notification planned in an earlier run has
/// to go, and a host that only existed while everything was fine would never
/// see that moment.
class TimerSurfacesHost extends StatefulWidget {
  const TimerSurfacesHost({
    super.key,
    required this.appTitle,
    required this.openRoute,
    required this.child,
    this.clearSignal,
    this.hotkeys,
    this.liveActivityRegistry,
    this.surfaces,
    this.intentProjects,
    this.snapshots = const TimerSurfaceSnapshotStore(),
    this.tileOffer = const QuickSettingsTileOffer(),
  });

  final String appTitle;

  /// Opens an in-app route; the router parks it until the app is ready.
  final void Function(String route) openRoute;

  final Widget child;

  /// "Delete local copies now" from the settings.
  final TimerSurfaceClearSignal? clearSignal;

  /// What the settings see of the system-wide shortcuts.
  final HotkeyStatus? hotkeys;

  /// Where Live Activity tokens are registered; the app's own when null.
  final LiveActivityPushRegistry? liveActivityRegistry;

  /// The surfaces to drive; the platform's own when null (tests hand fakes).
  final List<TimerSurface>? surfaces;

  /// The projects for Siri and Shortcuts (iOS); the app's own when null.
  final IntentProjectSnapshot? intentProjects;

  /// Where the switches and words for a background action are kept.
  final TimerSurfaceSnapshotStore snapshots;

  /// The one offer of the Quick Settings tile (Android).
  final QuickSettingsTileOffer tileOffer;

  @override
  State<TimerSurfacesHost> createState() => _TimerSurfacesHostState();
}

class _TimerSurfacesHostState extends State<TimerSurfacesHost>
    with WidgetsBindingObserver
    implements TimerSurfaceHost {
  late final TimerSurfaceCoordinator _coordinator = TimerSurfaceCoordinator(
    widget.surfaces ??
        buildTimerSurfaces(
          SurfacePlatform.current,
          appTitle: () => _appTitle,
          flashText: () => _flashText,
          hotkeys: widget.hotkeys ?? (_ownHotkeys = HotkeyStatus()),
          liveActivityRegistry:
              widget.liveActivityRegistry ??
              ApiLiveActivityPushRegistry(context.read<ApiClient>()),
          background: const TimerBackgroundCallbacks(
            notification: timerNotificationBackgroundResponse,
            widget: timerSurfaceBackgroundAction,
          ),
          alarms: _alarms,
          alarmsMayClear: () => _clearRequested || _signedOutForGood,
        ),
  );

  /// Whether alarms can ring the end of an interval (iOS 26, HIN-106).
  late final AlarmModeStatus? _alarms =
      SurfacePlatform.current == SurfacePlatform.ios ? AlarmModeStatus() : null;

  /// "Delete now" asked for the clear that is queued; only that one, and a
  /// real sign-out, take the alarms away.
  bool _clearRequested = false;

  /// Whether the system's limit was already said in this run.
  bool _limitSaid = false;

  /// The projects Siri and Shortcuts offer, on iOS only (HIN-105).
  late final IntentProjectSnapshot? _intentProjects =
      widget.intentProjects ??
      (SurfacePlatform.current == SurfacePlatform.ios
          ? IntentProjectSnapshot(context.read<ProjectRepository>())
          : null);

  /// A status of our own where nobody handed one in (a test); disposed here.
  HotkeyStatus? _ownHotkeys;

  late String _appTitle = widget.appTitle;
  String _flashText = '';
  bool _foreground = true;
  bool _launchChecked = false;

  /// Serialises the work on the surfaces: a state and the next one must not
  /// be drawn out of order, or a cancelled notification is planned again.
  Future<void> _queue = Future.value();

  @override
  bool get isForeground => _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.clearSignal?.addListener(_clearNow);
    _alarms?.addListener(_onAlarms);
    _enqueue(() => _coordinator.init(this));
  }

  /// The system's answer about alarms changed: the notification and the Live
  /// Activity take over again, or step back for the alarm.
  void _onAlarms() {
    final alarms = _alarms;
    if (alarms == null || !mounted) return;
    if (alarms.limitReached && !_limitSaid) {
      _limitSaid = true;
      final navigatorContext = rootNavigatorKey.currentContext;
      if (navigatorContext != null && navigatorContext.mounted) {
        showGlassToast(
          navigatorContext,
          navigatorContext.t('account.timerSurfaces.alarmLimit'),
          kind: GlassToastKind.info,
        );
      }
    }
    _coordinator.invalidate();
    _sync();
  }

  /// Clears every surface now. They stay cleared, also after the app comes
  /// back to the front, until the timer itself changes: that is what the
  /// person expects after deleting a copy of it.
  void _clearNow() {
    _cleared = _derive();
    unawaited(_intentProjects?.clear());
    _clearRequested = true;
    _enqueue(() async {
      try {
        await _coordinator.clearAll();
      } finally {
        _clearRequested = false;
      }
    });
  }

  /// The state "Delete now" took down; not drawn again while it holds.
  TimerSurfaceState? _cleared;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The language decides every word on a surface; [_sync] compares texts.
    _flashText = context.t('time.signal.titleFlash');
    _sync();
    _checkLaunch();
  }

  @override
  void didUpdateWidget(TimerSurfacesHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appTitle != widget.appTitle) {
      _appTitle = widget.appTitle;
      _coordinator.invalidate();
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      // The system may have dropped what was posted while the app was away;
      // draw the current state again in full.
      _coordinator.invalidate();
      _sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.clearSignal?.removeListener(_clearNow);
    _alarms
      ?..removeListener(_onAlarms)
      ..dispose();
    unawaited(
      _coordinator.dispose().whenComplete(() => _ownHotkeys?.dispose()),
    );
    super.dispose();
  }

  void _enqueue(Future<void> Function() work) {
    _queue = _queue.then((_) => work()).catchError((Object _) {});
  }

  bool get _gated {
    final signedIn =
        context.read<AuthBloc>().state.status == AuthStatus.authenticated;
    final module =
        context.read<AppConfigBloc>().state.meta?.advancedTimeTracking ?? false;
    return !signedIn || !module;
  }

  /// Gated for good: signed out, or the module known to be off. The first
  /// frames of a launch are gated as well while the session is read back, and
  /// iOS starts the app like that for Siri or a control (HIN-105): the
  /// snapshot the background action reads in that very moment must survive.
  bool get _signedOutForGood {
    final status = context.read<AuthBloc>().state.status;
    final meta = context.read<AppConfigBloc>().state.meta;
    return status == AuthStatus.unauthenticated ||
        (meta != null && !meta.advancedTimeTracking);
  }

  /// Whose projects Siri may offer: another server or person reads them anew.
  String get _owner =>
      '${context.read<AppStorage>().serverUrl}|'
      '${context.read<AuthBloc>().state.user?.id}';

  TimerSurfaceTexts _texts() => TimerSurfaceTexts(
    appName: _appTitle,
    countdownOver: context.t('time.signal.countdown'),
    workOver: context.t('time.surface.workOver'),
    breakOver: context.t('time.signal.breakOver'),
    running: context.t('time.surface.running'),
    onBreak: context.t('time.surface.onBreak'),
    stop: context.t('time.timer.stop'),
    takeBreak: context.t('time.focus.takeBreak'),
    resume: context.t('time.focus.resume'),
    start: context.t('time.surface.menu.start'),
    nextPhase: context.t('time.surface.menu.nextPhase'),
    openFocus: context.t('time.surface.menu.openFocus'),
    showWindow: context.t('time.surface.menu.showWindow'),
    quit: context.t('time.surface.menu.quit'),
    idle: context.t('time.surface.menu.idle'),
    stopwatch: context.t('time.surface.menu.stopwatch'),
    countdown: context.t('time.surface.menu.countdown'),
    focusPhase: context.t('time.surface.menu.focusPhase'),
    breakPhase: context.t('time.surface.menu.breakPhase'),
    unlockToAct: context.t('time.surface.unlockToAct'),
    actionFailed: context.t('time.surface.actionFailed'),
    timeLabel: context.t('time.surface.timeLabel'),
    alarmTitle: context.t('time.surface.alarmTitle'),
  );

  TimerSurfaceState _derive() {
    final timer = context.read<TimerCubit>().state;
    return deriveTimerSurfaceState(
      timer.timer,
      context.read<TimerSurfacePrefsCubit>().state,
      gated: _gated,
      alarmsUsable: _alarms?.usable ?? false,
      texts: _texts(),
      confirmed: timer.confirmed,
    );
  }

  /// Gated (signed out, module off) every surface is cleared. Otherwise even
  /// "no timer" is a state the surfaces draw: a countdown stops itself the
  /// moment it ends, and clearing then would also wipe the title's short flash
  /// that says so.
  void _sync() {
    if (!mounted) return;
    if (_gated) {
      _intentProjects?.invalidate();
      if (_signedOutForGood) {
        _keepSnapshot(null);
        unawaited(_intentProjects?.clear());
      }
      _enqueue(_coordinator.clearAll);
      return;
    }
    unawaited(_intentProjects?.refresh(owner: _owner));
    _keepSnapshot(
      TimerSurfaceSnapshot(
        prefs: context.read<TimerSurfacePrefsCubit>().state,
        texts: _texts(),
      ),
    );
    final state = _derive();
    if (state == _cleared) return;
    _cleared = null;
    _enqueue(() => _coordinator.apply(state));
  }

  /// The last snapshot written, so an unchanged one is not written again.
  String? _snapshot;

  /// Keeps what a background action needs to redraw the surfaces (HIN-103):
  /// the switches and the words, and nothing while signed out.
  void _keepSnapshot(TimerSurfaceSnapshot? snapshot) {
    final encoded = snapshot?.encode() ?? '';
    if (encoded == _snapshot) return;
    _snapshot = encoded;
    unawaited(widget.snapshots.write(snapshot).catchError((Object _) {}));
  }

  /// A tap on one of our notifications that launched the app opens the focus
  /// screen once the app is ready, the way a push tap opens its route.
  void _checkLaunch() {
    if (_launchChecked) return;
    _launchChecked = true;
    final texts = _texts();
    for (final surface in _coordinator.surfaces) {
      if (surface is! LocalNotificationsSurface) continue;
      _enqueue(() => surface.handleLaunch(texts));
    }
  }

  void _onTimer(TimerState previous, TimerState current) {
    final signal = current.signal;
    if (signal != null && signal != previous.signal) {
      final state = _derive();
      _enqueue(() => _coordinator.phaseEnded(state, foreground: _foreground));
    }
    if (previous.timer != current.timer ||
        previous.confirmed != current.confirmed) {
      _sync();
      _offerIntro(previous.timer, current.timer);
      _offerTile(previous.timer, current.timer);
    }
  }

  /// The Quick Settings tile is offered once, after the first timer started
  /// here, with the app in front (Android 13 and later).
  void _offerTile(RunningTimer? before, RunningTimer? now) {
    if (before != null || now == null || _gated || !_foreground) return;
    if (SurfacePlatform.current != SurfacePlatform.android) return;
    unawaited(widget.tileOffer.offerOnce().catchError((Object _) {}));
  }

  /// The introduction comes the first time somebody starts a timer that ends
  /// by itself: the moment the question "tell me when it is over?" makes sense.
  void _offerIntro(RunningTimer? before, RunningTimer? now) {
    if (before != null || now == null || now.target == null || _gated) return;
    final prefs = context.read<TimerSurfacePrefsCubit>();
    if (prefs.state.introSeen || prefs.state.consented) return;
    if (!_coordinator.capabilities.phaseEndNotification) return;
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) return;
    unawaited(showTimerSurfacesIntro(navigatorContext, prefs: prefs));
  }

  // ── TimerSurfaceHost ─────────────────────────────────────────────────

  /// From a notification that launched the app the timer may not be read yet;
  /// then the focus screen opens, where the person stops it themselves.
  @override
  Future<void> end() async {
    final timer = context.read<TimerCubit>();
    if (timer.state.timer == null) {
      openFocus();
      return;
    }
    await timer.end();
  }

  @override
  Future<void> advancePhase() async {
    final timer = context.read<TimerCubit>();
    if (timer.state.timer == null) {
      openFocus();
      return;
    }
    await timer.advancePhase();
  }

  @override
  Future<void> start() => context.read<TimerCubit>().start();

  @override
  void openFocus() => widget.openRoute(TimerNotificationAction.route);

  @override
  Future<void> showWindow() async {
    if (!_desktop) return;
    await WindowManagerGateway.shared.show();
  }

  @override
  Future<void> quit() async {
    if (!_desktop) return;
    await _coordinator.clearAll();
    await WindowManagerGateway.shared.close();
  }

  bool get _desktop => switch (SurfacePlatform.current) {
    SurfacePlatform.macos ||
    SurfacePlatform.windows ||
    SurfacePlatform.linux => true,
    _ => false,
  };

  @override
  void openRoute(String route) => widget.openRoute(route);

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<TimerCubit, TimerState>(
        listener: (context, state) {},
        listenWhen: (previous, current) {
          if (previous.shown.inSeconds != current.shown.inSeconds) {
            _coordinator.tick(current.shown);
          }
          _onTimer(previous, current);
          return false;
        },
      ),
      BlocListener<TimerSurfacePrefsCubit, TimerSurfacePrefs>(
        listener: (context, _) => _sync(),
      ),
      BlocListener<AuthBloc, AuthState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, _) => _sync(),
      ),
      BlocListener<AppConfigBloc, AppConfigState>(
        listenWhen: (previous, current) =>
            previous.meta?.advancedTimeTracking !=
            current.meta?.advancedTimeTracking,
        listener: (context, _) => _sync(),
      ),
    ],
    child: widget.child,
  );
}
