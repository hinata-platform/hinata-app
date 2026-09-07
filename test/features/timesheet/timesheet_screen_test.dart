import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/timesheet_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/timesheet/timesheet_screen.dart';

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
                  RepositoryProvider<TimesheetRepository>.value(
                    value: timesheet ?? _FakeTimesheetRepository(rows),
                  ),
                  RepositoryProvider<UserRepository>.value(
                    value: _FakeUserRepository(directory),
                  ),
                  RepositoryProvider<ProjectRepository>.value(
                    value: _FakeProjectRepository(projects),
                  ),
                ],
                child: BlocProvider<AuthBloc>.value(
                  value: _FakeAuthBloc(admin: admin),
                  child: const TimesheetScreen(),
                ),
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

  group('the week grid', () {
    testWidgets('names time that belongs to no project', (tester) async {
      await tester.pumpWidget(host(rows: [row(userId: 'u1', projectId: null)]));
      await tester.pumpAndSettle();

      expect(find.text('timesheet.unassigned'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
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
    testWidgets('is published into the shell app bar', (tester) async {
      await tester.pumpWidget(
        host(
          rows: [row(userId: 'u1', projectId: 'p1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        chrome.actionsFor('/').map((a) => a.label),
        contains('timesheet.today'),
      );
      expect(chrome.titleFor('/'), 'timesheet.title');
      // The grid is a layout to scan across, not prose to read.
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

      chrome
          .actionsFor('/')
          .firstWhere((a) => a.label == 'timesheet.today')
          .onTap!();
      await tester.pumpAndSettle();
      expect(repository.calls.last.from, thisWeek);
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

  @override
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) async {
    final needle = query.trim().toLowerCase();
    final matches = [
      for (final user in directory)
        if (needle.isEmpty || user.displayName.toLowerCase().contains(needle))
          user,
    ];
    return (
      items: page == 0 ? matches : const <DirectoryUser>[],
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

  @override
  Future<List<Project>> projects({bool archived = false}) async => catalogue;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Only the signed-in user's role is read, so a stub in a settled state is
/// enough — no repository, no storage, no sign-in to drive.
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
