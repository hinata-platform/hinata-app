import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/features/board/board_edit_cubit.dart';

const _board = AgileBoard(id: 'b1', name: 'Wall');

class _Boards implements BoardRepository {
  final asked = <List<Object?>>[];
  Object? refusal;

  Future<AgileBoard> _answer(List<Object?> call) async {
    asked.add(call);
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return _board;
  }

  @override
  Future<AgileBoard> createBoard(
    String name,
    List<String> projectIds, {
    BoardType type = BoardType.kanban,
  }) => _answer(['create', name, projectIds, type]);

  @override
  Future<AgileBoard> renameBoard(String boardId, String name) =>
      _answer(['rename', boardId, name]);

  @override
  Future<AgileBoard> updateBoardProjects(
    String boardId,
    List<String> projectIds,
  ) => _answer(['projects', boardId, projectIds]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Boards boards;
  late BoardEditCubit edit;

  setUp(() {
    boards = _Boards();
    edit = BoardEditCubit(boards);
  });

  tearDown(() => edit.close());

  test('creates, renames and re-scopes a board and hands it back', () async {
    expect(await edit.create('Wall', ['A']), _board);
    expect(
      await edit.create('Sprints', ['A', 'B'], type: BoardType.scrum),
      _board,
    );
    expect(await edit.rename('b1', 'Neu'), _board);
    expect(await edit.updateProjects('b1', ['A', 'C']), _board);

    expect(boards.asked, [
      [
        'create',
        'Wall',
        ['A'],
        BoardType.kanban,
      ],
      [
        'create',
        'Sprints',
        ['A', 'B'],
        BoardType.scrum,
      ],
      ['rename', 'b1', 'Neu'],
      [
        'projects',
        'b1',
        ['A', 'C'],
      ],
    ]);
  });

  test('passes a refusal on as it came', () async {
    final refusal = ApiFailure('error.accessDenied');
    boards.refusal = refusal;

    await expectLater(edit.create('Wall', ['A']), throwsA(refusal));
    await expectLater(edit.rename('b1', 'Neu'), throwsA(refusal));
    await expectLater(edit.updateProjects('b1', ['A']), throwsA(refusal));
  });
}
