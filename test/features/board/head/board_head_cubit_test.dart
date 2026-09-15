import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/features/board/board_filter.dart';
import 'package:hinata/features/board/board_swimlanes.dart';
import 'package:hinata/features/board/head/board_head_cubit.dart';

/// Gathers facets the way the server does, naming in them what they were
/// gathered over, so a test can tell whose facets are shown.
class _Server implements BoardRepository {
  final asked = <BoardFacetsScope>[];

  /// Answers held back until a test lets them go, first asked first.
  final gates = <Completer<void>>[];
  Object? failure;

  @override
  Future<BoardFacets> facets(
    String boardId, {
    String? sprintId,
    bool backlog = false,
    BoardCardShape shape = BoardCardShape.wall,
  }) async {
    asked.add(BoardFacetsScope(sprintId: sprintId, shape: shape));
    if (gates.isNotEmpty) await gates.removeAt(0).future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return BoardFacets(labels: [sprintId ?? 'board']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Server server;
  late DateTime now;

  setUp(() {
    server = _Server();
    now = DateTime(2026, 9, 15, 9);
  });

  BoardHeadCubit headOver() {
    final cubit = BoardHeadCubit(boards: server, boardId: 'b1', now: () => now);
    addTearDown(cubit.close);
    return cubit;
  }

  const board = BoardFacetsScope();

  group('the facets', () {
    test('are read once when the board opens', () async {
      final head = headOver();

      await Future.wait([head.ensureFacets(board), head.ensureFacets(board)]);
      await head.ensureFacets(board);

      expect(server.asked, hasLength(1));
      expect(head.state.facets.labels, ['board']);
    });

    test(
      'are read again for the faces after a change only once a minute old',
      () async {
        final head = headOver();
        await head.ensureFacets(board);
        head.facetsChanged();

        await head.ensureFacets(board);
        expect(server.asked, hasLength(1));

        now = now.add(kBoardFacetsFresh);
        await head.ensureFacets(board);
        expect(server.asked, hasLength(2));
      },
    );

    test(
      'are read again for the filter after any change, and after a minute without one',
      () async {
        final head = headOver();
        await head.ensureFacets(board);

        await head.ensureFacets(board, forFilter: true);
        expect(server.asked, hasLength(1), reason: 'nothing changed');

        head.facetsChanged();
        await head.ensureFacets(board, forFilter: true);
        expect(server.asked, hasLength(2));

        now = now.add(kBoardFacetsFresh);
        await head.ensureFacets(board, forFilter: true);
        expect(server.asked, hasLength(3));
      },
    );

    test('of a sprint the board has left are never shown', () async {
      final head = headOver();
      final slow = Completer<void>();
      server.gates.add(slow);

      final first = head.ensureFacets(const BoardFacetsScope(sprintId: 's1'));
      await head.ensureFacets(const BoardFacetsScope(sprintId: 's2'));
      slow.complete();
      await first;

      expect(head.state.facets.labels, ['s2']);
    });

    test('that did not come are read again on the next call', () async {
      final head = headOver();
      server.failure = ApiFailure('errors.network');
      await head.ensureFacets(board);
      expect(head.state.facets, BoardFacets.empty);

      server.failure = null;
      await head.ensureFacets(board);

      expect(server.asked, hasLength(2));
      expect(head.state.facets.labels, ['board']);
    });

    test('are gathered over the shape the board lists', () async {
      final head = headOver();

      await head.ensureFacets(
        const BoardFacetsScope(shape: BoardCardShape.planning),
      );

      expect(server.asked.single.shape, BoardCardShape.planning);
    });
  });

  test(
    'the search narrows the cards without redrawing the head, and grouping by sub-task makes them cards',
    () {
      const before = BoardHeadState();
      final typed = before.copyWith(text: 'login');
      final grouped = before.copyWith(grouping: BoardGrouping.subtask);

      expect(typed.narrowsOtherThan(before), isTrue);
      expect(typed.drawsOtherThan(before), isFalse);
      expect(before.copyWith(text: ' ').narrowsOtherThan(before), isFalse);
      expect(grouped.drawsOtherThan(before), isTrue);
      expect(grouped.wallShape, BoardCardShape.subtasks);
      expect(
        typed.query(BoardCardShape.timeline),
        const BoardQuery(text: 'login', shape: BoardCardShape.timeline),
      );
    },
  );

  test('a face toggled filters by that person, toggled again lets go', () {
    final head = headOver();

    head.toggleAssignee('u1');
    expect(head.state.filter, const BoardFilter(assignees: {'u1'}));

    head.toggleAssignee('u1');
    expect(head.state.filter, BoardFilter.empty);
  });
}
