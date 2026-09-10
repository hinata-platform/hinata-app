import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/repositories/timesheet_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/timesheet/timesheet_screen.dart';
import '../time/fake_time_policy_cubit.dart';

/// The week grid has to answer for rows nobody owns any more and for time that
/// belongs to no project — both are ordinary states of the data, not errors —
/// and it must offer the way back to this week. The filters are an admin
/// surface: a plain member may only ever see their own hours, so a filter would
/// have nothing to narrow.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  final monday = _weekStart(DateTime.now());

  TimesheetRow row({
    required String userId,
    String? projectId,
    int minutes = 90,
  }) => TimesheetRow(
    userId: userId,
    projectId: projectId,
    minutesPerDay: {monday: minutes},
    totalMinutes: minutes,
  );

  const project = Project(id: 'p1', key: 'HIN', name: 'Hinata');

  const ada = DirectoryUser(
    id: 'u1',
    username: 'ada',
    displayName: 'Ada Lovelace',
  );

  late PageChromeController chrome;

  setUp(() => chrome = PageChromeController());

  Widget host({
    required List<TimesheetRow> rows,
    bool admin = false,
    List<DirectoryUser> directory = const [ada],
    List<Project> projects = const [project],
    _FakeTimesheetRepository? timesheet,
    _FakeProjectRepository? projectRepository,
    _FakeUserRepository? userRepository,
    _FakeTimeRepository? time,
    bool moduleView = false,
    bool dockedBand = false,
    TimePolicySnapshot policy = TimePolicySnapshot.none,
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: PageChromeScope(
              controller: chrome,
              child: Column(
                children: [
                  // The shell's contract, reproduced: it hands the docked
                  // toolbar the height the page asked for, as a *tight* one.
                  // Rendered only where a test is about that band, so every
                  // other test keeps the plain tree it had.
                  if (dockedBand)
                    Builder(
                      builder: (context) {
                        final published = PageChromeScope.of(context);
                        final bottom = published.bottomFor('/');
                        if (bottom == null) return const SizedBox.shrink();
                        return SizedBox(
                          height: published.bottomHeightFor('/'),
                          width: double.infinity,
                          child: bottom,
                        );
                      },
                    ),
                  Expanded(
                    child: MultiRepositoryProvider(
                      providers: [
                        RepositoryProvider<TimesheetRepository>.value(
                          value: timesheet ?? _FakeTimesheetRepository(rows),
                        ),
                        RepositoryProvider<UserRepository>.value(
                          value:
                              userRepository ?? _FakeUserRepository(directory),
                        ),
                        RepositoryProvider<ProjectRepository>.value(
                          value:
                              projectRepository ??
                              _FakeProjectRepository(projects),
                        ),
                        RepositoryProvider<TimeRepository>.value(
                          value: time ?? _FakeTimeRepository(rows),
                        ),
                      ],
                      child: MultiBlocProvider(
                        providers: [
                          BlocProvider<AuthBloc>.value(
                            value: _FakeAuthBloc(admin: admin),
                          ),
                          // The page asks the rules whether its window is a week
                          // or a submission period. Stated here rather than
                          // fetched: a test about the grid must not also be a
                          // test about a round trip.
                          BlocProvider<TimePolicyCubit>.value(
                            value: FakeTimePolicyCubit(
                              policy,
                              time ?? _FakeTimeRepository(rows),
                            ),
                          ),
                        ],
                        child: TimesheetScreen(moduleView: moduleView),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }

  group('the module\'s own page', () {
    testWidgets('rows come from the paged route, not the array one', (
      tester,
    ) async {
      final module = _FakeTimeRepository([row(userId: 'me')]);
      final base = _FakeTimesheetRepository([row(userId: 'me')]);
      await tester.pumpWidget(
        host(rows: const [], moduleView: true, time: module, timesheet: base),
      );
      await tester.pumpAndSettle();

      expect(module.calls, 1);
      expect(base.calls, isEmpty, reason: 'the base route is the other page');
    });

    testWidgets('the base page still reads the array route', (tester) async {
      final module = _FakeTimeRepository(const []);
      final base = _FakeTimesheetRepository([row(userId: 'me')]);
      await tester.pumpWidget(
        host(rows: const [], time: module, timesheet: base),
      );
      await tester.pumpAndSettle();

      expect(base.calls, hasLength(1));
      expect(module.calls, isZero);
    });

    testWidgets('a matrix the page could not fit says how much it is showing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          rows: const [],
          moduleView: true,
          admin: true,
          time: _FakeTimeRepository.withTotal([row(userId: 'me')], 137),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('timesheet.truncated'), findsOneWidget);
    });

    testWidgets('a week that fits says nothing at all', (tester) async {
      await tester.pumpWidget(
        host(
          rows: const [],
          moduleView: true,
          time: _FakeTimeRepository([row(userId: 'me')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('timesheet.truncated'), findsNothing);
    });

    testWidgets('your own cell can be typed into; a colleague\'s cannot', (
      tester,
    ) async {
      // The server refuses the write either way. A cell that opens a form
      // before being told no is a worse way to learn that — and a lead reading
      // a report has no business being offered one.
      await tester.pumpWidget(
        host(
          rows: const [],
          moduleView: true,
          admin: true,
          time: _FakeTimeRepository([row(userId: 'me'), row(userId: 'u1')]),
        ),
      );
      await tester.pumpAndSettle();

      // Seven days of the week, on the reader's own row and no other.
      expect(_tappableCells(tester), 7);
    });

    testWidgets('the base page never offers a cell, even to its owner', (
      tester,
    ) async {
      await tester.pumpWidget(host(rows: [row(userId: 'me')]));
      await tester.pumpAndSettle();

      expect(_tappableCells(tester), isZero);
    });
  });

  group('the week grid', () {
    testWidgets('names time that belongs to no project', (tester) async {
      await tester.pumpWidget(host(rows: [row(userId: 'u1', projectId: null)]));
      await tester.pumpAndSettle();

      expect(find.text('timesheet.unassigned'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
    });

    testWidgets('time that never had an owner is not called a deleted user', (
      tester,
    ) async {
      // The pre-2.0 smart-commit remainders carry no user at all. Calling them
      // a deleted account asserts that somebody was erased, which is a
      // different and untrue statement.
      await tester.pumpWidget(
        host(
          rows: [row(userId: '', projectId: 'p1')],
          admin: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('time.legacySource'), findsOneWidget);
      expect(find.text('time.deletedUser'), findsNothing);
    });

    testWidgets('an id the directory no longer knows reads as deleted', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          rows: [row(userId: 'ghost', projectId: 'p1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('time.deletedUser'), findsOneWidget);
      // The raw id is never put in front of a reader.
      expect(find.textContaining('ghost'), findsNothing);
      // The project it *does* know is named by its key.
      expect(find.text('HIN'), findsOneWidget);
    });

    testWidgets('a week with nothing in it says so, narrow and wide', (
      tester,
    ) async {
      for (final size in const [Size(402, 874), Size(1400, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(rows: const []));
        await tester.pumpAndSettle();

        expect(
          find.byType(HiveEmptyState),
          findsOneWidget,
          reason: 'empty default state at ${size.width}px',
        );
        expect(find.byType(DataTable), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the docked pills are the height every other page gives them', (
      tester,
    ) async {
      // The band reserves ten points more than the row of controls needs, and
      // the shell hands that whole height down as a tight constraint — which a
      // `SizedBox` cannot come in under. Without an `Align` saying where the
      // slack goes, every pill grew to the full band and the timesheet's
      // toolbar stood a head taller than the identical toolbar on the calendar
      // and the list beside it.
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(rows: const [], moduleView: true, dockedBand: true),
      );
      await tester.pumpAndSettle();

      final pills = find.byType(GlassPill);
      expect(pills, findsWidgets);
      for (var i = 0; i < pills.evaluate().length; i++) {
        expect(
          tester.getSize(pills.at(i)).height,
          kGlassControlHeight,
          reason: 'docked pill $i',
        );
      }
      // And the module's three views are not among them: on a phone they live
      // under the app bar's title, so the one docked row this page is allowed
      // is spent on the week it is showing.
      expect(find.byType(GlassSwitchBar), findsNothing);
    });

    testWidgets('a full week of columns fits a phone without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          rows: [row(userId: 'u1', projectId: 'p1')],
        ),
      );
      await tester.pumpAndSettle();

      // The table scrolls sideways inside its own box …
      final horizontal = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsOneWidget);
      expect(
        find.descendant(of: horizontal, matching: find.byType(DataTable)),
        findsOneWidget,
      );
      // … and nothing paints outside its constraints.
      expect(tester.takeException(), isNull);
    });
  });

  group('the way back to this week', () {
    testWidgets('is on the page, not published into a bar nobody draws', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          rows: [row(userId: 'u1', projectId: 'p1')],
        ),
      );
      await tester.pumpAndSettle();

      // The shell renders PageChrome actions in its sub-page bar, and a
      // destination in the nav has no sub-page bar — a title and an action
      // handed over that way are simply never drawn on a wide window. So they
      // live in the page's own head, and the test looks where a reader does.
      expect(find.text('timesheet.title'), findsOneWidget);
      expect(find.text('timesheet.today'), findsOneWidget);
      // The grid is a layout to scan across, not prose to read — and that
      // *is* the shell's business.
      expect(chrome.fullWidthFor('/'), isTrue);
    });

    testWidgets('re-asks the server for the current week', (tester) async {
      final repository = _FakeTimesheetRepository([
        row(userId: 'u1', projectId: 'p1'),
      ]);
      await tester.pumpWidget(host(rows: const [], timesheet: repository));
      await tester.pumpAndSettle();

      expect(repository.calls, hasLength(1));
      final thisWeek = repository.calls.single.from;

      // Page back a week, then take the action home again.
      await tester.tap(find.byType(IconButton).first);
      await tester.pumpAndSettle();
      expect(repository.calls.last.from, isNot(thisWeek));

      await tester.tap(find.text('timesheet.today'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.from, thisWeek);
    });
  });

  group('the filter list', () {
    testWidgets('pages the directory as the reader scrolls it', (tester) async {
      // Enough people to fill three pages of 25, so the panel has something to
      // page through rather than one short answer.
      final directory = [
        for (var i = 0; i < 60; i++)
          DirectoryUser(
            id: 'u$i',
            username: 'user$i',
            displayName: 'Person $i',
          ),
      ];
      final users = _FakeUserRepository(directory);
      await tester.pumpWidget(
        host(
          rows: [row(userId: 'u1', projectId: 'p1')],
          admin: true,
          directory: directory,
          userRepository: users,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('timesheet.allUsers').first);
      await tester.pumpAndSettle();

      expect(users.pagesAsked, [0], reason: 'one page to open with');

      await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
      await tester.pumpAndSettle();

      expect(
        users.pagesAsked.length,
        greaterThan(1),
        reason: 'scrolling to the end asks for the next page',
      );
      expect(
        users.pagesAsked.toSet(),
        hasLength(users.pagesAsked.length),
        reason: 'no page is asked for twice',
      );

      // And it stops. Termination is what the paged cubit changed here — the
      // explicit "exhausted" flag gave way to a count — so it is the property
      // worth pinning, not just that paging starts.
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
        await tester.pumpAndSettle();
      }
      expect(users.pagesAsked, [0, 1, 2]);
    });
  });

  group('what the page fetches', () {
    testWidgets('names only the projects its rows mention', (tester) async {
      final projects = _FakeProjectRepository(const [
        project,
        Project(id: 'p2', key: 'MOB', name: 'Mobile'),
        Project(id: 'p3', key: 'INF', name: 'Infra'),
      ]);
      await tester.pumpWidget(
        host(
          rows: [row(userId: 'u1', projectId: 'p1')],
          admin: true,
          projectRepository: projects,
        ),
      );
      await tester.pumpAndSettle();

      // Never the whole catalogue: an instance can hold hundreds of projects
      // and a week's table names a handful.
      expect(projects.resolved, hasLength(1));
      expect(projects.resolved.single, ['p1']);
    });
  });

  group('filters', () {
    testWidgets('an admin gets a user and a project filter', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          rows: [row(userId: 'u1', projectId: 'p1')],
          admin: true,
        ),
      );
      await tester.pumpAndSettle();

      // Both fields, each saying what it is and that nothing is narrowed yet.
      expect(find.text('timesheet.member'), findsNWidgets(2)); // field + column
      expect(find.text('timesheet.allUsers'), findsOneWidget);
      expect(find.text('timesheet.allProjects'), findsOneWidget);
    });

    testWidgets('a plain member gets none', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          rows: [row(userId: 'u1', projectId: 'p1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('timesheet.allUsers'), findsNothing);
      expect(find.text('timesheet.allProjects'), findsNothing);
      // The column header is still there — only the filter fields are gone.
      expect(find.text('timesheet.member'), findsOneWidget);
    });

    testWidgets('picking a user narrows the query server-side', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _FakeTimesheetRepository([
        row(userId: 'u1', projectId: 'p1'),
      ]);
      await tester.pumpWidget(
        host(rows: const [], admin: true, timesheet: repository),
      );
      await tester.pumpAndSettle();
      expect(repository.calls.single.userId, isNull);

      await tester.tap(find.text('timesheet.allUsers'));
      await tester.pumpAndSettle();

      // The panel searches the directory rather than listing it.
      await tester.tap(find.text('Ada Lovelace').last);
      await tester.pumpAndSettle();

      expect(repository.calls.last.userId, 'u1');
      // The field now names the pick instead of "everyone".
      expect(find.text('Ada Lovelace'), findsWidgets);
    });
  });

  // --- the period, when the instance hands timesheets in ---------------------

  group('the submission period', () {
    ApprovalPeriod period({
      required DateTime start,
      required DateTime end,
      String type = 'MONTHLY',
      ApprovalStatus? status,
      int minutes = 480,
    }) => ApprovalPeriod(
      start: start,
      end: end,
      type: type,
      projects: [
        ApprovalProjectStatus(
          projectId: 'p1',
          projectKey: 'HIN',
          status: status,
          approvalId: status == null ? null : 'a1',
          minutes: minutes,
        ),
      ],
    );

    /// A wide window: on a phone the page docks its controls into the shell's
    /// glass app bar, and this host draws no band unless asked.
    void wide(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<_FakeTimeRepository> open(
      WidgetTester tester, {
      required ApprovalPeriod only,
      String rhythm = 'MONTHLY',
    }) async {
      wide(tester);
      final time = _FakeTimeRepository(const [])..periods = [only];
      await tester.pumpWidget(
        host(
          rows: const [],
          moduleView: true,
          time: time,
          policy: TimePolicySnapshot(
            approvalsEnabled: true,
            approvalRhythm: ApprovalRhythm(type: rhythm),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return time;
    }

    testWidgets('a monthly rhythm drives the window from the server', (
      tester,
    ) async {
      // The app derives no rhythm of its own: the boundaries, the label and the
      // status all come from one answer.
      final time = await open(
        tester,
        only: period(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31)),
      );

      expect(time.rowWindows.last, (
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 31),
      ));
      expect(find.text('time.approval.rhythm.MONTHLY'), findsOneWidget);
      expect(find.text('time.approval.status.open'), findsOneWidget);
      expect(find.text('time.approval.submitAction'), findsOneWidget);
    });

    testWidgets('a weekly rhythm is named as one, with its own window', (
      tester,
    ) async {
      final time = await open(
        tester,
        rhythm: 'WEEKLY',
        only: period(
          start: DateTime(2026, 8, 3),
          end: DateTime(2026, 8, 9),
          type: 'WEEKLY',
        ),
      );

      expect(time.rowWindows.last, (
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 9),
      ));
      expect(find.text('time.approval.rhythm.WEEKLY'), findsOneWidget);
    });

    testWidgets(
      'the arrows move the anchor past the period, not by its length',
      (tester) async {
        // A month is four different lengths, so a neighbour is found by stepping
        // one day past the edge and asking again.
        final time = await open(
          tester,
          only: period(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31)),
        );
        time.periodWindows.clear();

        await tester.tap(find.byTooltip('time.approval.nextPeriod'));
        await tester.pumpAndSettle();

        expect(time.periodWindows.single, (
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 1),
        ));
      },
    );

    testWidgets('a FREE rhythm offers a span to pick instead of arrows', (
      tester,
    ) async {
      // There is no grid to step through, so arrows would be a lie about a
      // rhythm that does not exist.
      await open(
        tester,
        rhythm: 'FREE',
        only: period(
          start: DateTime(2026, 8, 4),
          end: DateTime(2026, 8, 10),
          type: 'FREE',
        ),
      );

      expect(find.byTooltip('time.approval.nextPeriod'), findsNothing);
      expect(find.byTooltip('time.approval.previousPeriod'), findsNothing);
      // The label is the span itself, on a button that opens the picker.
      expect(find.byIcon(LucideIcons.calendarRange), findsWidgets);
    });

    testWidgets('handing a period in sends its own dates and projects', (
      tester,
    ) async {
      final time = await open(
        tester,
        only: period(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31)),
      );

      await tester.tap(find.text('time.approval.submitAction'));
      await tester.pumpAndSettle();
      // The confirmation's own button, not the card's that opened it: both carry
      // the label, and the dialog's is the later of the two in the tree.
      await tester.tap(
        find.widgetWithText(FilledButton, 'time.approval.submitAction').last,
      );
      await tester.pumpAndSettle();
      // The shared confirmation lays its two buttons out in a plain Row, and the
      // labels here are i18n *keys* — far longer than the words they stand for,
      // so the row overflows in the test and nowhere else. Asserting its pixels
      // would be asserting about the key lengths.
      tester.takeException();

      // Field by field: a record holding a List compares that List by identity,
      // so the whole-record form passes only by accident.
      final sent = time.submissions.single;
      expect(sent.$1, DateTime(2026, 8, 1));
      expect(sent.$2, DateTime(2026, 8, 31));
      expect(sent.$3, ['p1']);
      // The success toast dismisses itself on a timer; letting it finish keeps
      // that timer out of whichever test runs next.
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets(
      'a period already in offers the way back, not a second submit',
      (tester) async {
        await open(
          tester,
          only: period(
            start: DateTime(2026, 8, 1),
            end: DateTime(2026, 8, 31),
            status: ApprovalStatus.submitted,
          ),
        );

        expect(find.text('time.approval.status.submitted'), findsOneWidget);
        expect(find.text('time.approval.submitAction'), findsNothing);
        expect(
          find.textContaining('time.approval.withdrawFor'),
          findsOneWidget,
        );
      },
    );

    testWidgets('an approved period offers neither — only a reopen can', (
      tester,
    ) async {
      await open(
        tester,
        only: period(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 31),
          status: ApprovalStatus.approved,
        ),
      );

      expect(find.text('time.approval.status.approved'), findsOneWidget);
      expect(find.text('time.approval.submitAction'), findsNothing);
      expect(find.textContaining('time.approval.withdrawFor'), findsNothing);
    });

    testWidgets('a period with no hours offers no submit', (tester) async {
      await open(
        tester,
        only: period(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 31),
          minutes: 0,
        ),
      );

      expect(find.text('time.approval.submitAction'), findsNothing);
    });

    testWidgets(
      'with approvals off the window is a week and nothing is offered',
      (tester) async {
        // The plain `/timesheet` is the surface the published app reads, and it
        // stays a week whatever this instance has configured.
        wide(tester);
        final time = _FakeTimeRepository(const [])
          ..periods = [
            period(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31)),
          ];
        await tester.pumpWidget(
          host(rows: const [], moduleView: true, time: time),
        );
        await tester.pumpAndSettle();

        expect(time.periodWindows, isEmpty);
        expect(find.text('time.approval.submitAction'), findsNothing);
        expect(find.text('timesheet.today'), findsWidgets);
      },
    );
  });
}

DateTime _weekStart(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - 1));

