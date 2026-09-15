import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/work_models.dart';

Map<String, dynamic> _card(String id) => {
  'id': id,
  'projectId': 'p1',
  'readableId': 'HIN-$id',
  'title': 'Card $id',
  'state': 'Open',
  'type': 'TASK',
  'priority': 'NORMAL',
  'assigneeId': 'u1',
  'assigneeIds': const ['u1'],
  'epicId': 'e1',
  'subtaskCount': 2,
  'subtaskDoneCount': 1,
};

void main() {
  group('BoardWall', () {
    test('reads the columns with their totals, the people and the epics', () {
      final wall = BoardWall.fromJson({
        'board': const {
          'id': 'b1',
          'name': 'Board',
          'projectIds': ['p1'],
        },
        'sprints': const [
          {'id': 's1', 'name': 'Sprint 1'},
        ],
        'sprintId': 's1',
        'columns': [
          {
            'name': 'Open',
            'states': const ['Open'],
            'hue': 250,
            'total': 42,
            'issues': [_card('1'), _card('2')],
          },
        ],
        'users': const [
          {'id': 'u1', 'username': 'ada', 'displayName': 'Ada'},
        ],
        'refs': const [
          {
            'id': 'e1',
            'projectId': 'p1',
            'readableId': 'HIN-9',
            'title': 'Epic',
            'state': 'Open',
            'type': 'EPIC',
          },
        ],
      });

      expect(wall.sprintId, 's1');
      expect(wall.columns.single.count, 42);
      expect(wall.columns.single.issues, hasLength(2));
      expect(wall.columns.single.hasMore, isTrue);
      expect(wall.columns.single.issues.first.epicId, 'e1');
      expect(wall.users.single.displayName, 'Ada');
      expect(wall.refs.single.isEpic, isTrue);
      expect(wall.view.columns, wall.columns);
    });
  });

  test('a column of the old board view counts the cards it carries', () {
    final column = BoardColumnView.fromJson({
      'name': 'Open',
      'states': const ['Open'],
      'issues': [_card('1')],
    });

    expect(column.total, isNull);
    expect(column.count, 1);
    expect(column.hasMore, isFalse);
  });

  test('a card page carries its summary only when it was asked for', () {
    final withSummary = BoardCardPage.fromJson({
      'content': [_card('1')],
      'totalElements': 7,
      'summary': const [
        {'state': 'Done', 'resolved': true, 'count': 3, 'points': 8},
      ],
    });
    final without = BoardCardPage.fromJson(const {
      'content': [],
      'totalElements': 0,
    });

    expect(withSummary.total, 7);
    expect(withSummary.summary, const [
      BoardStateSummary(state: 'Done', resolved: true, count: 3, points: 8),
    ]);
    expect(without.summary, isNull);
    expect(without.items, isEmpty);
  });

  test('facets read every list and tolerate the ones left out', () {
    final facets = BoardFacets.fromJson(const {
      'assigneeIds': ['u1', 'u2'],
      'labels': ['ui'],
    });

    expect(facets.assigneeIds, ['u1', 'u2']);
    expect(facets.labels, ['ui']);
    expect(facets.reporterIds, isEmpty);
    expect(facets.epics, isEmpty);
  });

  group('BoardQuery', () {
    test('leaves empty facets out and sorts the rest', () {
      const query = BoardQuery(
        text: '  login ',
        states: {'IN PROGRESS', 'OPEN'},
        assigneeIds: {'u2', 'u1'},
        sprints: {BoardQuery.noSprint},
        shape: BoardCardShape.subtasks,
      );

      expect(query.toQuery(), {
        'q': 'login',
        'states': ['IN PROGRESS', 'OPEN'],
        'assigneeIds': ['u1', 'u2'],
        'sprints': ['__none__'],
        'shape': 'subtasks',
      });
      expect(BoardQuery.all.toQuery(), isEmpty);
    });

    test('is the same query whatever surrounds its text', () {
      expect(const BoardQuery(text: 'login '), const BoardQuery(text: 'login'));
      expect(
        const BoardQuery(text: 'a').withShape(BoardCardShape.timeline).shape,
        BoardCardShape.timeline,
      );
    });
  });
}
