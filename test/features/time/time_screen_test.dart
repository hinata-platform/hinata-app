import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/glass_popup_menu.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/time/time_screen.dart';
import 'package:hinata/features/time/timer_bar.dart';

import 'fake_time_policy_cubit.dart';

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
    TimePolicySnapshot policy = TimePolicySnapshot.none,
    Size size = const Size(1400, 900),
    // What the compact shell hands the page as the height of the glass app bar
    // plus whatever the page docked into it. Zero unless a test is about it.
    EdgeInsets padding = EdgeInsets.zero,
    // Handed in only where a test has to read back what the page asked the
    // timer to do; otherwise the page gets one built from [timer].
    _FakeTimerCubit? timerCubit,
    // Likewise, for a test about the rules changing under a session that had
    // already read them.
    FakeTimePolicyCubit? policyCubit,
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
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<TimerCubit>.value(
                      value: timerCubit ?? _FakeTimerCubit(timer),
                    ),
                    // Nothing required, nothing frozen — what a fresh instance
                    // demands, and what the screens assume until the module
                    // answers otherwise.
                    BlocProvider<TimePolicyCubit>(
                      create: (_) =>
                          policyCubit ?? FakeTimePolicyCubit(policy, time),
                    ),
                  ],
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
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .edgeOffset,
        dock.top,
      );
    });

    testWidgets(
      'on a wide window the head above the list has already paid it',
      (tester) async {
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
      },
    );

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

    testWidgets('a frozen entry is marked, and its menu offers no edit', (
      tester,
    ) async {
      // A row that let somebody open an editor whose save is refused is a row
      // that teaches them to distrust the screen. The history stays offered:
      // reading a frozen entry is not forbidden, and "who closed this" is
      // exactly the question a frozen entry raises.
      final frozen = DateTime(2026, 9, 3);
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository([
            entry(id: 'a', description: 'closed month', day: frozen),
          ]),
          policy: TimePolicySnapshot(lockBefore: DateTime(2026, 9, 10)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('time.policy.lockedChip'), findsOneWidget);

      await tester.tap(find.byType(GlassPopupMenu<String>));
      await tester.pumpAndSettle();

      expect(find.text('time.history.open'), findsOneWidget);
      expect(find.text('common.edit'), findsNothing);
      expect(find.text('common.delete'), findsNothing);
    });

    testWidgets('an ordinary entry keeps both, and gains the history', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository([entry(id: 'a', description: 'today')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('time.policy.lockedChip'), findsNothing);

      await tester.tap(find.byType(GlassPopupMenu<String>));
      await tester.pumpAndSettle();

      expect(find.text('common.edit'), findsOneWidget);
      expect(find.text('common.delete'), findsOneWidget);
      expect(find.text('time.history.open'), findsOneWidget);
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

  /// The phone's one trailing action.
  ///
  /// A phone's app bar has room for a single button and the module has two ways
  /// to add time. It used to be "new entry" outright, which left starting a
  /// timer reachable only by knowing that the title opens a menu — so on a
  /// phone the module's headline feature had no button at all.
  group('the phone\'s add button', () {
    const phone = Size(420, 900);

    Future<void> openMenu(WidgetTester tester) async {
      final actions = chrome.actionsFor('/');
      expect(actions, hasLength(1));
      // The rect the shell would hand it: the menu hangs off the button, so
      // without one it opens nothing at all.
      actions.single.onTap!(const Rect.fromLTWH(360, 40, 42, 42));
      await tester.pumpAndSettle();
    }

    testWidgets('asks which kind of add, rather than assuming', (tester) async {
      // With a row on the page, so the empty state — which offers "new entry"
      // itself, and is the whole reason the button could not simply be that —
      // is not on screen to be counted twice.
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository([entry(id: 'a')]),
          size: phone,
        ),
      );
      await tester.pumpAndSettle();
      await openMenu(tester);

      expect(find.text('time.entry.new'), findsOneWidget);
      expect(find.text('time.add.timerStart'), findsOneWidget);
    });

    testWidgets('its second row starts the timer', (tester) async {
      final cubit = _FakeTimerCubit(const TimerState());
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository(const []),
          size: phone,
          timerCubit: cubit,
        ),
      );
      await tester.pumpAndSettle();
      await openMenu(tester);

      await tester.tap(find.text('time.add.timerStart'));
      await tester.pumpAndSettle();

      // The plain start, which is the stopwatch — the same one the wide bar's
      // button is.
      expect(cubit.started, [TimerMode.stopwatch]);
    });

    testWidgets('while one runs the row stops it instead of offering a second '
        'start', (tester) async {
      // A start would be refused by the server, so the row would be one that
      // can only fail. It asks the timer's one question instead.
      final cubit = _FakeTimerCubit(
        TimerState(
          timer: RunningTimer(id: 't1', startedAt: DateTime.now()),
        ),
      );
      await tester.pumpWidget(
        host(
          time: _FakeTimeRepository(const []),
          size: phone,
          timerCubit: cubit,
        ),
      );
      await tester.pumpAndSettle();
      await openMenu(tester);

      expect(find.text('time.add.timerStop'), findsOneWidget);
      expect(find.text('time.add.timerStart'), findsNothing);
      expect(cubit.started, isEmpty);
    });

    /// A timer starts with nothing — that is the point of one. So the operator's
    /// required fields are collected at the stop, in the composer, rather than
    /// asked for at a start that has no fields to ask with.
    group('and the stop it offers', () {
      _FakeTimerCubit running() => _FakeTimerCubit(
        TimerState(
          timer: RunningTimer(
            id: 't1',
            startedAt: DateTime.now().subtract(const Duration(minutes: 30)),
          ),
        ),
      );

      testWidgets('files straight away when nothing is required', (
        tester,
      ) async {
        final cubit = running();
        await tester.pumpWidget(
          host(
            time: _FakeTimeRepository(const []),
            size: phone,
            timerCubit: cubit,
          ),
        );
        await tester.pumpAndSettle();
        await openMenu(tester);

        await tester.tap(find.text('time.add.timerStop'));
        await tester.pumpAndSettle();

        expect(cubit.stopped, hasLength(1));
        expect(find.text('time.timer.finish'), findsNothing);
      });

      testWidgets(
        'asks first when the policy wants more than the timer holds',
        (tester) async {
          final cubit = running();
          await tester.pumpWidget(
            host(
              time: _FakeTimeRepository(const []),
              size: phone,
              timerCubit: cubit,
              policy: const TimePolicySnapshot(requiredDescription: true),
            ),
          );
          await tester.pumpAndSettle();
          await openMenu(tester);

          await tester.tap(find.text('time.add.timerStop'));
          await tester.pumpAndSettle();

          // The composer, and nothing filed behind it: the timer is still
          // running, so cancelling here loses nothing.
          expect(find.text('time.timer.finish'), findsOneWidget);
          expect(cubit.stopped, isEmpty);
        },
      );

      testWidgets(
        'a frozen day is sent to the server rather than into a dead form',
        (tester) async {
          // The composer is worth opening only for something typing can fix.
          // Where the timer's day is locked it can fix nothing: the form's own
          // gate refuses a frozen day before it looks at a single field, so its
          // save would never enable — and every other way of stopping leads
          // back into the same sheet. That is a timer the app cannot stop at
          // all. Sent instead, the server deletes it and says why.
          final cubit = running();
          await tester.pumpWidget(
            host(
              time: _FakeTimeRepository(const []),
              size: phone,
              timerCubit: cubit,
              policy: TimePolicySnapshot(
                requiredDescription: true,
                lockBefore: DateTime.now().add(const Duration(days: 1)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await openMenu(tester);

          await tester.tap(find.text('time.add.timerStop'));
          await tester.pumpAndSettle();

          expect(find.text('time.timer.finish'), findsNothing);
          expect(cubit.stopped, hasLength(1));
          expect(
            cubit.stopped.single.description,
            isNull,
            reason: 'straight through, with nothing a composer collected',
          );
        },
      );

      testWidgets('a refusal it did not see coming opens the composer', (
        tester,
      ) async {
        // The bar decides from a snapshot read once a session, and a timer may
        // have been running since before an administrator turned a field on.
        // Then the stop this side thinks is complete comes back refused — and
        // without asking again, pressing stop would do the same thing for ever
        // while the clock kept running.
        final cubit = running()..refuseStop = true;
        final policy = FakeTimePolicyCubit(
          TimePolicySnapshot.none,
          _FakeTimeRepository(const []),
        )..onRefresh = const TimePolicySnapshot(requiredDescription: true);
        await tester.pumpWidget(
          host(
            time: _FakeTimeRepository(const []),
            size: phone,
            timerCubit: cubit,
            policyCubit: policy,
          ),
        );
        await tester.pumpAndSettle();
        await openMenu(tester);

        await tester.tap(find.text('time.add.timerStop'));
        await tester.pumpAndSettle();

        expect(
          policy.refreshes,
          1,
          reason: 'asked again, once, on the refusal',
        );
        expect(
          find.text('time.timer.finish'),
          findsOneWidget,
          reason: 'the composer for what the fresh policy says is missing',
        );
      });

      testWidgets('and the answer rides along on the stop', (tester) async {
        final cubit = running();
        await tester.pumpWidget(
          host(
            time: _FakeTimeRepository(const []),
            size: phone,
            timerCubit: cubit,
            policy: const TimePolicySnapshot(requiredDescription: true),
          ),
        );
        await tester.pumpAndSettle();
        await openMenu(tester);
        await tester.tap(find.text('time.add.timerStop'));
        await tester.pumpAndSettle();

        // Real milliseconds pass while the description is typed, which is the
        // whole point of the chain being tested: they were not worked, so they
        // must not be filed. Asserting the instant is merely non-null would
        // pass just as happily on a stop that sent its own `now`.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        final whileTyping = DateTime.now();
        await tester.enterText(find.byType(TextField).first, 'pairing');
        await tester.pumpAndSettle();
        await tester.tap(find.text('time.timer.stop').last);
        await tester.pumpAndSettle();

        expect(cubit.stopped, hasLength(1));
        expect(cubit.stopped.single.description, 'pairing');
        // The end is the one the sheet was opened with — when stop was pressed,
        // not when the field was finally typed.
        expect(
          cubit.stopped.single.endedAt!.isBefore(whileTyping),
          isTrue,
          reason: 'the minutes spent in the composer are not minutes worked',
        );
      });
    });

    testWidgets('the module title sits on the leading edge', (tester) async {
      // The module's three pages are one place seen three ways; a title that
      // moves between the centre and the edge as you step between them reads
      // as three places.
      await tester.pumpWidget(
        host(time: _FakeTimeRepository(const []), size: phone),
      );
      await tester.pumpAndSettle();

      expect(chrome.titleLeadingFor('/'), isTrue);
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
///
/// [start] is the exception: the phone's "+" menu exists to reach it, so a test
/// about that menu has to be able to say whether it did.
class _FakeTimerCubit extends Cubit<TimerState> implements TimerCubit {
  _FakeTimerCubit(super.initialState);

  /// The modes it was asked to start in, in order.
  final List<TimerMode> started = [];

  /// What each stop carried. A timer becomes an entry here, so a test about
  /// where the required fields are collected has to be able to read them back.
  final List<({DateTime? endedAt, String? description})> stopped = [];

  /// Whether the server turns the next stop down — a policy this side has not
  /// read yet, which is the one case the bar cannot see coming.
  bool refuseStop = false;

  @override
  Future<SavedTimeEntry?> end() async => state.timer == null ? null : stop();

  @override
  Future<SavedTimeEntry?> stop({
    DateTime? endedAt,
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String>? tags,
    bool? billable,
  }) async {
    stopped.add((endedAt: endedAt, description: description));
    if (refuseStop) return null;
    emit(const TimerState());
    return const SavedTimeEntry(
      entry: WorkItem(
        id: 'e1',
        durationMinutes: 30,
        activityType: 'Development',
      ),
    );
  }

  @override
  Future<void> start({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String> tags = const [],
    bool? billable,
    TimerMode mode = TimerMode.stopwatch,
    int? plannedMinutes,
    PomodoroConfig? pomodoro,
  }) async => started.add(mode);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
