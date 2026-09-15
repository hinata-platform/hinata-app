/// What a board's cards refer to: the epics they roll up to and the people
/// they name.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/board/board_people_strip.dart';
import 'package:hinata/features/board/board_swimlanes.dart';

Issue _issue(
  String id, {
  String type = 'TASK',
  String? parentId,
  String? epicId,
}) => Issue(
  id: id,
  projectId: 'p1',
  readableId: 'HIN-$id',
  title: 'Issue $id',
  state: 'OPEN',
  type: type,
  parentId: parentId,
  epicId: epicId,
);

void main() {
  test(
    'the epics a board names are those its filter offers and its cards refer to, each once, in key order',
    () {
      final epics = boardEpics(
        [_issue('3', type: 'EPIC'), _issue('1', type: 'EPIC')],
        [_issue('1', type: 'EPIC'), _issue('2', type: 'EPIC'), _issue('9')],
      );

      expect(epics.map((epic) => epic.id), ['1', '2', '3']);
    },
  );

  group('the epic a card rolls up to', () {
    test('is the one the server names on the card, before any parent', () {
      expect(
        boardEpicOf(
          _issue('sub', type: 'SUBTASK', parentId: 'story', epicId: 'e9'),
          const {},
        ),
        'e9',
      );
    });

    test(
      'is its parent for a work item and its grandparent for a sub-task',
      () {
        final byId = {
          'e1': _issue('e1', type: 'EPIC'),
          'story': _issue('story', parentId: 'e1'),
        };

        expect(boardEpicOf(_issue('story', parentId: 'e1'), byId), 'e1');
        expect(
          boardEpicOf(_issue('sub', type: 'SUBTASK', parentId: 'story'), byId),
          'e1',
        );
        expect(boardEpicOf(_issue('lone'), byId), isNull);
      },
    );
  });

  test(
    'the people of a board are named, pictured where they have a picture, and addressed as they asked',
    () {
      final people = boardPeople(const [
        DirectoryUser(
          id: 'u1',
          username: 'ada',
          displayName: 'Ada',
          avatarUrl: 'https://img.example/ada.png',
          pronouns: 'she/her',
        ),
        DirectoryUser(
          id: 'u2',
          username: 'bob',
          displayName: 'Bob',
          avatarUrl: '',
        ),
      ]);

      expect(people.names, {'u1': 'Ada', 'u2': 'Bob'});
      expect(people.avatars, {'u1': 'https://img.example/ada.png'});
      expect(people.pronouns.keys, ['u1']);
    },
  );
}
