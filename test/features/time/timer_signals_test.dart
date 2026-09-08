import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/time_preferences_cubit.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/router/app_router.dart' show rootNavigatorKey;
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/time/timer_signals.dart';

/// The end of an interval, said out loud.
///
/// This file exists because the first version of it could not have worked at
/// all: `TimerSignals` is mounted in `MaterialApp.router`'s builder — above the
/// navigator, which is the only place it can be if the focus route is to be
/// covered — and `Overlay.of` looks *upwards*, so the toast threw before the
/// chime or the title were ever reached. Nothing caught that, because every
/// other test in the suite uses a timer cubit that holds a state and never
/// ticks, so `signal` was never non-null anywhere.
///
/// So the shape here is the shape `app.dart` actually builds: the widget in a
/// router's `builder`, and a state pushed through the real cubit stream.
void main() {
  late _SignalCubit timer;
  late TimePreferencesCubit preferences;

  setUp(() {
    AppColors.brightness = Brightness.light;
    timer = _SignalCubit();
    preferences = TimePreferencesCubit(_FakeAccountRepository());
  });

  tearDown(() async {
    await timer.close();
    await preferences.close();
  });

  Future<void> pump(WidgetTester tester) {
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      routes: [GoRoute(path: '/', builder: (_, _) => const Text('a page'))],
    );
    return tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1000, 800)),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TimerCubit>.value(value: timer),
            BlocProvider<TimePreferencesCubit>.value(value: preferences),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            builder: (context, child) => TimerSignals(
              appTitle: 'Hinata',
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  RunningTimer pomodoro({required TimerPhase phase, int cyclesDone = 0}) =>
      RunningTimer(
        id: 'p1',
        startedAt: DateTime.now(),
        mode: TimerMode.pomodoro,
        pomodoro: const PomodoroConfig(),
        phase: phase,
        cyclesDone: cyclesDone,
      );

  testWidgets('a work interval ending says so, and offers the break', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    timer.announce(
      pomodoro(phase: TimerPhase.work),
      const TimerSignal(
        timerId: 'p1',
        mode: TimerMode.pomodoro,
        phase: TimerPhase.work,
        cyclesDone: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('time.signal.workOver'), findsOneWidget);
    // The offer, not the decision: whether the break starts now is the person's
    // to say, so the toast carries an action rather than turning the phase.
    expect(find.text('time.focus.takeBreak'), findsOneWidget);
  });

  testWidgets('a break ending offers the way back, not another break', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    timer.announce(
      pomodoro(phase: TimerPhase.shortBreak, cyclesDone: 1),
      const TimerSignal(
        timerId: 'p2',
        mode: TimerMode.pomodoro,
        phase: TimerPhase.shortBreak,
        cyclesDone: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('time.signal.breakOver'), findsOneWidget);
    expect(find.text('time.focus.resume'), findsOneWidget);
  });

  testWidgets('a countdown running out is said without an offer', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    timer.announce(
      null,
      const TimerSignal(timerId: 'c1', mode: TimerMode.countdown),
    );
    await tester.pumpAndSettle();

    expect(find.text('time.signal.countdown'), findsOneWidget);
    // A countdown ends itself — there is no next phase to offer.
    expect(find.text('time.focus.takeBreak'), findsNothing);
    expect(find.text('time.focus.resume'), findsNothing);
  });

  testWidgets('a failed start is said too, wherever the app happens to be', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    // The bar used to be the only listener, and it is mounted on three screens.
    // The buttons that can fail are now on a route outside the shell, on three
    // keyboard shortcuts and in the command palette.
    timer.fail('A timer is already running');
    await tester.pumpAndSettle();

    expect(find.text('A timer is already running'), findsOneWidget);
  });

  testWidgets('nothing is said twice for one interval', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    const signal = TimerSignal(timerId: 'c1', mode: TimerMode.countdown);
    timer.announce(null, signal);
    await tester.pumpAndSettle();
    expect(find.text('time.signal.countdown'), findsOneWidget);

    // A state that carries no signal must not re-show the last one. Waited out
    // rather than checked immediately: the toast is on screen for seconds, so
    // "still there" and "said again" look identical until it has gone.
    timer.quiet();
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('time.signal.countdown'), findsNothing);
  });
}

/// A timer cubit the test pushes states through.
///
/// The real one is not usable here — its ticker emits once a second, and
/// `pumpAndSettle` advances the clock until it does, for ever. What matters for
/// this file is that the states arrive through a real stream, which they do.
class _SignalCubit extends Cubit<TimerState> implements TimerCubit {
  _SignalCubit() : super(const TimerState());

  void announce(RunningTimer? running, TimerSignal signal) =>
      emit(TimerState(timer: running, signal: signal));

  void fail(String message) => emit(TimerState(errorMessage: message));

  void quiet() => emit(const TimerState());

  @override
  Future<void> advancePhase() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAccountRepository implements AccountRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
