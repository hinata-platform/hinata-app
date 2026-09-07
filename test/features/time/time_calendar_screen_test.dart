import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/core/widgets/time_grid/time_grid.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/time/time_calendar_screen.dart';

/// The calendar page: what it asks the server for, what it puts on the grid,
/// and what it does when the answer is short or missing.
///
/// The grid's own arithmetic and gestures are tested next to the grid. What is
/// left here is the part that is about time *entries* — which window, which
/// layer, and the notice when the window held more than came back.
void main() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);

  WorkItem entry({
    required String id,
    String? description,
    DateTime? startedAt,
    DateTime? endedAt,
    int minutes = 60,
  }) => WorkItem(
    id: id,
    userId: 'me',
    durationMinutes: minutes,
    activityType: 'Development',
    description: description,
    date: day,
    startedAt: startedAt,
    endedAt: endedAt,
  );

  late PageChromeController chrome;
  setUp(() => chrome = PageChromeController());

  Widget host({
    required _FakeTimeRepository time,
    Size size = const Size(1400, 900),
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: PageChromeScope(
              controller: chrome,
              child: MultiRepositoryProvider(
                providers: [
                  RepositoryProvider<TimeRepository>.value(value: time),
                  RepositoryProvider<ProjectRepository>.value(
                    value: _FakeProjectRepository(),
                  ),
                  RepositoryProvider<IssueRepository>.value(
                    value: _FakeIssueRepository(),
                  ),
                ],
                child: BlocProvider<TimerCubit>.value(
                  value: _FakeTimerCubit(const TimerState()),
                  child: const TimeCalendarScreen(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    );
  }

  testWidgets('it asks for the week it is showing, not for everything', (
    tester,
  ) async {
    final repository = _FakeTimeRepository();
    await tester.pumpWidget(host(time: repository));
    await tester.pumpAndSettle();

    expect(repository.windows, hasLength(1));
    final asked = repository.windows.single;
    // Seven days, inclusive — the server refuses anything past a month, and a
    // page that asked for more would simply never draw.
    expect(asked.to.difference(asked.from).inDays, 6);
  });

  testWidgets('a timed entry goes on the grid', (tester) async {
    await tester.pumpWidget(
      host(
        time: _FakeTimeRepository(
          logged: [
            entry(
              id: 'a',
              description: 'wrote the parser',
              startedAt: day.add(const Duration(hours: 9)),
              endedAt: day.add(const Duration(hours: 11)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimeGrid), findsOneWidget);
    expect(find.text('wrote the parser'), findsOneWidget);
  });

  testWidgets('an entry with no clock is still on the page, in the band', (
    tester,
  ) async {
    // It cannot be drawn between two hours it does not have. Dropping it would
    // make a day somebody logged look empty, which is the worse lie.
    await tester.pumpWidget(
      host(
        time: _FakeTimeRepository(
          logged: [entry(id: 'a', description: 'read the spec', minutes: 90)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('read the spec'), findsOneWidget);
    expect(find.text('time.calendar.untimed'), findsOneWidget);
  });

  testWidgets('a window the server had to cut says so', (tester) async {
    await tester.pumpWidget(
      host(
        time: _FakeTimeRepository(
          logged: [entry(id: 'a', description: 'one of many')],
          truncated: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('time.calendar.truncated'), findsOneWidget);
  });

  testWidgets('a server that will not answer offers a retry', (tester) async {
    final repository = _FakeTimeRepository(failing: true);
    await tester.pumpWidget(host(time: repository));
    await tester.pumpAndSettle();

    expect(find.byType(HiveEmptyState), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);

    repository.failing = false;
    await tester.tap(find.text('common.retry'));
    await tester.pumpAndSettle();

    expect(find.byType(TimeGrid), findsOneWidget);
  });

  testWidgets('switching to the day view asks for one day', (tester) async {
    final repository = _FakeTimeRepository();
    await tester.pumpWidget(host(time: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('time.calendar.day'));
    await tester.pumpAndSettle();

    expect(repository.windows.last.from, repository.windows.last.to);
  });

  testWidgets('paging back asks for the week before', (tester) async {
    final repository = _FakeTimeRepository();
    await tester.pumpWidget(host(time: repository));
    await tester.pumpAndSettle();
    final first = repository.windows.single.from;

    await tester.tap(find.byTooltip('time.calendar.previous'));
    await tester.pumpAndSettle();

    expect(
      first.difference(repository.windows.last.from).inDays,
      7,
      reason: 'a week back, not a day and not a month',
    );
  });
}

class _FakeTimeRepository implements TimeRepository {
  _FakeTimeRepository({
    this.logged = const [],
    this.truncated = false,
    this.failing = false,
  });

  /// Not named `entries`: the repository already has a method by that name, and
  /// a field cannot shadow it.
  final List<WorkItem> logged;
  final bool truncated;
  bool failing;

  /// Every window the page asked for, in order — what it asked is the point.
  final List<({DateTime from, DateTime to})> windows = [];

  @override
  Future<CalendarWindow> calendar(DateTime from, DateTime to) async {
    windows.add((from: from, to: to));
    if (failing) throw ApiFailure('errors.unexpected');
    return CalendarWindow(
      from: from,
      to: to,
      entries: logged,
      truncated: truncated,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeIssueRepository implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeTimerCubit extends Cubit<TimerState> implements TimerCubit {
  _FakeTimerCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
