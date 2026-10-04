import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/features/board/board_list_cubit.dart';

class _Boards implements BoardRepository {
  final asked = <String?>[];

  @override
  Future<List<AgileBoard>> boards({String? projectId}) async {
    asked.add(projectId);
    return const [AgileBoard(id: 'b1', name: 'Wall')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Projects implements ProjectRepository {
  Object? refusal;

  @override
  Future<List<Project>> projects({
    bool archived = false,
    bool? template,
  }) async {
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return const [Project(id: 'A', key: 'A', name: 'Alpha')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Teams implements TeamRepository {
  @override
  Future<List<Team>> teams() async => const [
    Team(id: 't1', key: 'T', name: 'Team'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Boards boards;
  late _Projects projects;
  late BoardListCubit list;

  setUp(() {
    boards = _Boards();
    projects = _Projects();
    list = BoardListCubit(boards: boards, projects: projects, teams: _Teams());
  });

  tearDown(() => list.close());

  test(
    'reads the boards, of one project when asked, and what goes with them',
    () async {
      expect([for (final b in await list.boards()) b.id], ['b1']);
      await list.boards(projectId: 'A');
      expect(boards.asked, [null, 'A']);
      expect([for (final p in await list.projects()) p.id], ['A']);
      expect([for (final t in await list.teams()) t.id], ['t1']);
    },
  );

  test('passes a refusal on as it came', () async {
    final refusal = ApiFailure('error.accessDenied');
    projects.refusal = refusal;

    await expectLater(list.projects(), throwsA(refusal));
  });
}
