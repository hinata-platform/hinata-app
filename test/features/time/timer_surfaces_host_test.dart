import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_clear_signal.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/features/time/timer_surfaces_host.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart';

/// The host that keeps the surfaces outside the app in step with the timer.
///
/// Every cubit here holds the state it is given and never ticks: a real timer
/// ticks once a second and a widget test would never settle.
void main() {
  late RecordingSurface surface;
  late _HeldTimerCubit timer;
  late TimerSurfacePrefsCubit prefs;
  late _HeldAuthBloc auth;
  late _HeldConfigBloc config;
  late TimerSurfaceClearSignal clear;
  final routes = <String>[];

  // Relative to now: the host shows nothing of a timer older than a day.
  final startedAt = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
  final running = TimerState(
    timer: RunningTimer(
      id: 'timer-1',
      startedAt: startedAt,
      description: 'Client report',
      mode: TimerMode.countdown,
      plannedMinutes: 25,
    ),
  );

  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    surface = RecordingSurface('fake');
    timer = _HeldTimerCubit(running);
    prefs = TimerSurfacePrefsCubit(storageId: 'surfaces#test')
      ..consent(TimerSurfacePrefs.suggested);
    auth = _HeldAuthBloc(AuthStatus.authenticated);
    config = _HeldConfigBloc(advanced: true);
    clear = TimerSurfaceClearSignal();
    routes.clear();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TimerCubit>.value(value: timer),
          BlocProvider<TimerSurfacePrefsCubit>.value(value: prefs),
          BlocProvider<AuthBloc>.value(value: auth),
          BlocProvider<AppConfigBloc>.value(value: config),
        ],
        child: MaterialApp(
          home: TimerSurfacesHost(
            appTitle: 'Hinata',
            openRoute: routes.add,
            clearSignal: clear,
            surfaces: [surface],
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'a running timer reaches the surface, generic and without details',
    (tester) async {
      await pump(tester);

      final state = surface.applied.last;
      expect(state.running, isTrue);
      expect(state.phaseEndNotification, isTrue);
      expect(state.label, isNull);
      expect(state.endsAt, startedAt.add(const Duration(minutes: 25)));
    },
  );

  testWidgets('a cold start signed out clears everything and draws nothing', (
    tester,
  ) async {
    auth = _HeldAuthBloc(AuthStatus.unauthenticated);
    await pump(tester);

    expect(surface.clears, greaterThan(0));
    expect(surface.applied, isEmpty);
  });

  testWidgets('with the module off nothing is drawn', (tester) async {
    config = _HeldConfigBloc(advanced: false);
    await pump(tester);

    expect(surface.clears, greaterThan(0));
    expect(surface.applied, isEmpty);
  });

  testWidgets(
    'before the introduction is confirmed only an empty state goes out',
    (tester) async {
      prefs.update(const TimerSurfacePrefs());
      await pump(tester);

      final state = surface.applied.last;
      expect(state.phaseEndNotification, isFalse);
      expect(state.runningSurface, isFalse);
    },
  );

  testWidgets('signing out clears every surface', (tester) async {
    await pump(tester);
    final before = surface.clears;

    auth.hold(AuthStatus.unauthenticated);
    await tester.pump();
    await tester.pump();

    expect(surface.clears, greaterThan(before));
  });

  testWidgets('the end of an interval in front is reported as in front', (
    tester,
  ) async {
    await pump(tester);

    timer.hold(
      running.copyWith(
        signal: const TimerSignal(
          timerId: 'timer-1',
          mode: TimerMode.countdown,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(surface.ended, [true]);
  });

  testWidgets(
    'a timer that ends while signed in is drawn as idle, not cleared',
    (tester) async {
      // A countdown stops itself the moment it ends; clearing then would wipe
      // the title's flash that announces exactly that.
      await pump(tester);
      final clearsBefore = surface.clears;

      timer.hold(const TimerState());
      await tester.pump();
      await tester.pump();

      expect(surface.clears, clearsBefore);
      expect(surface.applied.last.running, isFalse);
    },
  );

  testWidgets('deleting local copies clears the surfaces', (tester) async {
    await pump(tester);
    final before = surface.clears;

    clear.request();
    await tester.pump();
    await tester.pump();

    expect(surface.clears, before + 1);
  });

  testWidgets('deleted copies stay deleted when the app comes back', (
    tester,
  ) async {
    await pump(tester);
    clear.request();
    await tester.pump();
    final applied = surface.applied.length;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(surface.applied.length, applied);
  });

  testWidgets('a surface opens the focus screen as a route', (tester) async {
    await pump(tester);

    surface.host!.openFocus();

    expect(routes, ['/time/focus']);
  });
}

class _HeldTimerCubit extends Cubit<TimerState> implements TimerCubit {
  _HeldTimerCubit(super.initialState);

  void hold(TimerState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _HeldAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _HeldAuthBloc(AuthStatus status) : super(AuthState(status: status));

  void hold(AuthStatus status) => emit(AuthState(status: status));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _HeldConfigBloc extends Bloc<AppConfigEvent, AppConfigState>
    implements AppConfigBloc {
  _HeldConfigBloc({required bool advanced})
    : super(
        AppConfigState(
          status: AppConfigStatus.ready,
          meta: ServerMeta(
            serverVersion: '1',
            minAppVersion: '1',
            setupCompleted: true,
            featureFlags: {PlatformFlags.advancedTimeTracking: advanced},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
