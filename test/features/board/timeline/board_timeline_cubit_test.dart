import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/features/board/timeline/board_timeline_cubit.dart';

Issue _card(String id, {DateTime? due}) => Issue(
  id: id,
  projectId: 'p1',
  readableId: 'HIN-$id',
  title: 'Card $id',
  state: 'Open',
  dueDate: due,
);

/// The server behind the timeline: its cards with a date and without, handed
/// out in pages, and a link between the first and the last card it is asked
/// about.
class _Server implements BoardRepository {
  _Server({required this.dated, required this.undated});

  final List<Issue> dated;
  final List<Issue> undated;
  final reads =
      <({bool dated, int page, String? sprintId, BoardQuery query})>[];
  final linked = <List<String>>[];
  Object? failure;
  Object? linkFailure;

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
    reads.add((dated: dated!, page: page, sprintId: sprintId, query: query));
    final failure = this.failure;
    if (failure != null) throw failure;
    final all = dated ? this.dated : undated;
    return BoardCardPage(
      items: all.skip(page * size).take(size).toList(),
      total: all.length,
    );
  }

  @override
  Future<List<GanttLink>> links(String boardId, List<String> ids) async {
    linked.add(ids);
    final failure = linkFailure;
    if (failure != null) throw failure;
    return [
      GanttLink(
        id: 'l${ids.length}',
        type: 'BLOCKS',
        sourceId: ids.first,
        targetId: ids.last,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Server server;
  final day = DateTime(2026, 9, 1);

  setUp(() {
    server = _Server(
      dated: [
        for (var i = 0; i < 150; i++)
          _card('d$i', due: day.add(Duration(days: i))),
      ],
      undated: [for (var i = 0; i < 20; i++) _card('u$i')],
    );
  });

  BoardTimelineCubit timelineOver() {
    final cubit = BoardTimelineCubit(
      boards: server,
      boardId: 'b1',
      refreshDelay: const Duration(milliseconds: 20),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  const search = BoardQuery(text: 'card');
  const whole = BoardQuery(shape: BoardCardShape.timeline);

  test(
    'shows the cards with a date, then those without, and the links between them',
    () async {
      final timeline = timelineOver();

      await timeline.show(sprintId: 's1', query: search);

      final state = timeline.state;
      expect(state.status, BoardTimelineStatus.ready);
      expect(state.dated, hasLength(kBoardMaxPageSize));
      expect(state.datedTotal, 150);
      expect(state.undated, hasLength(20));
      expect(state.query, search.copyWith(shape: BoardCardShape.timeline));
      expect(server.reads.map((read) => read.sprintId), everyElement('s1'));
      expect(server.linked.single, hasLength(120));
      expect(state.links.single.id, 'l120');
    },
  );

  test('the timeline on screen is not read again', () async {
    final timeline = timelineOver();
    await timeline.show(sprintId: null, query: search);

    await timeline.show(sprintId: null, query: search);

    expect(server.reads, hasLength(2));
  });

  test('reads on through the cards with a date before those without', () async {
    final timeline = timelineOver();
    await timeline.show(sprintId: null, query: BoardQuery.all);

    await timeline.loadMore();

    expect(server.reads.last, (
      dated: true,
      page: 1,
      sprintId: null,
      query: whole,
    ));
    expect(timeline.state.dated, hasLength(150));
    expect(timeline.state.hasMore, isFalse);
    expect(server.linked.last, hasLength(170));
    await timeline.loadMore();
    expect(server.reads, hasLength(3), reason: 'nothing is left to ask for');
  });

  test('a refresh keeps the depth someone scrolled to', () async {
    final timeline = timelineOver();
    await timeline.show(sprintId: null, query: BoardQuery.all);
    await timeline.loadMore();
    server.reads.clear();

    await timeline.refresh();

    expect(server.reads.where((read) => read.dated).map((read) => read.page), [
      0,
      1,
    ]);
    expect(timeline.state.dated, hasLength(150));
  });

  test(
    'a change while the timeline is away reads it again once it shows',
    () async {
      final timeline = timelineOver();
      await timeline.show(sprintId: null, query: BoardQuery.all);
      server.reads.clear();

      timeline.changed();
      await timeline.show(sprintId: null, query: BoardQuery.all);

      expect(server.reads, hasLength(2));
    },
  );

  test('links that do not come leave the connectors drawn', () async {
    final timeline = timelineOver();
    await timeline.show(sprintId: null, query: BoardQuery.all);
    server.linkFailure = ApiFailure('errors.network');

    await timeline.loadMore();

    expect(timeline.state.links.single.id, 'l120');
    expect(timeline.state.dated, hasLength(150));
  });

  test(
    'a timeline that did not come says so, and showing it again asks again',
    () async {
      server.failure = ApiFailure('errors.network');
      final timeline = timelineOver();
      await timeline.show(sprintId: null, query: BoardQuery.all);
      expect(timeline.state.status, BoardTimelineStatus.failure);
      expect(timeline.state.errorKey, 'errors.network');

      server.failure = null;
      await timeline.show(sprintId: null, query: BoardQuery.all);

      expect(timeline.state.status, BoardTimelineStatus.ready);
    },
  );
}
