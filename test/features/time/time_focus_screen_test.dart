import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/time_preferences_cubit.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/shortcuts/app_shortcuts.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/time/time_focus_screen.dart';

/// The focus view: one screen, one timer, and a way out.
///
/// What is worth pinning here is the behaviour that is *different* from the
/// timer bar, because everything else is the same cubit: it counts down where
/// there is a target, it never offers to file a break, and Escape leaves —
/// which only works because the screen is a route of its own with its own
/// registered shortcut.
void main() {
  late _FakeTimeRepository time;
  late _FakeTimerCubit timer;
  late TimePreferencesCubit preferences;
  late AppShortcutRegistry registry;
  late List<String> went;

  setUp(() {
    AppColors.brightness = Brightness.light;
    time = _FakeTimeRepository();
    // A fake, not the real cubit: this file is about what the screen draws and
    // offers. The cubit's own behaviour — counting, signalling, turning a phase
    // — is pinned next to the cubit, where a once-a-second ticker does not stop
    // a widget test from ever settling.
    timer = _FakeTimerCubit();
    preferences = TimePreferencesCubit(_FakeAccountRepository());
    registry = AppShortcutRegistry();
    went = [];
  });

  tearDown(() async {
    await preferences.close();
  });

  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pump(WidgetTester tester, {Size size = const Size(900, 800)}) {
    final router = GoRouter(
      navigatorKey: navigatorKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MultiRepositoryProvider(
            providers: [
              RepositoryProvider<TimeRepository>.value(value: time),
              RepositoryProvider<AccountRepository>.value(
                value: _FakeAccountRepository(),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<TimerCubit>.value(value: timer),
                BlocProvider<TimePreferencesCubit>.value(value: preferences),
              ],
              child: ShortcutScope(
                registry: registry,
                child: const TimeFocusScreen(),
              ),
            ),
          ),
        ),
        GoRoute(path: '/time', builder: (_, _) => const Text('the list')),
      ],
    );
    router.routerDelegate.addListener(() {
      went.add(router.state.matchedLocation);
    });
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          // The dispatcher lives above the router in the app, because the focus
          // route is outside the shell. Here too, or the key would reach
          // nothing and the test would be about a tree the app never builds.
          builder: (context, child) => ShortcutHost(
            registry: registry,
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  testWidgets('with nothing running it offers to start, and says so', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('time.focus.idle'), findsOneWidget);
    expect(find.text('time.timer.start'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    // The mode is chosen before a run, so all three are on offer.
    expect(find.text('time.mode.pomodoro'), findsOneWidget);
  });

  testWidgets('a countdown shows what is left, not how long it has run', (
    tester,
  ) async {
    timer.show(
      RunningTimer(
        id: 'c1',
        startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        mode: TimerMode.countdown,
        plannedMinutes: 25,
      ),
    );
    await pump(tester);
    await tester.pumpAndSettle();

    // Twenty minutes left, give or take the second the test itself took: the
    // readout is against the real clock, and pinning it to one string would be
    // a test that fails at a second boundary rather than on a regression.
    final readouts = tester
        .widgetList<Text>(find.byType(Text))
        .map((each) => each.data)
        .whereType<String>();
    expect(readouts, anyOf(contains('20:00'), contains('19:59')));
    expect(find.text('5:00'), findsNothing, reason: 'that is the elapsed time');
  });

  testWidgets('a break is ended, never stopped into an entry', (tester) async {
    timer.show(
      RunningTimer(
        id: 'p2',
        startedAt: DateTime.now(),
        mode: TimerMode.pomodoro,
        pomodoro: const PomodoroConfig(),
        phase: TimerPhase.shortBreak,
        cyclesDone: 1,
      ),
    );
    await pump(tester);
    await tester.pumpAndSettle();

    // The server refuses a stop on a break outright — booked time is worked
    // time. The screen must never be the thing that asks for one.
    expect(find.text('time.timer.stop'), findsNothing);
    expect(find.text('time.focus.endSession'), findsOneWidget);
    expect(find.text('time.focus.resume'), findsOneWidget);
    expect(find.text('time.phase.shortBreak'), findsOneWidget);
    // The ticker outlives the widget tree otherwise, and the harness calls
    // that a leak — rightly.
  });

  testWidgets('a work phase offers the break, and counts the set out', (
    tester,
  ) async {
    timer.show(
      RunningTimer(
        id: 'p3',
        startedAt: DateTime.now(),
        mode: TimerMode.pomodoro,
        pomodoro: const PomodoroConfig(cycles: 4),
        phase: TimerPhase.work,
        cyclesDone: 2,
      ),
    );
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('time.focus.takeBreak'), findsOneWidget);
    expect(find.text('time.timer.stop'), findsOneWidget);
    expect(find.text('time.phase.work'), findsOneWidget);
  });

  testWidgets('Escape leaves, and the shortcut goes with the screen', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(
      registry.all.map((each) => each.id),
      contains('focus.leave'),
      reason: 'the screen registers Escape while it is mounted',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Nothing to pop — a deep link into the focus view has nothing behind it —
    // so it lands on the module's own page rather than on the dashboard.
    expect(went.last, '/time');
    expect(
      registry.all.map((each) => each.id),
      isNot(contains('focus.leave')),
      reason: 'and takes it back with it',
    );
  });

  testWidgets('the way out is a button as well as a key', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('time.focus.leave'));
    await tester.pumpAndSettle();

    expect(went.last, '/time');
  });
}

class _FakeTimeRepository implements TimeRepository {
  RunningTimer? running;

  @override
  Future<RunningTimer?> timer() async => running;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<Me> meAccount() async => throw ApiFailure('offline');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// The timer, as a value the test sets rather than a clock it has to wait on.
class _FakeTimerCubit extends Cubit<TimerState> implements TimerCubit {
  _FakeTimerCubit() : super(const TimerState());

  void show(RunningTimer timer) =>
      emit(TimerState(timer: timer, elapsed: timer.elapsed(DateTime.now())));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
