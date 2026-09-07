import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/time/time_screen.dart';
import 'package:hinata/features/time/timer_bar.dart';

/// The `time.fmt.*` key the day header beside [dayKey] renders — the header's
/// own total, not one of the row durations further down the page.
String _totalKeyUnder(WidgetTester tester, String dayKey) {
  final header = find
      .ancestor(of: find.text(dayKey), matching: find.byType(Row))
      .first;
  return tester
      .widgetList<Text>(
        find.descendant(of: header, matching: find.byType(Text)),
      )
      .map((text) => text.data ?? '')
      .firstWhere((data) => data.startsWith('time.fmt.'), orElse: () => '');
}

/// The Time page and the timer bar, in the states a reader actually meets them
/// in: nothing tracked, something tracked, a server that would not answer, and
/// a timer that is or is not running.
///
/// Nothing here asserts on translated copy — widget tests render raw i18n keys,
/// so a label assertion would be pinning the key and its length rather than the
/// sentence.
void main() {
  final today = DateTime.now();

  WorkItem entry({
    required String id,
    String? description,
    int minutes = 90,
    String? projectId,
    DateTime? day,
    DateTime? startedAt,
    DateTime? endedAt,
  }) => WorkItem(
    id: id,
    userId: 'me',
    projectId: projectId,
    durationMinutes: minutes,
    activityType: 'Development',
    description: description,
    date: day ?? DateTime(today.year, today.month, today.day),
    startedAt: startedAt,
    endedAt: endedAt,
  );

  late PageChromeController chrome;

  setUp(() => chrome = PageChromeController());

  Widget host({
    required _FakeTimeRepository time,
    TimerState timer = const TimerState(),
    Size size = const Size(1400, 900),
    // What the compact shell hands the page as the height of the glass app bar
    // plus whatever the page docked into it. Zero unless a test is about it.
    EdgeInsets padding = EdgeInsets.zero,
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
                  value: _FakeTimerCubit(timer),
                  child: const TimeScreen(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return MediaQuery(
      data: MediaQueryData(size: size, padding: padding),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    );
  }

  group('the list', () {
    /// The page the reader opens is behind the app bar unless the body spends
    /// the gutter itself.
    ///
    /// On a phone the shell does not reserve the bar's height: it publishes it
    /// as `MediaQuery.padding.top` so content can scroll *through* the blur, and
    /// every page pays it where it wants the content to begin. This one did not,
    /// and the first day of the list — its header and its first rows — sat
    /// permanently behind the bar, smeared into it rather than clipped, so the
    /// page read as empty with something indistinct above it.
    testWidgets('on a phone the list starts below the glass header', (
      tester,
    ) async {
      const dock = EdgeInsets.only(top: 180);
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository([entry(id: 'a', description: 'first')]),
          size: const Size(390, 844),
          padding: dock,
        ),
      );
      await tester.pumpAndSettle();

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.padding?.resolve(TextDirection.ltr).top, dock.top);
      // And the refresh spinner drops from the same line, not from behind
      // the bar.
      expect(
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).edgeOffset,
        dock.top,
      );
    });

    testWidgets('on a wide window the head above the list has already paid it', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository([entry(id: 'a', description: 'first')]),
          size: const Size(1400, 900),
          padding: const EdgeInsets.only(top: 180),
        ),
      );
      await tester.pumpAndSettle();

      // Paying it twice would push the list a bar's height down the page.
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.padding?.resolve(TextDirection.ltr).top, 0);
    });

    testWidgets('the empty state begins below the header, not behind it', (
      tester,
    ) async {
      const dock = 180.0;
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository(const []),
          size: const Size(390, 844),
          padding: const EdgeInsets.only(top: dock),
        ),
      );
      await tester.pumpAndSettle();

      // Centred in the bare window its top edge lands around 90 — a third of
      // the card behind the blur, which is how the page came to look like it
      // was showing nothing at all.
      expect(
        tester.getTopLeft(find.byType(HiveEmptyState)).dy,
        greaterThanOrEqualTo(dock),
      );
      // And it is a card around a sentence, not a rectangle the height of the
      // page: HiveEmptyState fills whatever height it is given, so handing it
      // the body's full height drew one empty box from the toolbar to the
      // navigation.
      expect(
        tester.getSize(find.byType(HiveEmptyState)).height,
        lessThan(844 - dock),
      );
    });

    testWidgets(
      'a person with nothing tracked is told so, not shown a spinner',
      (tester) async {
        await tester.pumpWidget(host(time: _FakeTimeRepository(const [])));
        await tester.pumpAndSettle();

        expect(find.byType(HiveEmptyState), findsOneWidget);
        expect(find.text('time.empty.title'), findsOneWidget);
        // The empty state offers the way out of it — and so does the page head,
        // hence "widgets" rather than "one widget".
        expect(find.text('time.entry.new'), findsWidgets);
      },
    );

    testWidgets('entries are grouped by day with the day total', (
      tester,
    ) async {
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository([
            entry(id: 'a', description: 'wrote the parser', minutes: 90),
            entry(id: 'b', description: 'reviewed the PR', minutes: 45),
            entry(
              id: 'c',
              description: 'yesterday',
              minutes: 60,
              day: yesterday,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('wrote the parser'), findsOneWidget);
      expect(find.text('reviewed the PR'), findsOneWidget);
      expect(find.text('yesterday'), findsOneWidget);
      expect(find.text('common.today'), findsOneWidget);
      expect(find.text('common.yesterday'), findsOneWidget);
      // Each day totals its own rows and nothing else. Widget tests render raw
      // keys, so the numbers are invisible — but the *shape* is not: today is
      // 90 + 45 = 2h 15m and yesterday is a round hour, which fmtDuration
      // formats through two different keys. A header that summed the whole list
      // would say `hoursMinutes` under both days.
      expect(_totalKeyUnder(tester, 'common.today'), 'time.fmt.hoursMinutes');
      expect(_totalKeyUnder(tester, 'common.yesterday'), 'time.fmt.hours');
    });

    testWidgets('an entry with no description is named, not left blank', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(time: _FakeTimeRepository([entry(id: 'a')])),
      );
      await tester.pumpAndSettle();

      expect(find.text('time.entry.noDescription'), findsOneWidget);
    });

    testWidgets('an unfiled entry says so rather than showing an empty chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository([
            entry(id: 'a', description: 'retro', projectId: null),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('time.placement.none'), findsOneWidget);
    });

    testWidgets('a server that will not answer offers a retry', (tester) async {
      final repository = _FakeTimeRepository(const [], failing: true);
      await tester.pumpWidget(host(time: repository));
      await tester.pumpAndSettle();

      // Not the "nothing tracked yet" state: telling somebody their day is
      // empty when the request failed is a lie they would act on.
      expect(find.text('common.retry'), findsOneWidget);
      expect(find.text('time.error.title'), findsOneWidget);
      expect(find.text('time.empty.title'), findsNothing);

      repository.failing = false;
      await tester.tap(find.text('common.retry'));
      await tester.pumpAndSettle();

      expect(find.text('common.retry'), findsNothing);
    });

    testWidgets('the list asks for its own entries and nobody else\'s', (
      tester,
    ) async {
      final repository = _FakeTimeRepository([entry(id: 'a')]);
      await tester.pumpWidget(host(time: repository));
      await tester.pumpAndSettle();

      // There is no user filter to pass, which is the point: the endpoint
      // answers with the caller's rows and offers no way to ask otherwise.
      expect(repository.filtersAsked, hasLength(1));
      expect(repository.filtersAsked.single.projectId, isNull);
      expect(repository.filtersAsked.single.query, isNull);
    });
  });

  group('the timer bar', () {
    testWidgets('offers to start when nothing runs', (tester) async {
      await tester.pumpWidget(host(time: _FakeTimeRepository(const [])));
      await tester.pumpAndSettle();

      expect(find.text('time.timer.start'), findsOneWidget);
      expect(find.text('time.timer.stop'), findsNothing);
      expect(find.text('time.timer.idle'), findsOneWidget);
    });

    testWidgets('past an hour the readout carries the hour', (tester) async {
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository(const []),
          timer: TimerState(
            timer: RunningTimer(id: 't1', startedAt: DateTime.now()),
            elapsed: const Duration(hours: 2, minutes: 7, seconds: 9),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2:07:09'), findsOneWidget);
    });

    testWidgets('shows the running description and the way to stop it', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository(const []),
          timer: TimerState(
            timer: RunningTimer(
              id: 't1',
              startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
              description: 'pairing on the picker',
            ),
            elapsed: const Duration(minutes: 5, seconds: 3),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('pairing on the picker'), findsOneWidget);
      expect(find.text('time.timer.stop'), findsOneWidget);
      expect(find.text('time.timer.start'), findsNothing);
      // Under an hour the readout drops the empty hour, the way a stopwatch
      // does — and those three characters are what the description needs on a
      // phone.
      expect(find.text('5:03'), findsOneWidget);
    });

    testWidgets('a running timer with no description is named, not blank', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository(const []),
          timer: TimerState(
            timer: RunningTimer(id: 't1', startedAt: DateTime.now()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('time.timer.noDescription'), findsOneWidget);
    });

    testWidgets('the compact bar takes no room at all while nothing runs', (
      tester,
    ) async {
      // On a phone it floats above the navigation, so a bar that was always
      // there would be a permanent strip of chrome offering one button.
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<TimerCubit>.value(
            value: _FakeTimerCubit(const TimerState()),
            child: const Scaffold(body: TimerBar(compact: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(TimerBar)).height, 0);
    });

    testWidgets('the compact bar reserves exactly what the shell reserves', (
      tester,
    ) async {
      // The shell adds kCompactTimerBarHeight to the page's bottom gutter
      // before the bar has laid out. If the two disagreed, the last row of a
      // list would sit under the bar — or a strip of empty canvas would open
      // under it.
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<TimerCubit>.value(
            value: _FakeTimerCubit(
              TimerState(
                timer: RunningTimer(id: 't1', startedAt: DateTime.now()),
              ),
            ),
            child: const Scaffold(body: TimerBar(compact: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(TimerBar)).height,
        kCompactTimerBarHeight,
      );
    });
  });
}

class _FakeTimeRepository implements TimeRepository {
  _FakeTimeRepository(this.rows, {this.failing = false});

  final List<WorkItem> rows;
  bool failing;

  /// Every filter the screen asked with, so the test can state what it does
  /// *not* send as much as what it does.
  final List<TimeEntryFilter> filtersAsked = [];

  @override
  Future<PageResult<WorkItem>> entries({
    TimeEntryFilter filter = const TimeEntryFilter(),
    int page = 0,
    int size = 50,
  }) async {
    filtersAsked.add(filter);
    if (failing) throw Exception('offline');
    return (items: page == 0 ? rows : const <WorkItem>[], total: rows.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> resolveProjects(List<String> ids) async => const [];

  @override
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
  }) async => (projects: const <Project>[], total: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeIssueRepository implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// A cubit that is only ever asked for the state it was built with — the bar's
/// rendering is what these tests are about, not the requests behind it.
class _FakeTimerCubit extends Cubit<TimerState> implements TimerCubit {
  _FakeTimerCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
