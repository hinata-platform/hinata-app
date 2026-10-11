import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/router/app_router.dart' show rootNavigatorKey;
import '../../core/timer_surfaces/adapters/keep_running_surface.dart';
import '../../core/timer_surfaces/adapters/local_notifications_surface.dart';
import '../../core/timer_surfaces/build_timer_surfaces.dart';
import '../../core/timer_surfaces/surface_platform.dart';
import '../../core/timer_surfaces/timer_surface.dart';
import '../../core/timer_surfaces/timer_surface_clear_signal.dart';
import '../../core/timer_surfaces/timer_surface_coordinator.dart';
import '../../core/timer_surfaces/timer_surface_prefs.dart';
import '../../core/timer_surfaces/timer_surface_state.dart';
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
    this.surfaces,
  });

  final String appTitle;

  /// Opens an in-app route; the router parks it until the app is ready.
  final void Function(String route) openRoute;

  final Widget child;

  /// "Delete local copies now" from the settings.
  final TimerSurfaceClearSignal? clearSignal;

  /// The surfaces to drive; the platform's own when null (tests hand fakes).
  final List<TimerSurface>? surfaces;

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
        ),
  );

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
    _enqueue(() => _coordinator.init(this));
  }

  /// Clears every surface now. They stay cleared, also after the app comes
  /// back to the front, until the timer itself changes: that is what the
  /// person expects after deleting a copy of it.
  void _clearNow() {
    _cleared = _derive();
    _enqueue(_coordinator.clearAll);
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
    unawaited(_coordinator.dispose());
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
  );

  TimerSurfaceState _derive() => deriveTimerSurfaceState(
    context.read<TimerCubit>().state.timer,
    context.read<TimerSurfacePrefsCubit>().state,
    gated: _gated,
    texts: _texts(),
  );

  /// Gated (signed out, module off) every surface is cleared. Otherwise even
  /// "no timer" is a state the surfaces draw: a countdown stops itself the
  /// moment it ends, and clearing then would also wipe the title's short flash
  /// that says so.
  void _sync() {
    if (!mounted) return;
    if (_gated) {
      _enqueue(_coordinator.clearAll);
      return;
    }
    final state = _derive();
    if (state == _cleared) return;
    _cleared = null;
    _enqueue(() => _coordinator.apply(state));
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
    if (previous.timer != current.timer) {
      _sync();
      _offerIntro(previous.timer, current.timer);
    }
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
