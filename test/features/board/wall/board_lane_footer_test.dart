/// A grouped wall reads its columns on by itself.
///
/// A lane holds the cards of one group alone, and a column hands its cards over
/// in board order, so a group's cards may all sit past the first page: the Done
/// lane of an epic whose work is finished stays empty until the column has been
/// read that far. Nobody scrolls a board that already fills the screen to its
/// very end to find that out, so the column reads on under the lanes as long as
/// they need it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/board/board_swimlanes.dart';
import 'package:hinata/features/board/wall/board_wall_columns.dart';
import 'package:hinata/features/board/wall/board_wall_cubit.dart';

/// The epic whose lane the board is grouped into below.
const _epic = 'e1';

Issue _card(String id, {bool ofEpic = false}) => Issue(
  id: id,
  projectId: 'p1',
  readableId: 'HIN-$id',
  title: 'Card $id',
  state: 'Done',
  rank: 1,
  epicId: ofEpic ? _epic : null,
);

/// The server behind the wall: one column of [total] cards, of which it hands
/// out pages the way the real one does. From [epicFrom] on they belong to the
/// epic — the case that matters, where a lane's cards all sit past the first
/// page the wall reads.
class _Server implements BoardRepository {
  _Server(this.total, {this.epicFrom});

  final int total;
  final int? epicFrom;
  final pages = <({int page, int size})>[];
  Object? pageFailure;

  List<Issue> get _cards => [
    for (var i = 1; i <= total; i++)
      _card('d$i', ofEpic: epicFrom != null && i >= epicFrom!),
  ];

  @override
  Future<BoardWallPage> wall(
    String boardId, {
    String? sprintId,
    int size = kBoardPageSize,
    BoardQuery query = BoardQuery.all,
  }) async => BoardWallPage(
    board: const AgileBoard(id: 'b1', name: 'Board'),
    sprints: const [],
    sprintId: sprintId,
    columns: [
      BoardColumnView(
        name: 'Done',
        states: const ['Done'],
        issues: _cards.take(size).toList(),
        total: total,
      ),
    ],
  );

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
    pages.add((page: page, size: size));
    final failure = pageFailure;
    if (failure != null) throw failure;
    return BoardCardPage(
      items: _cards.skip(page * size).take(size).toList(),
      total: total,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Issues implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Server server;
  late BoardWallCubit wall;

  Future<void> openWall(int total, {int? epicFrom}) async {
    server = _Server(total, epicFrom: epicFrom);
    wall = BoardWallCubit(boards: server, issues: _Issues(), boardId: 'b1');
    addTearDown(wall.close);
    await wall.load();
    server.pages.clear();
  }

  /// The cards the column holds so far.
  List<Issue> loaded() => wall.state.column('Done')!.issues;

  /// The footer that stands under the column's lanes.
  Future<void> pumpLanes(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<BoardWallCubit>.value(
          value: wall,
          child: const Scaffold(body: BoardLaneFooter(name: 'Done')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a column under lanes reads on until it holds every card', (
    tester,
  ) async {
    await openWall(240);
    expect(loaded(), hasLength(kBoardPageSize));

    await pumpLanes(tester);

    expect(loaded(), hasLength(240));
    expect(
      [for (final page in server.pages) page.size],
      everyElement(kBoardLanePageSize),
      reason: 'lanes read in the largest pages the server hands over',
    );
  });

  testWidgets('it stops where the lanes hold enough, and says what is left', (
    tester,
  ) async {
    await openWall(kBoardLaneMaxCards + 40);

    await pumpLanes(tester);

    expect(loaded(), hasLength(kBoardLaneMaxCards));
    expect(
      find.text('board.laneLimit'),
      findsOneWidget,
      reason: 'past this the board offers the search and the filter instead',
    );
  });

  testWidgets('a lane whose cards all sit past the first page fills up', (
    tester,
  ) async {
    // The board in the report: every card of the epic's Done lane lies behind
    // the cards of everything else that was ever finished.
    await openWall(kBoardPageSize + 10, epicFrom: kBoardPageSize + 1);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<BoardWallCubit>.value(
          value: wall,
          child: Scaffold(
            body: BlocBuilder<BoardWallCubit, BoardWallState>(
              builder: (context, state) => BoardSwimlanes(
                columns: state.columns,
                lanes: [
                  BoardLane(
                    key: _epic,
                    header: const Text('epic'),
                    issues: [
                      for (final card in state.cards)
                        if (card.epicId == _epic) card,
                    ],
                  ),
                ],
                columnBuilder: (column, issues, lane, width) => SizedBox(
                  height: 600,
                  child: Text('${column.name}: ${issues.length}'),
                ),
                footerBuilder: (column) => BoardLaneFooter(name: column.name),
                // Only the footer reads on here: the lanes are never scrolled.
                onNearEnd: ({required retry}) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Done: 0'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Done: 10'), findsOneWidget);
  });

  testWidgets('a page that did not come stops it until the lanes move', (
    tester,
  ) async {
    await openWall(240);
    server.pageFailure = ApiFailure('errors.network');

    await pumpLanes(tester);

    expect(server.pages, hasLength(1), reason: 'not asked for over and over');
    expect(wall.state.failedColumns, {'Done'});

    server.pageFailure = null;
    readOnUnderLanes(wall, ['Done'], retry: true);
    await tester.pumpAndSettle();

    expect(loaded(), hasLength(240));
  });
}
