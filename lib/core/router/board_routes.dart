import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/board/board_links.dart';
import '../../features/board/board_screen.dart';
import '../../features/board/boards_screen.dart';
import '../../features/board/project_boards_screen.dart';
import 'linked_target.dart';

/// Wraps a screen into the page its route shows.
typedef RoutePage = Page<void> Function(GoRouterState state, Widget child);

/// The board overview, one board, and a project's boards.
///
/// A board sits *under* the list it was opened from: `/board/:id` beneath the
/// overview, `/projects/:id/boards/:boardId` beneath a project's boards. So a
/// `go` to a board builds both pages, the address names the board, a reload
/// comes back to it, and back still leads to the list (HIN-114). The list
/// beneath waits to read anything until it is on screen.
///
/// `/boards/:id` was a board's address before and stays one: the server hands
/// it out in search hits and notifications, and the published app knows no
/// other.
List<RouteBase> boardRoutes(RoutePage page) => [
  GoRoute(
    path: boardsLocation,
    pageBuilder: (_, state) => page(state, const BoardScreen()),
    routes: [
      GoRoute(
        path: ':id',
        pageBuilder: (_, state) => page(
          state,
          _board(
            state.pathParameters['id']!,
            sprintId: state.uri.queryParameters['sprint'],
            visit: LinkVisit.of(state),
          ),
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/boards/:id',
    // The query goes along: a search hit for a sprint names it (`?sprint=`).
    redirect: (_, state) => currentBoardLink(state.uri.toString()),
  ),
  GoRoute(
    path: '/projects/:id/boards',
    pageBuilder: (_, state) => page(
      state,
      ProjectBoardsScreen(projectId: state.pathParameters['id']!),
    ),
    routes: [
      GoRoute(
        path: ':boardId',
        pageBuilder: (_, state) => page(
          state,
          _board(
            state.pathParameters['boardId']!,
            sprintId: state.uri.queryParameters['sprint'],
            visit: LinkVisit.of(state),
          ),
        ),
      ),
    ],
  ),
];

/// Keyed by the board, like an issue: go_router keys a page by its pattern, so
/// going from one board to another would otherwise keep the first board's
/// state under the second one's address. The sprint is not in the key: a link
/// to another sprint of the board on screen switches the wall to it, and so
/// does the same link again ([visit]).
KanbanBoardScreen _board(String id, {String? sprintId, LinkVisit? visit}) =>
    KanbanBoardScreen(
      key: ValueKey('board-$id'),
      boardId: id,
      sprintId: sprintId,
      visit: visit,
    );
