import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/core_models.dart';
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

/// Longer than every delay the wall is given below.
const _settle = Duration(milliseconds: 80);

/// The server behind the wall: every card of every column, in board order, of
/// which it hands out pages and totals the way the real one does.
class _Server implements BoardRepository {
  _Server(this.columns);

  final Map<String, List<Issue>> columns;
  final walls = <({BoardQuery query, String? sprintId, int size})>[];
  final pages = <({String column, int page, int size, BoardQuery query})>[];

  /// Wall answers held back until a test lets them go, first asked first.
  final wallGates = <Completer<void>>[];
  Object? wallFailure;
  Object? pageFailure;

  /// The people every wall names.
  List<DirectoryUser> users = const [];

  /// Answers every page with the first one, as a server whose order moved.
  bool repeatFirstPage = false;

  /// Answers every page with no cards, as past the reach of a page.
  bool emptyPages = false;

  List<Issue> _kept(String column, BoardQuery query) => [
    for (final card in columns[column] ?? const <Issue>[])
      if (!query.hasText ||
          card.title.toLowerCase().contains(query.text.trim().toLowerCase()))
        card,
  ];

  @override
  Future<BoardWallPage> wall(
    String boardId, {
    String? sprintId,
    int size = kBoardPageSize,
    BoardQuery query = BoardQuery.all,
  }) async {
    walls.add((query: query, sprintId: sprintId, size: size));
    if (wallGates.isNotEmpty) await wallGates.removeAt(0).future;
    final failure = wallFailure;
    if (failure != null) throw failure;
    return BoardWallPage(
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
      users: users,
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
    pages.add((column: column!, page: page, size: size, query: query));
    final failure = pageFailure;
    if (failure != null) throw failure;
    final kept = _kept(column, query);
    final start = repeatFirstPage ? 0 : page * size;
    return BoardCardPage(
      items: emptyPages ? const [] : kept.skip(start).take(size).toList(),
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
      'Open': [
        for (var i = 1; i <= 45; i++) _card('o$i', 'Open', i.toDouble()),
      ],
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
      filterDelay: const Duration(milliseconds: 20),
      refreshDelay: const Duration(milliseconds: 20),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  BoardColumnView column(BoardWallCubit wall, String name) =>
      wall.state.column(name)!;

  group('reading', () {
    test(
      'the first read shows each column with its total and first page',
      () async {
        final wall = wallOver();
        expect(wall.state.status, BoardWallStatus.loading);

        await wall.load();

        expect(wall.state.status, BoardWallStatus.ready);
        expect(column(wall, 'Open').count, 45);
        expect(column(wall, 'Open').issues, hasLength(kBoardPageSize));
        expect(column(wall, 'Open').remaining, 45 - kBoardPageSize);
        expect(column(wall, 'Done').issues, hasLength(2));
      },
    );

    test('shows the sprint picked', () async {
      final wall = wallOver();
      await wall.load();

      await wall.showSprint('s2');

      expect(server.walls.last.sprintId, 's2');
      expect(wall.state.pickedSprintId, 's2');
      expect(wall.state.sprintId, 's2');
    });

    test(
      'a failed first read fails the wall, a failed later one keeps it',
      () async {
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
      },
    );

    test(
      'a read of the whole wall names only the people its cards name',
      () async {
        server.users = const [
          DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada'),
          DirectoryUser(id: 'u2', username: 'bob', displayName: 'Bob'),
        ];
        final wall = wallOver();
        await wall.load();
        expect(wall.state.users.keys, {'u1', 'u2'});
        server.users = const [
          DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada'),
        ];

        await wall.load();

        expect(wall.state.users.keys, {'u1'});
      },
    );

    test('a read that names the same people keeps their map', () async {
      server.users = const [
        DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada'),
      ];
      final wall = wallOver();
      await wall.load();
      final held = wall.state.users;

      await wall.refresh();

      expect(identical(wall.state.users, held), isTrue);
    });
  });

  group('reading on', () {
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
        expect(
          server.pages,
          hasLength(1),
          reason: 'nothing is left to ask for',
        );
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
      'an empty page ends the column instead of being asked for again',
      () async {
        final wall = wallOver();
        await wall.load();
        server.emptyPages = true;

        await wall.loadMore('Open');

        expect(column(wall, 'Open').count, kBoardPageSize);
        expect(column(wall, 'Open').hasMore, isFalse);
      },
    );

    test(
      'a page that does not come marks its column, which reads on when asked again',
      () async {
        final wall = wallOver();
        await wall.load();
        server.pageFailure = ApiFailure('errors.network');

        await wall.loadMore('Open');

        expect(wall.state.failedColumns, {'Open'});
        expect(wall.state.loadingMore, isEmpty);
        expect(column(wall, 'Open').issues, hasLength(kBoardPageSize));

        server.pageFailure = null;
        await wall.loadMore('Open');

        expect(wall.state.failedColumns, isEmpty);
        expect(column(wall, 'Open').issues, hasLength(45));
      },
    );
  });

  group('narrowing', () {
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

        expect(
          server.walls,
          hasLength(1),
          reason: 'nothing asked while typing',
        );
        expect(column(wall, 'Open').issues, hasLength(2));
        await Future<void>.delayed(_settle);
        expect(server.walls, hasLength(2));
        expect(server.walls.last.query.text, 'login');
        expect(column(wall, 'Open').issues.single.title, 'Fix the login');
      },
    );

    test('filters ticked in a row are one read', () async {
      final wall = wallOver();
      await wall.load();

      wall
        ..narrow(const BoardQuery(states: {'OPEN'}))
        ..narrow(const BoardQuery(states: {'OPEN', 'DONE'}));

      expect(server.walls, hasLength(1), reason: 'nothing asked while ticking');
      await Future<void>.delayed(_settle);
      expect(server.walls, hasLength(2));
      expect(server.walls.last.query.states, {'OPEN', 'DONE'});
    });

    test('an answer overtaken by a newer read is not shown', () async {
      final wall = wallOver();
      await wall.load();
      final slow = Completer<void>();
      server.wallGates.add(slow);

      wall.narrow(const BoardQuery(states: {'OPEN'}));
      await Future<void>.delayed(_settle);
      expect(wall.state.refreshing, isTrue);
      wall.narrow(const BoardQuery(states: {'DONE'}));
      await Future<void>.delayed(_settle);
      expect(wall.state.query.states, {'DONE'});

      slow.complete();
      await Future<void>.delayed(Duration.zero);
      expect(wall.state.query.states, {'DONE'});
      expect(wall.state.refreshing, isFalse);
    });

    test(
      'a failed search keeps the cards with their own query, and the same words ask again',
      () async {
        final wall = wallOver();
        await wall.load();
        server.wallFailure = ApiFailure('errors.network');

        wall.narrow(const BoardQuery(text: 'card o1'));
        await Future<void>.delayed(_settle);

        expect(wall.state.query, BoardQuery.all);
        expect(column(wall, 'Open').issues, hasLength(kBoardPageSize));

        server.wallFailure = null;
        wall.narrow(const BoardQuery(text: 'card o1'));
        await Future<void>.delayed(_settle);

        expect(server.walls, hasLength(3));
        expect(wall.state.query.text, 'card o1');
        expect(
          column(wall, 'Open').issues.map((card) => card.id),
          everyElement(startsWith('o1')),
        );
      },
    );
  });

