import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/board/wall/board_wall_cubit.dart';

Issue _card(String id, String state, double rank, {String? title}) => Issue(
  id: id,
  projectId: 'p1',
  readableId: 'HIN-$id',
  title: title ?? 'Card $id',
  state: state,
  rank: rank,
);

/// The server behind the wall: every card of every column, in board order, of
/// which it hands out pages and totals the way the real one does.
class _Server implements BoardRepository {
  _Server(this.columns);

  final Map<String, List<Issue>> columns;
  final walls = <({BoardQuery query, String? sprintId, int size})>[];
  final pages = <({String column, int page, BoardQuery query})>[];

  /// Wall answers held back until a test lets them go, first asked first.
  final wallGates = <Completer<void>>[];
  Object? wallFailure;

  /// Answers every page with the first one, as a server whose order moved.
  bool repeatFirstPage = false;

  List<Issue> _kept(String column, BoardQuery query) => [
    for (final card in columns[column] ?? const <Issue>[])
      if (!query.hasText ||
          card.title.toLowerCase().contains(query.text.trim().toLowerCase()))
        card,
  ];

  @override
  Future<BoardWall> wall(
    String boardId, {
    String? sprintId,
    int size = kBoardPageSize,
    BoardQuery query = BoardQuery.all,
  }) async {
    walls.add((query: query, sprintId: sprintId, size: size));
    if (wallGates.isNotEmpty) await wallGates.removeAt(0).future;
    final failure = wallFailure;
    if (failure != null) throw failure;
    return BoardWall(
      board: const AgileBoard(id: 'b1', name: 'Board'),
      sprints: const [],
      sprintId: sprintId,
      columns: [
        for (final name in columns.keys)
          BoardColumnView(
            name: name,
            states: [name],
            issues: _kept(name, query).take(size).toList(),
            total: _kept(name, query).length,
          ),
      ],
    );
  }

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
    pages.add((column: column!, page: page, query: query));
    final kept = _kept(column, query);
    final start = repeatFirstPage ? 0 : page * size;
    return BoardCardPage(
      items: kept.skip(start).take(size).toList(),
      total: kept.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Issues implements IssueRepository {
  final patches = <({String id, Map<String, dynamic> patch})>[];
  Object? refusal;

  @override
  Future<Issue> updateIssue(String id, Map<String, dynamic> patch) async {
    patches.add((id: id, patch: patch));
    final failure = refusal;
    if (failure != null) throw failure;
    return _card(id, patch['state'] as String, 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Server server;
  late _Issues issues;

  setUp(() {
    server = _Server({
      'Open': [for (var i = 1; i <= 45; i++) _card('o$i', 'Open', i.toDouble())],
      'Done': [_card('d1', 'Done', 1), _card('d2', 'Done', 2)],
    });
    issues = _Issues();
  });

  BoardWallCubit wallOver() {
    final cubit = BoardWallCubit(
      boards: server,
      issues: issues,
      boardId: 'b1',
      searchDelay: const Duration(milliseconds: 20),
      refreshDelay: const Duration(milliseconds: 20),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  BoardColumnView column(BoardWallCubit wall, String name) =>
      wall.state.columns.firstWhere((column) => column.name == name);

  test('the first read shows each column with its total and first page', () async {
    final wall = wallOver();
    expect(wall.state.status, BoardWallStatus.loading);

    await wall.load();

    expect(wall.state.status, BoardWallStatus.ready);
    expect(column(wall, 'Open').count, 45);
    expect(column(wall, 'Open').issues, hasLength(kBoardPageSize));
    expect(column(wall, 'Open').hasMore, isTrue);
    expect(column(wall, 'Done').issues, hasLength(2));
  });

  test(
    'a column reads its next page once, however often it is scrolled to its end',
    () async {
      final wall = wallOver();
      await wall.load();

      await Future.wait([wall.loadMore('Open'), wall.loadMore('Open')]);

      expect(server.pages, hasLength(1));
      expect(column(wall, 'Open').issues, hasLength(45));
      expect(column(wall, 'Open').hasMore, isFalse);
      await wall.loadMore('Open');
      expect(server.pages, hasLength(1), reason: 'nothing is left to ask for');
    },
  );

  test('a page of cards the column holds already ends it', () async {
    final wall = wallOver();
    await wall.load();
    server.repeatFirstPage = true;

    await wall.loadMore('Open');

    expect(column(wall, 'Open').count, kBoardPageSize);
    expect(column(wall, 'Open').hasMore, isFalse);
  });

  test(
    'a search typed letter by letter is one read, and the cards stay meanwhile',
    () async {
      server = _Server({
        'Open': [
          _card('a', 'Open', 1, title: 'Fix the login'),
          _card('b', 'Open', 2, title: 'Release notes'),
        ],
      });
      final wall = wallOver();
      await wall.load();

      wall
        ..narrow(const BoardQuery(text: 'l'))
        ..narrow(const BoardQuery(text: 'lo'))
        ..narrow(const BoardQuery(text: 'login'));

      expect(server.walls, hasLength(1), reason: 'nothing asked while typing');
      expect(column(wall, 'Open').issues, hasLength(2));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.walls, hasLength(2));
      expect(server.walls.last.query.text, 'login');
      expect(column(wall, 'Open').issues.single.title, 'Fix the login');
    },
  );

  test('a changed filter reads at once', () async {
    final wall = wallOver();
    await wall.load();

    wall.narrow(const BoardQuery(states: {'OPEN'}));
    await Future<void>.delayed(Duration.zero);

    expect(server.walls, hasLength(2));
    expect(server.walls.last.query.states, {'OPEN'});
  });

  test('an answer overtaken by a newer read is not shown', () async {
    final wall = wallOver();
    await wall.load();
    final slow = Completer<void>();
    server.wallGates.add(slow);

    wall
      ..narrow(const BoardQuery(states: {'OPEN'}))
      ..narrow(const BoardQuery(states: {'DONE'}));
    await Future<void>.delayed(Duration.zero);
    expect(wall.state.query.states, {'DONE'});

    slow.complete();
    await Future<void>.delayed(Duration.zero);
    expect(wall.state.query.states, {'DONE'});
    expect(wall.state.refreshing, isFalse);
  });

  test('a moved card moves at once and stays when the server takes it', () async {
    final wall = wallOver();
    await wall.load();
    final card = column(wall, 'Open').issues.first;

    final moving = wall.move(card, 'Done', 'Done');

    expect(column(wall, 'Open').count, 44);
    expect(column(wall, 'Done').count, 3);
    final landed = column(wall, 'Done').issues.firstWhere((i) => i.id == card.id);
    expect(landed.state, 'Done');
    expect(await moving, isNull);
    expect(issues.patches.single.id, card.id);
    expect(issues.patches.single.patch, {'state': 'Done'});
    expect(server.walls, hasLength(1), reason: 'no search or filter to ask again');
  });

  test('a card the server refuses to move goes back, with the reason', () async {
    issues.refusal = ApiFailure('error.issue.unknownState');
    final wall = wallOver();
    await wall.load();
    final card = column(wall, 'Open').issues.first;
    final errors = <String>[];
    final listening = wall.stream.listen((state) {
      if (state.errorKey != null) errors.add(state.errorKey!);
    });

    expect(await wall.move(card, 'Done', 'Done'), 'error.issue.unknownState');
    await Future<void>.delayed(Duration.zero);
    await listening.cancel();

    expect(column(wall, 'Open').count, 45);
    expect(column(wall, 'Open').issues.first.id, card.id);
    expect(column(wall, 'Done').count, 2);
    expect(errors, ['error.issue.unknownState']);
  });

  test('a move under a search or a filter reads the wall again', () async {
    final wall = wallOver();
    await wall.load();
    wall.narrow(const BoardQuery(states: {'OPEN'}));
    await Future<void>.delayed(Duration.zero);

    await wall.move(column(wall, 'Open').issues.first, 'Done', 'Done');
    await Future<void>.delayed(Duration.zero);

    expect(server.walls, hasLength(3));
  });

  test('refreshing keeps every card someone scrolled through', () async {
    final wall = wallOver();
    await wall.load();
    await wall.loadMore('Open');

    await wall.refresh();

    expect(server.walls.last.size, 45);
    expect(column(wall, 'Open').issues, hasLength(45));
  });

  test('a burst of changes elsewhere is one read of the wall', () async {
    final wall = wallOver();
    await wall.load();

    wall
      ..refreshSoon()
      ..refreshSoon()
      ..refreshSoon();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(server.walls, hasLength(2));
  });

  test('a failed first read fails the wall, a failed later one keeps it', () async {
    server.wallFailure = ApiFailure('errors.network');
    final wall = wallOver();
    await wall.load();
    expect(wall.state.status, BoardWallStatus.failure);
    expect(wall.state.errorKey, 'errors.network');

    server.wallFailure = null;
    await wall.load();
    server.wallFailure = ApiFailure('errors.network');
    await wall.refresh();

    expect(wall.state.status, BoardWallStatus.ready);
    expect(wall.state.refreshing, isFalse);
    expect(column(wall, 'Open').issues, hasLength(kBoardPageSize));
  });
}
