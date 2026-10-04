import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/board_page_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/features/board/board_columns_editor_cubit.dart';

const _board = AgileBoard(id: 'b1', name: 'Wall');

class _Boards implements BoardRepository {
  final asked = <List<Object?>>[];
  Object? refusal;

  Future<T> _answer<T>(List<Object?> call, T value) async {
    asked.add(call);
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return value;
  }

  @override
  Future<BoardWallPage> wall(
    String boardId, {
    String? sprintId,
    int size = kBoardPageSize,
    BoardQuery query = BoardQuery.all,
  }) => _answer([
    'wall',
    boardId,
    sprintId,
    size,
  ], const BoardWallPage(board: _board, sprints: [], columns: []));

  @override
  Future<AgileBoard> updateBoardColumns(
    String boardId,
    List<BoardColumnLayout> columns,
  ) => _answer(['update', boardId, columns], _board);

  @override
  Future<AgileBoard> resetBoardColumns(String boardId) =>
      _answer(['reset', boardId], _board);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Projects implements ProjectRepository {
  final asked = <List<String>>[];

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async {
    asked.add(ids);
    return [for (final id in ids) Project(id: id, key: id, name: id)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Boards boards;
  late _Projects projects;
  late BoardColumnsEditorCubit editor;

  setUp(() {
    boards = _Boards();
    projects = _Projects();
    editor = BoardColumnsEditorCubit(
      boards: boards,
      projects: projects,
      boardId: 'b1',
    );
  });

  tearDown(() => editor.close());

  test('reads the layout without cards, and the projects behind it', () async {
    final layout = await editor.layout();
    final resolved = await editor.projects(['A', 'B']);

    expect(layout.board, _board);
    expect(boards.asked, [
      ['wall', 'b1', null, 0],
    ]);
    expect(projects.asked, [
      ['A', 'B'],
    ]);
    expect([for (final p in resolved) p.id], ['A', 'B']);
  });

  test('saves and resets the board it edits', () async {
    const columns = [
      BoardColumnLayout(name: 'Los', states: ['Open']),
    ];

    expect(await editor.save(columns), _board);
    expect(await editor.reset(), _board);
    expect(boards.asked, [
      ['update', 'b1', columns],
      ['reset', 'b1'],
    ]);
  });

  test('passes a refusal on as it came', () async {
    final refusal = ApiFailure('error.accessDenied');
    boards.refusal = refusal;

    await expectLater(editor.layout(), throwsA(refusal));
    await expectLater(editor.save(const []), throwsA(refusal));
    await expectLater(editor.reset(), throwsA(refusal));
  });
}