  group('refreshing', () {
    test('a burst of changes elsewhere is one read of the wall', () async {
      final wall = wallOver();
      await wall.load();

      wall
        ..refreshSoon()
        ..refreshSoon()
        ..refreshSoon();
      await Future<void>.delayed(_settle);

      expect(server.walls, hasLength(2));
    });

    test(
      'a refresh keeps a column as deep as it was scrolled, reading only that one deeper',
      () async {
        final wall = wallOver();
        await wall.load();
        await wall.loadMore('Open');
        server.pages.clear();

        await wall.refresh();

        expect(server.walls.last.size, kBoardPageSize);
        expect(server.pages.single, (
          column: 'Open',
          page: 0,
          size: 45,
          query: BoardQuery.all,
        ));
        expect(column(wall, 'Open').issues, hasLength(45));
        expect(column(wall, 'Done').issues, hasLength(2));
      },
    );

    test(
      'past what a page holds, a refresh keeps the cards beyond it, each in one column only',
      () async {
        server = _Server({
          'Open': [
            for (var i = 1; i <= 150; i++) _card('o$i', 'Open', i.toDouble()),
          ],
          'Done': [_card('d1', 'Done', 1)],
        });
        final wall = wallOver();
        await wall.load();
        for (var i = 0; i < 4; i++) {
          await wall.loadMore('Open');
        }
        expect(column(wall, 'Open').issues, hasLength(150));
        // One card beyond the first hundred moved to Done meanwhile.
        final moved = server.columns['Open']!.removeAt(119);
        server.columns['Done']!.add(moved.copyWith(state: 'Done'));

        await wall.refresh();

        final open = [for (final card in column(wall, 'Open').issues) card.id];
        expect(open, hasLength(149));
        expect(open, isNot(contains('o120')));
        expect(
          column(wall, 'Done').issues.map((card) => card.id),
          contains('o120'),
        );
        expect(column(wall, 'Open').count, 149);
      },
    );

    test('a new search starts every column at its first page', () async {
      final wall = wallOver();
      await wall.load();
      await wall.loadMore('Open');
      server.pages.clear();

      wall.narrow(const BoardQuery(text: 'card'));
      await Future<void>.delayed(_settle);

      expect(server.pages, isEmpty);
      expect(column(wall, 'Open').issues, hasLength(kBoardPageSize));
    });
  });

