import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/features/board/project_boards_cubit.dart';

class _Boards implements BoardRepository {
  final asked = <String?>[];

  @override
  Future<List<AgileBoard>> boards({String? projectId}) async {
    asked.add(projectId);
    return const [
      AgileBoard(id: 'b1', name: 'Wall', projectIds: ['A']),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Projects implements ProjectRepository {
  final asked = <String>[];
  Object? refusal;

  @override
  Future<Project> project(String id) async {
    asked.add(id);
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return Project(id: id, key: id, name: 'Alpha', leadIds: const ['lead']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Teams implements TeamRepository {
  int calls = 0;

  @override
  Future<List<Team>> teams() async {
    calls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

AuthUser _user(String id) => AuthUser(
  id: id,
  email: '$id@example.org',
  username: id,
  displayName: id,
  roles: const {},
);

void main() {
  late _Boards boards;
  late _Projects projects;
  late _Teams teams;
  AuthUser? me;

  ProjectBoardsCubit cubitFor(String projectId) {
    final cubit = ProjectBoardsCubit(
      boards: boards,
      projects: projects,
      teams: teams,
      projectId: projectId,
      me: () => me,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  setUp(() {
    boards = _Boards();
    projects = _Projects();
    teams = _Teams();
    me = null;
  });

  test('reads the project\'s boards, its name and the teams', () async {
    final cubit = cubitFor('A');
    await cubit.load();

    expect(boards.asked, ['A']);
    expect(projects.asked, ['A']);
    expect(teams.calls, 1);
    final data = cubit.state.data!;
    expect(data.projectName, 'Alpha');
    expect([for (final b in data.boards) b.id], ['b1']);
    expect(data.canManageProject, isFalse);
  });

  test('judges whoever is signed in at the time of the read', () async {
    final cubit = cubitFor('A');
    me = _user('member');
    await cubit.load();
    expect(cubit.state.data!.canManageProject, isFalse);

    me = _user('lead');
    await cubit.load();
    expect(cubit.state.data!.canManageProject, isTrue);
  });

  test('keeps the failure\'s key when a read is refused', () async {
    projects.refusal = ApiFailure('error.accessDenied');
    final cubit = cubitFor('A');
    await cubit.load();

    expect(cubit.state.data, isNull);
    expect(cubit.state.errorKey, 'error.accessDenied');
  });
}
