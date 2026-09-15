import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/sprint_repository.dart';
import 'package:hinata/features/sprint/planning/sprint_planning_cubit.dart';

Issue _card(
  String id, {
  String? sprintId,
  String title = 'Card',
  int? points,
}) => Issue(
  id: id,
  projectId: 'p1',
  readableId: 'HIN-$id',
  title: '$title $id',
  state: 'Open',
  sprintId: sprintId,
  storyPoints: points,
);

/// Longer than every delay the planning is given below.
const _settle = Duration(milliseconds: 80);

/// The server behind the planning: its cards, handed out in pages, with
/// totals and summaries the way the real one computes them.
class _Server implements BoardRepository {
  _Server(this.issues);

  final List<Issue> issues;
  final reads =
      <
        ({String? sprintId, bool backlog, int page, int size, BoardQuery query})
      >[];
  Object? failure;

  List<Issue> _kept({
    String? sprintId,
    required bool backlog,
    required BoardQuery query,
  }) => [
    for (final card in issues)
      if ((backlog ? card.sprintId == null : card.sprintId == sprintId) &&
          (!query.hasText ||
              card.title.toLowerCase().contains(
                query.text.trim().toLowerCase(),
              )))
        card,
  ];

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
    reads.add((
      sprintId: sprintId,
      backlog: backlog,
      page: page,
      size: size,
      query: query,
    ));
    final failure = this.failure;
    if (failure != null) throw failure;
    final kept = _kept(sprintId: sprintId, backlog: backlog, query: query);
    return BoardCardPage(
      items: kept.skip(page * size).take(size).toList(),
      total: kept.length,
      summary: summary
          ? [
              BoardStateSummary(
                state: 'Open',
                resolved: false,
                count: kept.length,
                points: kept.fold(
                  0,
                  (sum, card) => sum + (card.storyPoints ?? 0),
                ),
              ),
            ]
          : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Sprints implements SprintRepository {
  int calls = 0;
  Object? failure;

  @override
  Future<List<Sprint>> sprints(
    String boardId, {
    bool includeArchived = false,
  }) async {
    calls++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return const [
      Sprint(id: 's1', name: 'Sprint 1'),
      Sprint(id: 's2', name: 'Sprint 2'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Applies a change to the server's cards, or refuses it, and counts how many
/// changes were under way at once.
class _Issues implements IssueRepository {
  _Issues(this.server);

  final _Server server;
  Object? refusal;
  int _running = 0;
  int mostAtOnce = 0;

  @override
  Future<Issue> updateIssue(String id, Map<String, dynamic> patch) async {
    _running++;
    mostAtOnce = math.max(mostAtOnce, _running);
    try {
      await Future<void>.delayed(Duration.zero);
      final failure = refusal;
      if (failure != null) throw failure;
      final at = server.issues.indexWhere((card) => card.id == id);
      final card = server.issues[at];
      final updated = patch.containsKey('sprintId')
          ? card.copyWith(
              sprintId: (patch['sprintId'] as String).isEmpty
                  ? null
                  : patch['sprintId'] as String,
            )
          : card.copyWith(storyPoints: patch['storyPoints'] as int?);
      server.issues[at] = updated;
      return updated;
    } finally {
      _running--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Server server;
  late _Issues issues;
  late _Sprints sprints;

  setUp(() {
    server = _Server([
      for (var i = 1; i <= 60; i++) _card('a$i', sprintId: 's1', points: 1),
      for (var i = 1; i <= 3; i++) _card('b$i', sprintId: 's2', points: 2),
      for (var i = 1; i <= 30; i++) _card('c$i'),
    ]);
    issues = _Issues(server);
    sprints = _Sprints();
  });

  SprintPlanningCubit planningOver() {
    final cubit = SprintPlanningCubit(
      boards: server,
      issues: issues,
      sprints: sprints,
      boardId: 'b1',
      searchDelay: const Duration(milliseconds: 20),
      filterDelay: const Duration(milliseconds: 20),
      refreshDelay: const Duration(milliseconds: 20),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<List<String>> errorsWhile(
    SprintPlanningCubit planning,
    Future<void> Function() act,
  ) async {
    final errors = <String>[];
    final listening = planning.stream.listen((state) {
      if (state.errorKey != null) errors.add(state.errorKey!);
    });
    await act();
    await Future<void>.delayed(Duration.zero);
    await listening.cancel();
    return errors;
  }

  group('reading', () {
    test(
      'reads every sprint with its first page and summary, and the backlog page',
      () async {
        final planning = planningOver();

        await planning.load();

        final first = planning.state.containerOf('s1');
        expect(planning.state.status, SprintPlanningStatus.ready);
        expect(first.items, hasLength(kSprintPageSize));
        expect(first.total, 60);
        expect(
          first.points,
          60,
          reason: 'the head counts every card, not the loaded',
        );
        expect(planning.state.containerOf('s2').items, hasLength(3));
        expect(planning.state.backlog, hasLength(kBacklogPageSize));
        expect(planning.state.backlogTotal, 30);
      },
    );

    test('a sprint reads its next page once', () async {
      final planning = planningOver();
      await planning.load();
      final before = server.reads.length;

      await Future.wait([planning.loadMore('s1'), planning.loadMore('s1')]);

      expect(server.reads.length, before + 1);
      expect(planning.state.containerOf('s1').items, hasLength(60));
      expect(planning.state.containerOf('s1').hasMore, isFalse);
    });

    test('the backlog shows the page it is asked for', () async {
      final planning = planningOver();
      await planning.load();

      await planning.showBacklogPage(2);

      expect(planning.state.backlogPage, 2);
      expect(planning.state.backlog.map((card) => card.id), [
        'c25',
        'c26',
        'c27',
        'c28',
        'c29',
        'c30',
      ]);
    });

    test(
      'a backlog page that does not come leaves the page on screen, and says why',
      () async {
        final planning = planningOver();
        await planning.load();
        final onScreen = [for (final card in planning.state.backlog) card.id];
        server.failure = ApiFailure('errors.network');

        final errors = await errorsWhile(
          planning,
          () => planning.showBacklogPage(2),
        );

        expect(planning.state.backlogPage, 0);
        expect([for (final card in planning.state.backlog) card.id], onScreen);
        expect(errors, ['errors.network']);
      },
    );

    test('reads again only the sprints it is told to', () async {
      final planning = planningOver();
      await planning.load();
      server.issues.add(_card('a61', sprintId: 's1', points: 1));
      final before = server.reads.length;

      await planning.rereadSprints({'s1'});

      expect(planning.state.containerOf('s1').total, 61);
      expect(server.reads.skip(before).map((read) => read.sprintId), ['s1']);
    });
  });

  group('narrowing', () {
    test(
      'a search waits for the last letter and starts the backlog at its first page',
      () async {
        final planning = planningOver();
        await planning.load();
        await planning.showBacklogPage(1);
        final before = server.reads.length;

        planning
          ..narrow(const BoardQuery(text: 'car'))
          ..narrow(const BoardQuery(text: 'card c1'));
        expect(
          server.reads.length,
          before,
          reason: 'nothing asked while typing',
        );
        await Future<void>.delayed(_settle);

        expect(planning.state.query.text, 'card c1');
        expect(planning.state.backlogPage, 0);
        expect(
          planning.state.backlog.map((card) => card.id),
          everyElement(startsWith('c1')),
        );
      },
    );

    test(
      'the planning lists every issue type, whatever shape it is narrowed with',
      () async {
        final planning = planningOver();
        await planning.load();

        planning.narrow(const BoardQuery(text: 'card'));
        await Future<void>.delayed(_settle);

        expect(server.reads.last.query.shape, BoardCardShape.planning);
        expect(planning.state.narrowed, isTrue);
      },
    );

    test(
      'a narrowed planning reads a sprint whole to start or complete it',
      () async {
        final planning = planningOver();
        await planning.load();
        final before = server.reads.length;

        expect((await planning.summaryOf('s1')).cardCount, 60);
        expect(
          server.reads.length,
          before,
          reason: 'the head counts it already',
        );

        planning.narrow(const BoardQuery(text: 'card a1'));
        await Future<void>.delayed(_settle);
        expect(planning.state.containerOf('s1').total, 11);

        expect((await planning.summaryOf('s1')).cardCount, 60);
        expect(server.reads.last.size, 0);
        expect(server.reads.last.query, SprintPlanningState.everything);
      },
    );
  });

  group('changing', () {
    test(
      'a card pulled into a sprint moves at once and both ends are read again',
      () async {
        final planning = planningOver();
        await planning.load();
        final card = planning.state.backlog.first;

        final moving = planning.moveToSprint(card, 's2');

        expect(planning.state.containerOf('s2').items.first.id, card.id);
        expect(planning.state.containerOf('s2').total, 4);
        expect(planning.state.backlogTotal, 29);
        expect(await moving, isNull);
        expect(planning.state.containerOf('s2').total, 4);
        expect(
          planning.state.backlog.map((c) => c.id),
          isNot(contains(card.id)),
        );
        expect(
          server.reads.where((read) => read.sprintId == 's2'),
          hasLength(2),
        );
      },
    );

    test(
      'a refused move is undone by what the server holds, with the reason',
      () async {
        final planning = planningOver();
        await planning.load();
        issues.refusal = ApiFailure('error.accessDenied');
        String? refusal;

        final errors = await errorsWhile(planning, () async {
          refusal = await planning.moveToSprint(
            planning.state.backlog.first,
            's2',
          );
        });

        expect(refusal, 'error.accessDenied');
        expect(errors, ['error.accessDenied']);
        expect(planning.state.containerOf('s2').total, 3);
        expect(planning.state.backlogTotal, 30);
      },
    );

    test(
      'a refused move is taken back at once, even when the planning cannot be read again',
      () async {
        final planning = planningOver();
        await planning.load();
        final card = planning.state.backlog.first;
        issues.refusal = ApiFailure('error.accessDenied');
        sprints.failure = ApiFailure('errors.network');

        final refusal = await planning.moveToSprint(card, 's2');

        expect(refusal, 'error.accessDenied');
        expect(planning.state.containerOf('s2').total, 3);
        expect(planning.state.backlog.first.id, card.id);
        expect(planning.state.backlogTotal, 30);
      },
    );

    test(
      'an estimate shows at once and the sprint head counts it after',
      () async {
        final planning = planningOver();
        await planning.load();
        final card = planning.state.containerOf('s2').items.first;

        final estimating = planning.estimate(card, 8);

        expect(planning.state.containerOf('s2').items.first.storyPoints, 8);
        expect(await estimating, isNull);
        expect(planning.state.containerOf('s2').points, 12);
      },
    );

    test(
      'picked cards move a few at a time, and only their sprints are read again',
      () async {
        final planning = planningOver();
        await planning.load();
        final picked = [
          for (final card in planning.state.backlog.take(10)) card.id,
        ];
        final listed = sprints.calls;
        final before = server.reads.length;

        expect(await planning.moveAll(picked, 's2'), isNull);

        expect(issues.mostAtOnce, lessThanOrEqualTo(4));
        expect(planning.state.containerOf('s2').total, 13);
        expect(sprints.calls, listed, reason: 'no read of the whole planning');
        expect(
          {
            for (final read in server.reads.skip(before))
              read.backlog ? 'backlog' : read.sprintId,
          },
          {'s2', 'backlog'},
        );
      },
    );

    test(
      'cards picked on a backlog page no longer on screen move as well',
      () async {
        final planning = planningOver();
        await planning.load();
        final picked = [
          for (final card in planning.state.backlog.take(2)) card.id,
        ];
        await planning.showBacklogPage(1);

        expect(await planning.moveAll(picked, 's2'), isNull);

        expect(
          [
            for (final card in server.issues)
              if (picked.contains(card.id)) card.sprintId,
          ],
          ['s2', 's2'],
        );
        expect(planning.state.containerOf('s2').total, 5);
      },
    );

    test(
      'a refused move of picked cards puts every one of them back',
      () async {
        final planning = planningOver();
        await planning.load();
        final picked = [
          for (final card in planning.state.backlog.take(3)) card.id,
        ];
        issues.refusal = ApiFailure('error.accessDenied');

        expect(await planning.moveAll(picked, 's2'), 'error.accessDenied');

        expect(planning.state.containerOf('s2').total, 3);
        expect(planning.state.backlogTotal, 30);
      },
    );
  });
}
