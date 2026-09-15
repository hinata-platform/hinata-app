import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/features/board/board_filter.dart';
import 'package:hinata/features/board/board_swimlanes.dart';
import 'package:hinata/features/board/head/board_head_cubit.dart';

/// Gathers facets the way the server does, naming in them the shape they were
/// gathered for, so a test can tell whose facets are shown.
class _Server implements BoardRepository {
  final asked = <BoardCardShape>[];

  /// Answers held back until a test lets them go, first asked first.
  final gates = <Completer<void>>[];
  Object? failure;

  @override
  Future<BoardFacets> facets(
    String boardId, {
    BoardCardShape shape = BoardCardShape.wall,
  }) async {
    asked.add(shape);
    if (gates.isNotEmpty) await gates.removeAt(0).future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return BoardFacets(labels: [shape.name]);
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

  const wall = BoardCardShape.wall;

  group('the facets', () {
    test('are read once when the board opens', () async {
      final head = headOver();

      await Future.wait([head.ensureFacets(wall), head.ensureFacets(wall)]);
      await head.ensureFacets(wall);

      expect(server.asked, hasLength(1));
      expect(head.state.facets.labels, ['wall']);
    });

    test(
      'are read again for the faces after a change only once a minute old',
      () async {
        final head = headOver();
        await head.ensureFacets(wall);
        head.facetsChanged();

        await head.ensureFacets(wall);
        expect(server.asked, hasLength(1));

        now = now.add(kBoardFacetsFresh);
        await head.ensureFacets(wall);
        expect(server.asked, hasLength(2));
      },
    );

    test(
      'are read again for the filter after any change, and after a minute without one',
      () async {
        final head = headOver();
        await head.ensureFacets(wall);

        await head.ensureFacets(wall, forFilter: true);
        expect(server.asked, hasLength(1), reason: 'nothing changed');

        head.facetsChanged();
        await head.ensureFacets(wall, forFilter: true);
        expect(server.asked, hasLength(2));

        now = now.add(kBoardFacetsFresh);
        await head.ensureFacets(wall, forFilter: true);
        expect(server.asked, hasLength(3));
      },
    );

    test('of a shape the board has left are never shown', () async {
      final head = headOver();
      final slow = Completer<void>();
      server.gates.add(slow);

      final first = head.ensureFacets(wall);
      await head.ensureFacets(BoardCardShape.subtasks);
      slow.complete();
      await first;

      expect(head.state.facets.labels, ['subtasks']);
    });

    test('that did not come are read again on the next call', () async {
      final head = headOver();
      server.failure = ApiFailure('errors.network');
      await head.ensureFacets(wall);
      expect(head.state.facets, BoardFacets.empty);

      server.failure = null;
      await head.ensureFacets(wall);

      expect(server.asked, hasLength(2));
      expect(head.state.facets.labels, ['wall']);
    });

    test('are gathered for the shape the board lists', () async {
      final head = headOver();

      await head.ensureFacets(BoardCardShape.planning);

      expect(server.asked.single, BoardCardShape.planning);
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