typedef _TimesheetCall = ({
  DateTime from,
  DateTime to,
  String? userId,
  String? projectId,
});

class _FakeTimesheetRepository implements TimesheetRepository {
  _FakeTimesheetRepository(this.rows);

  final List<TimesheetRow> rows;
  final List<_TimesheetCall> calls = [];

  @override
  Future<List<TimesheetRow>> timesheet(
    DateTime from,
    DateTime to, {
    String? userId,
    String? projectId,
  }) async {
    calls.add((from: from, to: to, userId: userId, projectId: projectId));
    return [
      for (final row in rows)
        if ((userId == null || row.userId == userId) &&
            (projectId == null || row.projectId == projectId))
          row,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository(this.directory);

  final List<DirectoryUser> directory;

  @override
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async => [
    for (final user in directory)
      if (ids.contains(user.id)) user,
  ];

  /// Which pages the panel asked for, in order.
  final List<int> pagesAsked = [];

  @override
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) async {
    pagesAsked.add(page);
    final needle = query.trim().toLowerCase();
    final matches = [
      for (final user in directory)
        if (needle.isEmpty || user.displayName.toLowerCase().contains(needle))
          user,
    ];
    final start = page * size;
    return (
      items: start >= matches.length
          ? const <DirectoryUser>[]
          : matches.sublist(
              start,
              start + size > matches.length ? matches.length : start + size,
            ),
      total: matches.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.catalogue);

  final List<Project> catalogue;

  /// Ids the screen asked to have named. The screen must never drain the whole
  /// catalogue — it resolves exactly the projects its rows mention.
  final List<List<String>> resolved = [];

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async {
    resolved.add(ids);
    return [
      for (final project in catalogue)
        if (ids.contains(project.id)) project,
    ];
  }

  @override
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
  }) async {
    final needle = (query ?? '').trim().toLowerCase();
    final matches = [
      for (final project in catalogue)
        if (needle.isEmpty ||
            project.name.toLowerCase().contains(needle) ||
            project.key.toLowerCase().contains(needle))
          project,
    ];
    return (
      projects: page == 0 ? matches : const <Project>[],
      total: matches.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Only the signed-in user's role is read, so a stub in a settled state is
/// enough — no repository, no storage, no sign-in to drive.
/// The module's paged route. Counts its calls, because which of the two routes
/// a page reads is exactly what these tests are about.
/// How many cells of the grid answer a tap.
///
/// [DataCell] is not a widget — it is data the table holds — so it cannot be
/// found in the tree; the table itself has to be asked.
int _tappableCells(WidgetTester tester) => tester
    .widget<DataTable>(find.byType(DataTable))
    .rows
    .expand((row) => row.cells)
    .where((cell) => cell.onTap != null)
    .length;

class _FakeTimeRepository implements TimeRepository {
  _FakeTimeRepository(this.rows) : total = null;

  final List<TimesheetRow> rows;
  int calls = 0;

  _FakeTimeRepository.withTotal(this.rows, this.total);

  /// What the whole matrix holds, which is only ever more than [rows] when the
  /// server's page ran out.
  int? total;

  /// The periods the server would hand back. Empty is what an instance without
  /// approvals answers, and what a FREE rhythm answers before anything has been
  /// handed in.
  List<ApprovalPeriod> periods = const [];

  /// Every window the page asked about, so a test can assert that the arrows move
  /// the *anchor* rather than the window.
  final List<(DateTime, DateTime)> periodWindows = [];

  /// Every window the grid asked rows for.
  final List<(DateTime, DateTime)> rowWindows = [];

  final List<(DateTime, DateTime, List<String>?)> submissions = [];
  final List<String> withdrawals = [];

  @override
  Future<PageResult<TimesheetRow>> timesheet({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? projectId,
    int page = 0,
    int size = 50,
  }) async {
    calls++;
    rowWindows.add((from, to));
    return (items: rows, total: total ?? rows.length);
  }

  @override
  Future<List<ApprovalPeriod>> approvalPeriods({
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) async {
    periodWindows.add((from, to));
    return periods;
  }

  @override
  Future<List<TimesheetApproval>> submitPeriod({
    required DateTime periodStart,
    required DateTime periodEnd,
    List<String>? projectIds,
  }) async {
    submissions.add((periodStart, periodEnd, projectIds));
    return const [];
  }

  @override
  Future<TimesheetApproval> withdrawApproval(String id) async {
    withdrawals.add(id);
    return TimesheetApproval(
      id: id,
      userId: 'me',
      projectId: 'p1',
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 31),
      status: ApprovalStatus.withdrawn,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc({required bool admin})
    : super(
        AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'me',
            email: 'me@example.test',
            username: 'me',
            displayName: 'Me',
            roles: admin ? const {'ADMIN'} : const {'USER'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
