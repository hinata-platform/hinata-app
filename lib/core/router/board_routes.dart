import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/board/board_links.dart';
import '../../features/board/board_screen.dart';
import '../../features/board/boards_screen.dart';
import '../../features/board/project_boards_screen.dart';

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
        pageBuilder: (_, state) =>
            page(state, _board(state.pathParameters['id']!)),
      ),
    ],
  ),
  GoRoute(
    path: '/boards/:id',
    redirect: (_, state) => boardLocation(state.pathParameters['id']!),
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
        pageBuilder: (_, state) =>
            page(state, _board(state.pathParameters['boardId']!)),
      ),
    ],
  ),
];

/// Keyed by the board, like an issue: go_router keys a page by its pattern, so
/// going from one board to another would otherwise keep the first board's
/// state under the second one's address.
KanbanBoardScreen _board(String id) =>
    KanbanBoardScreen(key: ValueKey('board-$id'), boardId: id);
