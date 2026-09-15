import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../events/board_events.dart';
import '../models/board_page_models.dart';
import '../models/deletion_models.dart';
import '../models/work_models.dart';

/// Agile boards: listing, creation, the wall read page by page, and cascading
/// deletion.
///
/// The mutations that change what a *list* of boards shows announce themselves
/// on [BoardEvents], so every screen that renders boards re-fetches without the
/// screen that made the change having to know who else is on screen. See
/// [BoardEvents] for why that lives here rather than at each call site.
///
/// A board id goes into a path encoded: it can come from an address anybody
/// can write (HIN-114), and `a/b` has to stay one segment.
class BoardRepository {
  BoardRepository(this._api);

  final ApiClient _api;

  /// The path of one board, its id encoded.
  static String _boardPath(String boardId) =>
      '/api/v1/boards/${Uri.encodeComponent(boardId)}';

  Future<List<AgileBoard>> boards({String? projectId}) async =>
      ((await _api.get('/api/v1/boards', query: {'projectId': ?projectId}))
              as List<dynamic>)
          .map((b) => AgileBoard.fromJson(b as Map<String, dynamic>))
          .toList();

  Future<AgileBoard> createBoard(
    String name,
    List<String> projectIds, {
    BoardType type = BoardType.kanban,
  }) async {
    final board = AgileBoard.fromJson(
      await _api.post(
            '/api/v1/boards',
            body: {
              'name': name,
              'projectIds': projectIds,
              'type': type == BoardType.scrum ? 'SCRUM' : 'KANBAN',
            },
          )
          as Map<String, dynamic>,
    );
    BoardEvents.instance.notifyChanged();
    return board;
  }

  /// Renames a board (management action — server enforces owner/lead/admin).
  Future<AgileBoard> renameBoard(String boardId, String name) async {
    final board = AgileBoard.fromJson(
      await _api.patch(_boardPath(boardId), body: {'name': name})
          as Map<String, dynamic>,
    );
    BoardEvents.instance.notifyChanged();
    return board;
  }

  /// Changes which projects a board spans (management action — the server also
  /// re-checks membership on every project in the new set, so widening a board
  /// can never be used to reach a project the caller isn't in).
  Future<AgileBoard> updateBoardProjects(
    String boardId,
    List<String> projectIds,
  ) async {
    final board = AgileBoard.fromJson(
      await _api.patch(
            _boardPath(boardId),
            body: {'projectIds': projectIds},
          )
          as Map<String, dynamic>,
    );
    BoardEvents.instance.notifyChanged();
    return board;
  }

  /// Stores a hand-made column layout. The server validates it as a whole: every
  /// status of every spanned project needs exactly one column, and no column may
  /// hold two statuses of the same project (a drop there would be ambiguous).
  Future<AgileBoard> updateBoardColumns(
    String boardId,
    List<BoardColumnLayout> columns,
  ) async => AgileBoard.fromJson(
    await _api.patch(
          _boardPath(boardId),
          body: {
            'columns': [for (final c in columns) c.toJson()],
          },
        )
        as Map<String, dynamic>,
  );

  /// Drops a hand-made layout and goes back to columns derived from the spanned
  /// workflows.
  Future<AgileBoard> resetBoardColumns(String boardId) async =>
      AgileBoard.fromJson(
        await _api.patch(
              _boardPath(boardId),
              body: {'resetColumns': true},
            )
            as Map<String, dynamic>,
      );

  /// The wall in one request: the columns, each with its number of cards and
  /// the first [size] of them in board order, plus the people, epics and
  /// parents those cards name. The server searches and filters by [query].
  /// Without [sprintId] the board's active sprint applies; a [size] of 0
  /// returns the columns alone.
  Future<BoardWallPage> wall(
    String boardId, {
    String? sprintId,
    int size = kBoardPageSize,
    BoardQuery query = BoardQuery.all,
  }) async => BoardWallPage.fromJson(
    await _api.get(
          '${_boardPath(boardId)}/wall',
          query: {'sprintId': ?sprintId, 'size': size, ...query.toQuery()},
        )
        as Map<String, dynamic>,
  );

  /// One page of cards, in board order unless it is the timeline's: of the
  /// [column] of that name, of the sprint [sprintId], or of the [backlog]. With
  /// none of the three it is every card of the board. [dated] splits the
  /// timeline into the cards with a date and those without; [summary] adds
  /// the whole query's cards by state.
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
  }) async => BoardCardPage.fromJson(
    await _api.get(
          '${_boardPath(boardId)}/cards',
          query: {
            'column': ?column,
            'sprintId': ?sprintId,
            if (backlog) 'backlog': true,
            'dated': ?dated,
            'page': page,
            'size': size,
            if (summary) 'summary': true,
            ...query.toQuery(),
          },
        )
        as Map<String, dynamic>,
  );

  /// What the filter and the row of faces can offer over every card of the
  /// board: the people, reporters, labels and epics on its cards, the states
  /// of its projects, and the types and priorities a card of [shape] can have.
  Future<BoardFacets> facets(
    String boardId, {
    BoardCardShape shape = BoardCardShape.wall,
  }) async => BoardFacets.fromJson(
    await _api.get(
          '${_boardPath(boardId)}/facets',
          query: {if (shape != BoardCardShape.wall) 'shape': shape.name},
        )
        as Map<String, dynamic>,
  );

  /// The links between the board's cards [ids], at most [kBoardMaxLinkCards]
  /// of them: the connectors the timeline draws between the cards it has
  /// loaded, without reading every issue of the board's projects for them.
  Future<List<GanttLink>> links(String boardId, List<String> ids) async =>
      ((await _api.post('${_boardPath(boardId)}/links', body: {'ids': ids}))
              as List<dynamic>)
          .map((l) => GanttLink.fromJson(l as Map<String, dynamic>))
          .toList();

  /// Counts driving the board delete confirmation (sprints, issues to detach).
  Future<BoardDeletionImpact> boardDeletionImpact(String boardId) async =>
      BoardDeletionImpact.fromJson(
        await _api.get('${_boardPath(boardId)}/deletion-impact')
            as Map<String, dynamic>,
      );

  /// Raw SSE byte stream of a board deletion (parse with [parseSse] →
  /// [DeleteEvent.tryParse]). Cancel via [cancelToken] to abort listening.
  Future<Stream<List<int>>> boardDeleteStream(
    String boardId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '${_boardPath(boardId)}/delete-stream',
    cancelToken: cancelToken,
  );
}
