import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/deletion_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/features/deletion/deletion_cubit.dart';

/// The cascading delete: what it would touch, and the delete itself as a
/// stream, for boards, projects and teams.
void main() {
  late List<String> calls;
  late DeletionCubit cubit;
  final cancel = CancelToken();

  setUp(() {
    calls = [];
    cubit = DeletionCubit(
      boards: _FakeBoards(calls, cancel),
      projects: _FakeProjects(calls, cancel),
      teams: _FakeTeams(calls, cancel),
    );
  });

  tearDown(() => cubit.close());

  test('a board', () async {
    expect((await cubit.boardImpact('b1')).sprints, 2);
    await cubit.deleteBoard('b1', cancelToken: cancel);

    expect(calls, ['boardImpact b1', 'boardDelete b1']);
  });

  test('a project carries the choice for its issues', () async {
    expect((await cubit.projectImpact('p1')).issues, 4);
    await cubit.deleteProject(
      'p1',
      strategy: IssueStrategy.migrate,
      migrateToProjectId: 'p2',
      cancelToken: cancel,
    );

    expect(calls, ['projectImpact p1', 'projectDelete p1 migrate p2']);
  });

  test('a team', () async {
    expect((await cubit.teamImpact('t1')).members, 3);
    await cubit.deleteTeam('t1', cancelToken: cancel);

    expect(calls, ['teamImpact t1', 'teamDelete t1']);
  });

  test('a failed impact read passes through', () async {
    await expectLater(cubit.boardImpact('gone'), throwsA(isA<StateError>()));
  });
}

Stream<List<int>> _frames() => Stream.value(const [100, 97, 116, 97]);

class _FakeBoards implements BoardRepository {
  _FakeBoards(this.calls, this.cancel);

  final List<String> calls;
  final CancelToken cancel;

  @override
  Future<BoardDeletionImpact> boardDeletionImpact(String boardId) async {
    if (boardId == 'gone') throw StateError('not found');
    calls.add('boardImpact $boardId');
    return BoardDeletionImpact.fromJson(const {'sprints': 2});
  }

  @override
  Future<Stream<List<int>>> boardDeleteStream(
    String boardId, {
    CancelToken? cancelToken,
  }) async {
    expect(cancelToken, same(cancel));
    calls.add('boardDelete $boardId');
    return _frames();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjects implements ProjectRepository {
  _FakeProjects(this.calls, this.cancel);

  final List<String> calls;
  final CancelToken cancel;

  @override
  Future<ProjectDeletionImpact> projectDeletionImpact(String projectId) async {
    calls.add('projectImpact $projectId');
    return ProjectDeletionImpact.fromJson(const {'issues': 4});
  }

  @override
  Future<Stream<List<int>>> projectDeleteStream(
    String projectId, {
    IssueStrategy? strategy,
    String? migrateToProjectId,
    CancelToken? cancelToken,
  }) async {
    expect(cancelToken, same(cancel));
    calls.add('projectDelete $projectId ${strategy?.name} $migrateToProjectId');
    return _frames();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeTeams implements TeamRepository {
  _FakeTeams(this.calls, this.cancel);

  final List<String> calls;
  final CancelToken cancel;

  @override
  Future<TeamDeletionImpact> teamDeletionImpact(String teamId) async {
    calls.add('teamImpact $teamId');
    return TeamDeletionImpact.fromJson(const {'members': 3});
  }

  @override
  Future<Stream<List<int>>> teamDeleteStream(
    String teamId, {
    CancelToken? cancelToken,
  }) async {
    expect(cancelToken, same(cancel));
    calls.add('teamDelete $teamId');
    return _frames();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
