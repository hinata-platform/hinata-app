import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/board/board_filter.dart';

void main() {
  test('hands every facet to the server under the name it reads it by', () {
    const filter = BoardFilter(
      states: {'OPEN'},
      types: {'BUG'},
      priorities: {'HIGH'},
      assignees: {'u1'},
      authors: {'u2'},
      labels: {'ui'},
      sprints: {BoardFilter.noSprint},
      epics: {'e1'},
    );

    expect(
      filter.toQuery(text: 'login', shape: BoardCardShape.planning),
      const BoardQuery(
        text: 'login',
        states: {'OPEN'},
        types: {'BUG'},
        priorities: {'HIGH'},
        assigneeIds: {'u1'},
        reporterIds: {'u2'},
        labels: {'ui'},
        sprints: {BoardQuery.noSprint},
        epicIds: {'e1'},
        shape: BoardCardShape.planning,
      ),
    );
  });

  test(
    'offers what the server gathered in upper case and once each, with the labels of the projects',
    () {
      final options = BoardFilterOptions.fromFacets(
        const BoardFacets(
          states: ['Open', 'OPEN', 'done', ''],
          types: ['bug'],
          priorities: ['high'],
          assigneeIds: ['u1'],
          reporterIds: ['u2'],
          labels: ['ui', ''],
        ),
        boardSprints: const [Sprint(id: 's1', name: 'Sprint 1')],
        projectLabels: const ['ui', 'api'],
        epicIds: const ['e1'],
      );

      expect(options.states, ['OPEN', 'DONE']);
      expect(options.types, ['BUG']);
      expect(options.priorities, ['HIGH']);
      expect(options.assignees, ['u1']);
      expect(options.authors, ['u2']);
      expect(options.sprints, ['s1']);
      expect(options.labels, ['ui', 'api']);
      expect(options.epics, ['e1']);
    },
  );

  test('is the same filter whatever order its values were picked in', () {
    expect(
      BoardFilter.empty
          .toggle(BoardFilterFacet.assignee, 'u2')
          .toggle(BoardFilterFacet.assignee, 'u1'),
      const BoardFilter(assignees: {'u1', 'u2'}),
    );
    expect(
      BoardFilter.empty
          .toggle(BoardFilterFacet.label, 'ui')
          .toggle(BoardFilterFacet.label, 'ui'),
      BoardFilter.empty,
    );
  });
}
