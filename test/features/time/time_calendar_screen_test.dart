import 'package:flutter/gestures.dart'
    show kDoubleTapMinTime, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/core/widgets/time_grid/time_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_month_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_month_layout.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/time/time_calendar_screen.dart';

/// The calendar page: what it asks the server for, what it puts on the grid,
/// and what it does when the answer is short or missing.
///
/// The grid's own arithmetic and gestures are tested next to the grid. What is
/// left here is the part that is about time *entries* — which window, which
/// layer, and the chrome the page publishes into the app bar.
void main() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);

  WorkItem entry({
    required String id,
    String? description,
    DateTime? startedAt,
    DateTime? endedAt,
    int minutes = 60,
    DateTime? on,
  }) => WorkItem(
    id: id,
    userId: 'me',
    durationMinutes: minutes,
    activityType: 'Development',
    description: description,
    date: on ?? day,
    startedAt: startedAt,
    endedAt: endedAt,
  );

  late PageChromeController chrome;
  setUp(() => chrome = PageChromeController());

  const phone = Size(402, 874);

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

  /// Pumps the page with the *view* sized to match the window the page is told
  /// it has. Without it the tree lays out at 1400 points inside an 800-point
  /// view, and every control past the eighth hundred is untappable.
  Future<void> pump(
    WidgetTester tester,
    _FakeTimeRepository time, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(time: time, size: size));
    await tester.pumpAndSettle();
  }

  /// The same, at phone width — a docked band laid out in a 1400-point window
  /// is not the band a phone gets.
  Future<void> pumpPhone(WidgetTester tester, _FakeTimeRepository time) =>
      pump(tester, time, size: phone);

  testWidgets('it asks for whole months, and asks for each of them once', (
    tester,
  ) async {
    final repository = _FakeTimeRepository();
    await pump(tester, repository);

    expect(repository.windows, isNotEmpty);
    for (final window in repository.windows) {
      expect(window.from.day, 1, reason: 'a window starts on the first');
      expect(window.to.month, window.from.month);
      // The server refuses a window past 31 days, which a month never is.
      expect(window.to.difference(window.from).inDays, lessThan(31));
    }
    final asked = repository.windows.map((w) => (w.from.year, w.from.month));
    expect(
      asked.toSet().length,
      asked.length,
      reason: 'a month held is a month not asked for again',
    );
  });

  testWidgets('a timed entry goes on the grid', (tester) async {
    await pump(
      tester,
      _FakeTimeRepository(
        logged: [
          entry(
            id: 'a',
            description: 'wrote the parser',
            startedAt: day.add(const Duration(hours: 9)),
            endedAt: day.add(const Duration(hours: 11)),
          ),
        ],
      ),
    );

    expect(find.byType(TimeGrid), findsOneWidget);
    expect(find.text('wrote the parser'), findsOneWidget);
  });

  testWidgets('an entry with no clock is still on the page, in the band', (
    tester,
  ) async {
    // It cannot be drawn between two hours it does not have. Dropping it would
    // make a day somebody logged look empty, which is the worse lie.
    await pump(
      tester,
      _FakeTimeRepository(
        logged: [entry(id: 'a', description: 'read the spec', minutes: 90)],
      ),
    );

    expect(find.text('read the spec'), findsOneWidget);
    expect(find.text('time.calendar.untimed'), findsOneWidget);
  });

  testWidgets('with nothing to put in it, the band is not there at all', (
    tester,
  ) async {
    // A strip labelled "all day" with nothing in it is a claim about the day
    // that is not true, and it costs a row of the hour canvas to make.
    await pump(
      tester,
      _FakeTimeRepository(
        logged: [
          entry(
            id: 'a',
            description: 'wrote the parser',
            startedAt: day.add(const Duration(hours: 9)),
            endedAt: day.add(const Duration(hours: 11)),
          ),
        ],
      ),
    );

    expect(find.text('time.calendar.untimed'), findsNothing);
  });

  testWidgets('a window the server had to cut says so', (tester) async {
    await pump(
      tester,
      _FakeTimeRepository(
        logged: [entry(id: 'a', description: 'one of many')],
        truncated: true,
      ),
    );

    expect(find.text('time.calendar.truncated'), findsOneWidget);
  });

  testWidgets('a server that will not answer offers a retry', (tester) async {
    final repository = _FakeTimeRepository(failing: true);
    await pump(tester, repository);

    expect(find.byType(HiveEmptyState), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);

    repository.failing = false;
    await tester.tap(find.text('common.retry'));
    await tester.pumpAndSettle();

    expect(find.byType(TimeGrid), findsOneWidget);
  });

  testWidgets('there is no day span left to switch to', (tester) async {
    // The week reads a day at a time on a phone, which is what the separate day
    // view was for; two spans that show the same thing is one span too many.
    await pump(tester, _FakeTimeRepository());

    expect(find.text('time.calendar.day'), findsNothing);
    expect(find.text('time.calendar.week'), findsOneWidget);
    expect(find.text('time.calendar.month'), findsOneWidget);
  });

  testWidgets('the month scrolls, and the hour canvas gives way to it', (
    tester,
  ) async {
    final repository = _FakeTimeRepository();
    await pump(tester, repository);

    // The harness renders i18n *keys*, which are far longer than the words
    // they stand for, so the second chip starts life scrolled out of the bar.
    await tester.ensureVisible(find.text('time.calendar.month'));
    await tester.tap(find.text('time.calendar.month'));
    await tester.pumpAndSettle();

    expect(find.byType(TimeMonthScroller), findsOneWidget);
    expect(find.byType(TimeGrid), findsNothing);
  });

  testWidgets('a month steps from the month on screen, not from the anchor', (
    tester,
  ) async {
    // The month scrolls, and scrolling deliberately does not move the anchor.
    // Stepped from the anchor, "previous" pressed while looking at December
    // walked back from wherever the reader last jumped to — so the test has to
    // scroll first, or it passes against the arithmetic it is meant to catch.
    final repository = _FakeTimeRepository();
    await pump(tester, repository);
    // The harness renders i18n *keys*, which are far longer than the words
    // they stand for, so the second chip starts life scrolled out of the bar.
    await tester.ensureVisible(find.text('time.calendar.month'));
    await tester.tap(find.text('time.calendar.month'));
    await tester.pumpAndSettle();

    // Two months on, without touching the anchor.
    final scroller = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(TimeMonthScroller),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    var visible = DateTime(today.year, today.month);
    for (var step = 0; step < 2; step++) {
      scroller.jumpTo(
        scroller.pixels +
            weeksInMonth(visible, firstDayOfWeekIndex: _firstDay(tester)) *
                kMonthWeekExtent,
      );
      await tester.pumpAndSettle();
      visible = DateTime(visible.year, visible.month + 1);
    }
    await tester.tap(find.byTooltip('time.calendar.previous'));
    await tester.pumpAndSettle();

    // Read off the title, not off the requests: the month before the one on
    // screen has usually been prefetched already, so "did it ask for it" cannot
    // tell the two arithmetics apart. What the bar says is what the reader sees.
    final locale = Localizations.localeOf(
      tester.element(find.byType(TimeMonthScroller)),
    ).toLanguageTag();
    final before = DateTime(visible.year, visible.month - 1);
    expect(
      chrome.titleFor('/'),
      contains(DateFormat.MMMM(locale).format(before)),
      reason: 'the month before the one on screen, whatever its length',
    );
  });

  testWidgets('the span switcher sits at the trailing edge on a wide window', (
    tester,
  ) async {
    await pump(tester, _FakeTimeRepository());

    // Two switchers live on a wide page — the module's three views up in the
    // head, and this one. Reach the right one through a chip only it has.
    final bar = find.ancestor(
      of: find.text('time.calendar.month'),
      matching: find.byType(GlassSwitchBar),
    );
    final row = tester.getRect(
      find.ancestor(of: bar, matching: find.byType(Row)).first,
    );
    final switcher = tester.getRect(bar);

    expect(
      switcher.right,
      closeTo(row.right, 1),
      reason: 'hard against the edge, not trailing a clump on the left',
    );
  });

  testWidgets(
    'the page hands the bar a title, a menu and one new-entry action',
    (tester) async {
      // The bar centres its title in `width - 2 * max(leading, actions)`, so a
      // second trailing circle beside the bell and the gear leaves the title
      // nothing. One action, and the switching goes under the title instead.
      await pumpPhone(tester, _FakeTimeRepository());

      expect(chrome.titleFor('/'), isNotNull);
      expect(chrome.onTitleTapFor('/'), isNotNull);
      expect(chrome.actionsFor('/'), hasLength(1));
      expect(chrome.actionsFor('/').single.primary, isTrue);
    },
  );

  testWidgets('a phone docks one row, and lays it out without an unbounded flex', (
    tester,
  ) async {
    // Two things at once, because they are one rule: the blurred band above a
    // page holds the app bar's title row and exactly one more. A `Flexible` in
    // a horizontal scroller asks for a share of infinity and throws "RenderFlex
    // children have non-zero flex but incoming width constraints are unbounded"
    // — which took the whole calendar down on native builds and showed up
    // nowhere on web.
    await pumpPhone(tester, _FakeTimeRepository());

    final band = chrome.bottomFor('/');
    expect(band, isNotNull, reason: 'the phone docks its navigation');
    expect(
      chrome.bottomHeightFor('/'),
      lessThanOrEqualTo(56),
      reason: 'one row, not two',
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: phone),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: chrome.bottomHeightFor('/'),
              width: double.infinity,
              child: band,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone reads the week one day at a time', (tester) async {
    await pumpPhone(tester, _FakeTimeRepository());

    expect(find.byType(PageView), findsOneWidget);
    final grid = tester.widget<TimeGrid>(find.byType(TimeGrid).first);
    expect(grid.days, hasLength(1));
    expect(grid.days.single, day);
  });

  testWidgets('a swipe moves to the next day, and on into the next week', (
    tester,
  ) async {
    final repository = _FakeTimeRepository(
      logged: [
        for (var ahead = 0; ahead < 9; ahead++)
          entry(
            id: 'day$ahead',
            description: 'entry $ahead',
            on: DateTime(day.year, day.month, day.day + ahead),
            startedAt: DateTime(day.year, day.month, day.day + ahead, 9),
            endedAt: DateTime(day.year, day.month, day.day + ahead, 10),
          ),
      ],
    );
    await pumpPhone(tester, repository);

    // Far enough to leave whatever week today happens to fall in: seven swipes
    // land on the same weekday one week on, whichever day the test runs.
    for (var swipe = 0; swipe < 8; swipe++) {
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
    }

    final grid = tester.widget<TimeGrid>(find.byType(TimeGrid).first);
    expect(
      grid.days.single,
      DateTime(day.year, day.month, day.day + 8),
      reason: 'the day after Sunday is Monday, and the strip follows it',
    );
  });

  // --- adding an entry by hand ---------------------------------------------
  //
  // The grid's own gesture arithmetic is tested next to the grid, on a grid
  // that is nobody's child. These are about the composition: a hour canvas
  // inside a horizontal pager inside a vertical scroll view, which is what the
  // phone actually renders, and a month whose cells are the only surface there
  // is. A gesture that works in isolation and loses the arena in place is
  // exactly the failure these exist to catch.

  testWidgets('a long press on the day canvas opens a new entry', (
    tester,
  ) async {
    await pumpPhone(tester, _FakeTimeRepository());

    final canvas = tester.getRect(find.byType(TimeGrid).first);
    final gesture = await tester.startGesture(
      Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 120),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('time.entry.subtitle'), findsOneWidget);
    expect(find.text('time.entry.new'), findsWidgets);
  });

  testWidgets('a double tap on empty canvas opens a new entry at that hour', (
    tester,
  ) async {
    await pumpPhone(tester, _FakeTimeRepository());

    final canvas = tester.getRect(find.byType(TimeGrid).first);
    final at = Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 120);
    await tester.tapAt(at);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(at);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(find.text('time.entry.subtitle'), findsOneWidget);
    expect(find.text('time.entry.new'), findsWidgets);
  });

  testWidgets('a single tap on empty canvas opens nothing', (tester) async {
    await pumpPhone(tester, _FakeTimeRepository());

    final canvas = tester.getRect(find.byType(TimeGrid).first);
    await tester.tapAt(
      Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 120),
    );
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(find.text('time.entry.subtitle'), findsNothing);
  });

  testWidgets('a tap on a block opens that block, not a new entry', (
    tester,
  ) async {
    final repository = _FakeTimeRepository(
      logged: [
        entry(
          id: 'a',
          description: 'existing',
          startedAt: DateTime(day.year, day.month, day.day, 9),
          endedAt: DateTime(day.year, day.month, day.day, 11),
        ),
      ],
    );
    await pumpPhone(tester, repository);

    await tester.tap(find.text('existing').first);
    await tester.pumpAndSettle();

    expect(find.text('time.entry.subtitle'), findsOneWidget);
    expect(find.text('time.entry.edit'), findsWidgets);
  });

  testWidgets('a long press on a month day opens a new entry on that day', (
    tester,
  ) async {
    await pump(tester, _FakeTimeRepository());
    await tester.ensureVisible(find.text('time.calendar.month'));
    await tester.tap(find.text('time.calendar.month'));
    await tester.pumpAndSettle();

    // Whatever today is, its own cell is on screen.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('${day.day}').first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('time.entry.subtitle'), findsOneWidget);
    expect(find.text('time.entry.new'), findsWidgets);
  });

  testWidgets('paging back asks for the week before', (tester) async {
    final repository = _FakeTimeRepository();
    await pump(tester, repository);
    final grid = tester.widget<TimeGrid>(find.byType(TimeGrid));
    final first = grid.days.first;

    await tester.tap(find.byTooltip('time.calendar.previous'));
    await tester.pumpAndSettle();

    final back = tester.widget<TimeGrid>(find.byType(TimeGrid)).days.first;
    expect(
      first.difference(back).inDays,
      7,
      reason: 'a week back, not a day and not a month',
    );
  });
  testWidgets(
    'an entry whose hours were moved off its filed day is still drawn',
    (tester) async {
      // The server files an entry under a reporting day of its own and leaves it
      // alone when only the interval is edited, so the two come apart in two
      // taps. The pool is keyed on the filed day and the hour canvas places by
      // the span: handed only its own day, the entry was drawn nowhere at all —
      // while the month cell and the timesheet both counted it.
      final moved = DateTime(day.year, day.month, day.day + 1);
      await pumpPhone(
        tester,
        _FakeTimeRepository(
          logged: [
            entry(
              id: 'a',
              description: 'moved hours',
              on: day,
              startedAt: DateTime(moved.year, moved.month, moved.day, 9),
              endedAt: DateTime(moved.year, moved.month, moved.day, 11),
            ),
          ],
        ),
      );

      // Not on the day it is filed under — its hours are not there …
      expect(find.text('moved hours'), findsNothing);

      // … and on the day its hours are, which is the day it has to be drawn on.
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('moved hours'), findsOneWidget);
    },
  );

  testWidgets('the tail of an overnight entry is drawn on the following day', (
    tester,
  ) async {
    // The wide week canvas cuts it at midnight and draws both halves, because
    // there it is a shape with two ends. The phone draws one column at a time
    // and has to agree with it about the same entry.
    await pumpPhone(
      tester,
      _FakeTimeRepository(
        logged: [
          entry(
            id: 'a',
            description: 'night shift',
            on: day,
            startedAt: DateTime(day.year, day.month, day.day, 22),
            endedAt: DateTime(day.year, day.month, day.day + 1, 2),
          ),
        ],
      ),
    );

    expect(find.text('night shift'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(
      find.text('night shift'),
      findsOneWidget,
      reason: 'the hours after midnight belong to the next column too',
    );
  });

  testWidgets('a month that failed says so rather than reading as empty', (
    tester,
  ) async {
    // A calendar that draws "not here" the same way it draws "nothing logged"
    // is telling somebody they did not work.
    final repository = _FakeTimeRepository(failing: true);
    await pump(tester, repository);

    expect(find.byType(HiveEmptyState), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);
    expect(find.byType(TimeMonthScroller), findsNothing);
    expect(find.byType(TimeGrid), findsNothing);
  });

  testWidgets('a month asked for twice over is only fetched once', (
    tester,
  ) async {
    // [_monthsAround] names the same month more than once on purpose — a week
    // is usually all in one — and the scroller asks for three at a boundary.
    final repository = _FakeTimeRepository();
    await pump(tester, repository);
    final before = repository.windows.length;

    await tester.tap(find.byTooltip('time.calendar.next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('time.calendar.previous'));
    await tester.pumpAndSettle();

    final asked = repository.windows.map((w) => (w.from.year, w.from.month));
    expect(asked.toSet().length, asked.length);
    expect(repository.windows.length, greaterThanOrEqualTo(before));
  });
}

/// The day the harness's locale starts a week on — the month grid is laid out
/// to it, so a test that jumps by whole months has to count in the same rows.
int _firstDay(WidgetTester tester) => MaterialLocalizations.of(
  tester.element(find.byType(TimeMonthScroller)),
).firstDayOfWeekIndex;

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
      // The page holds a month at a time and looks days up in it, so a fake
      // that answered every window with everything would file the same entry
      // under the same day twice.
      entries: [
        for (final item in logged)
          if (item.date != null &&
              !item.date!.isBefore(from) &&
              !item.date!.isAfter(to))
            item,
      ],
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