  group('moving', () {
    test(
      'a moved card moves at once and stays when the server takes it',
      () async {
        final wall = wallOver();
        await wall.load();
        final card = column(wall, 'Open').issues.first;

        final moving = wall.move(card, 'Done', 'Done');

        expect(column(wall, 'Open').count, 44);
        expect(column(wall, 'Done').count, 3);
        final landed = column(
          wall,
          'Done',
        ).issues.firstWhere((i) => i.id == card.id);
        expect(landed.state, 'Done');
        expect(await moving, isNull);
        expect(issues.patches.single.id, card.id);
        expect(issues.patches.single.patch, {'state': 'Done'});
        await Future<void>.delayed(_settle);
        expect(
          server.walls,
          hasLength(1),
          reason: 'no search or filter to ask again',
        );
      },
    );

    test(
      'a card the server refuses to move goes back, with the reason',
      () async {
        issues.refusal = ApiFailure('error.issue.unknownState');
        final wall = wallOver();
        await wall.load();
        final card = column(wall, 'Open').issues.first;
        final errors = <String>[];
        final listening = wall.stream.listen((state) {
          if (state.errorKey != null) errors.add(state.errorKey!);
        });

        expect(
          await wall.move(card, 'Done', 'Done'),
          'error.issue.unknownState',
        );
        await Future<void>.delayed(Duration.zero);
        await listening.cancel();

        expect(column(wall, 'Open').count, 45);
        expect(column(wall, 'Open').issues.first.id, card.id);
        expect(column(wall, 'Done').count, 2);
        expect(errors, ['error.issue.unknownState']);
      },
    );

    test(
      'a move under a search or a filter reads the wall again a moment later',
      () async {
        final wall = wallOver();
        await wall.load();
        wall.narrow(const BoardQuery(states: {'OPEN'}));
        await Future<void>.delayed(_settle);
        expect(server.walls, hasLength(2));

        await wall.move(column(wall, 'Open').issues.first, 'Done', 'Done');
        expect(server.walls, hasLength(2), reason: 'changes gather first');
        await Future<void>.delayed(_settle);

        expect(server.walls, hasLength(3));
      },
    );

    test(
      'grouping alone narrows nothing, so a move reads nothing again',
      () async {
        final wall = wallOver();
        await wall.load();
        wall.narrow(const BoardQuery(shape: BoardCardShape.subtasks));
        await Future<void>.delayed(_settle);

        await wall.move(column(wall, 'Open').issues.first, 'Done', 'Done');
        await Future<void>.delayed(_settle);

        expect(server.walls, hasLength(2));
      },
    );
  });
}
