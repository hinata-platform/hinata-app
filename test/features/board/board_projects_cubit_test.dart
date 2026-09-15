import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/features/board/board_projects_cubit.dart';

/// Resolves the projects it is asked for, all but one the viewer may not read.
class _Projects implements ProjectRepository {
  final asked = <List<String>>[];
  Object? failure;

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async {
    asked.add(ids);
    final failure = this.failure;
    if (failure != null) throw failure;
    return [
      for (final id in ids)
        if (id != 'hidden')
          Project(id: id, key: id.toUpperCase(), name: 'Project $id'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Projects server;

  setUp(() => server = _Projects());

  BoardProjectsCubit projectsOver() {
    final cubit = BoardProjectsCubit(projects: server);
    addTearDown(cubit.close);
    return cubit;
  }

  test("reads the projects a board names once, in the board's order", () async {
    final projects = projectsOver();

    await Future.wait([
      projects.resolve(const ['p2', 'hidden', 'p1']),
      projects.resolve(const ['p2', 'hidden', 'p1']),
    ]);

    expect(server.asked, hasLength(1));
    expect(projects.state.inBoardOrder.map((project) => project.id), [
      'p2',
      'p1',
    ]);
    expect(projects.state.names, {'p2': 'Project p2', 'p1': 'Project p1'});
  });

  test('reads again once the board names other projects', () async {
    final projects = projectsOver();
    await projects.resolve(const ['p1']);

    await projects.resolve(const ['p1', 'p2']);

    expect(server.asked, hasLength(2));
    expect(projects.state.byId.keys, containsAll(['p1', 'p2']));
  });

  test('projects that did not come are asked for again', () async {
    final projects = projectsOver();
    server.failure = ApiFailure('errors.network');
    await projects.resolve(const ['p1']);
    expect(projects.state, BoardProjectsState.none);

    server.failure = null;
    await projects.resolve(const ['p1']);

    expect(server.asked, hasLength(2));
    expect(projects.state.names, {'p1': 'Project p1'});
  });
}
