/// The head of both boards: docked into the app bar's blur on a phone, on the
/// page itself on a wide window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/sprint_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show PageHead;
import 'package:hinata/features/board/board_header.dart';
import 'package:hinata/features/board/board_screen.dart';
import 'package:hinata/features/board/wall/board_reads.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/sprint/sprint_planning_surface.dart';

const _phone = Size(390, 844);
const _wide = Size(1400, 1000);

const _login = Issue(
  id: 'i1',
  projectId: 'p1',
  readableId: 'MOB-1',
  title: 'Fix the login screen',
  state: 'OPEN',
);
const _notes = Issue(
  id: 'i2',
  projectId: 'p1',
  readableId: 'MOB-2',
  title: 'Write the release notes',
  state: 'OPEN',
);

void main() {
  Future<void> open(
    WidgetTester tester, {
    required BoardType type,
    required Size size,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final board = AgileBoard(
      id: 'b1',
      name: type == BoardType.scrum
          ? 'Hinata Platform Board'
          : 'Test Kanban Board',
      projectIds: const ['p1'],
      type: type,
    );
    final chrome = PageChromeController();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<BoardRepository>.value(
            value: _FakeBoardRepository(board),
          ),
          RepositoryProvider<ProjectRepository>.value(
            value: _FakeProjectRepository(),
          ),
          RepositoryProvider<TeamRepository>.value(
            value: _FakeTeamRepository(),
          ),
          RepositoryProvider<IssueRepository>.value(
            value: _FakeIssueRepository(),
          ),
          RepositoryProvider<UserRepository>.value(
            value: _FakeUserRepository(),
          ),
          RepositoryProvider<SprintRepository>.value(
            value: _FakeSprintRepository(),
          ),
        ],
        child: BlocProvider<AuthBloc>(
          create: (_) => _FakeAuthBloc(),
          // A router above it, because PageChrome publishes into the shell by
          // asking GoRouterState where it is.
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: _Bar.location,
              routes: [
                GoRoute(
                  path: '/boards/:id',
                  builder: (_, state) => PageChromeScope(
                    controller: chrome,
                    child: Scaffold(
                      body: Column(
                        children: [
                          const _Bar(),
                          Expanded(
                            child: KanbanBoardScreen(
                              boardId: state.pathParameters['id']!,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inBar(Finder finder) =>
      find.descendant(of: find.byType(_Bar), matching: finder);

  group('the Kanban board', () {
    testWidgets(
      'on a phone docks its views, search and filter under its name',
      (tester) async {
        await open(tester, type: BoardType.kanban, size: _phone);

        expect(find.text('title: Test Kanban Board'), findsOneWidget);
        // No page head: the name is the bar's title, and a second one on the
        // page would only push the wall down.
        expect(find.byType(PageHead), findsNothing);
        for (final type in [
          BoardViewSwitch,
          GlassSearchButton,
          BoardFilterPill,
        ]) {
          expect(inBar(find.byType(type)), findsOneWidget);
        }
      },
    );

    testWidgets('narrows the wall to the cards a search finds', (tester) async {
      await open(tester, type: BoardType.kanban, size: _phone);
      expect(find.textContaining('release notes'), findsOneWidget);

      await tester.tap(inBar(find.byType(GlassSearchButton)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(GlassSearchField),
          matching: find.byType(TextField),
        ),
        'login',
      );
      // The search waits a moment for the next letter, then asks the server.
      await tester.pump(kBoardSearchDelay + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.textContaining('login screen'), findsOneWidget);
      expect(find.textContaining('release notes'), findsNothing);
    });

    testWidgets('on a wide window keeps its page head and docks nothing', (
      tester,
    ) async {
      await open(tester, type: BoardType.kanban, size: _wide);

      expect(find.byType(PageHead), findsOneWidget);
      expect(inBar(find.byType(BoardHeaderDock)), findsNothing);
      expect(find.byType(BoardSearchField), findsOneWidget);
    });
  });

  group('the Scrum board', () {
    testWidgets(
      'on a phone makes sprints from the bar, searches from the dock',
      (tester) async {
        await open(tester, type: BoardType.scrum, size: _phone);

        expect(find.text('title: Hinata Platform Board'), findsOneWidget);
        expect(find.text('action: sprint.createSprint'), findsOneWidget);
        expect(inBar(find.byType(GlassSearchButton)), findsOneWidget);
        // The planning list no longer opens on a button of its own.
        expect(
          find.descendant(
            of: find.byType(SprintPlanningSurface),
            matching: find.text('sprint.createSprint'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('narrows the planning to the cards a search finds', (
      tester,
    ) async {
      await open(tester, type: BoardType.scrum, size: _phone);
      expect(find.textContaining('release notes'), findsOneWidget);

      await tester.tap(inBar(find.byType(GlassSearchButton)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(GlassSearchField),
          matching: find.byType(TextField),
        ),
        'login',
      );
      // The search waits a moment for the next letter, then asks the server.
      await tester.pump(kBoardSearchDelay + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.textContaining('login screen'), findsOneWidget);
      expect(find.textContaining('release notes'), findsNothing);
    });

    testWidgets('has nothing to search, filter or create on the insights', (
      tester,
    ) async {
      await open(tester, type: BoardType.scrum, size: _phone);

      await tester.tap(find.byTooltip('sprint.tab.insights'));
      await tester.pumpAndSettle();

      expect(inBar(find.byType(GlassSearchButton)), findsNothing);
      expect(inBar(find.byType(BoardFilterPill)), findsNothing);
      expect(find.text('action: sprint.createSprint'), findsNothing);
    });
  });
}

/// What the shell draws from a page's chrome, cut down to what these tests
/// read: the title, the page's actions by name, and the docked row.
class _Bar extends StatelessWidget {
  const _Bar();

  static const location = '/boards/b1';

  @override
  Widget build(BuildContext context) {
    final chrome = PageChromeScope.of(context);
    final bottom = chrome.bottomFor(location);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('title: ${chrome.titleFor(location)}'),
        for (final action in chrome.actionsFor(location))
          Text('action: ${action.label}'),
        if (bottom != null)
          SizedBox(height: chrome.bottomHeightFor(location), child: bottom),
      ],
    );
  }
}

class _FakeBoardRepository implements BoardRepository {
  _FakeBoardRepository(this.board);

  final AgileBoard board;

  /// Searches the way the server does: the title holds the text, any case.
  List<Issue> _found(BoardQuery query) {
    final text = query.text.trim().toLowerCase();
    return [
      for (final card in const [_login, _notes])
        if (text.isEmpty || card.title.toLowerCase().contains(text)) card,
    ];
  }

  @override
  Future<BoardWallPage> wall(
    String boardId, {
    String? sprintId,
    int size = kBoardPageSize,
    BoardQuery query = BoardQuery.all,
  }) async {
    final cards = _found(query);
    return BoardWallPage(
      board: board,
      sprints: const [],
      columns: [
        BoardColumnView(
          name: 'Open',
          states: const ['OPEN'],
          issues: cards,
          total: cards.length,
        ),
      ],
    );
  }

  @override
  Future<BoardFacets> facets(
    String boardId, {
    String? sprintId,
    bool backlog = false,
    BoardCardShape shape = BoardCardShape.wall,
  }) async => BoardFacets.empty;

  /// A Scrum board's backlog holds the same cards; it has no sprints.
  @override
  Future<BoardCardPage> cards(
    String boardId, {
    String? column,
    String? sprintId,
    bool backlog = false,
    bool? dated,
    int page = 0,
    int size = kBoardPageSize,
    bool summary = false,
    BoardQuery query = BoardQuery.all,
  }) async {
    final cards = backlog ? _found(query) : const <Issue>[];
    return BoardCardPage(
      items: cards,
      total: cards.length,
      summary: summary ? const [] : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> projects({bool archived = false}) async => const [
    Project(id: 'p1', key: 'MOB', name: 'Mobile App'),
  ];

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async => const [
    Project(id: 'p1', key: 'MOB', name: 'Mobile App'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeTeamRepository implements TeamRepository {
  @override
  Future<List<Team>> teams() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Both boards read their cards from the board's own endpoints; these tests
/// change none.
class _FakeIssueRepository implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUserRepository implements UserRepository {
  @override
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeSprintRepository implements SprintRepository {
  @override
  Future<List<Sprint>> sprints(
    String boardId, {
    bool includeArchived = false,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc() : super(const AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
