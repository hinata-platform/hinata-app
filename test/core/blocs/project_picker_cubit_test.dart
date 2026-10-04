import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/project_picker_cubit.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';

/// The project picker's search and label lookup go through this cubit: each
/// must reach the repository as asked and hand back its answer or refusal.
void main() {
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha', color: '#AEC6F4');

  test('searches the page it was given', () async {
    final projects = _FakeProjectRepository();
    final cubit = ProjectPickerCubit(projects);
    addTearDown(cubit.close);

    final result = await cubit.search(query: 'al', page: 1, size: 25);

    expect(projects.searches, [(query: 'al', page: 1, size: 25)]);
    expect(result.projects, [alpha]);
    expect(result.total, 26);
  });

  test('a search without a query lists them all', () async {
    final projects = _FakeProjectRepository();
    final cubit = ProjectPickerCubit(projects);
    addTearDown(cubit.close);

    await cubit.search(page: 0, size: 25);

    expect(projects.searches, [(query: null, page: 0, size: 25)]);
  });

  test('resolves the ids it was given', () async {
    final projects = _FakeProjectRepository();
    final cubit = ProjectPickerCubit(projects);
    addTearDown(cubit.close);

    expect(await cubit.resolve(['p1', 'p2']), [alpha]);
    expect(projects.resolved, [
      ['p1', 'p2'],
    ]);
  });

  test('passes a refusal through', () async {
    final cubit = ProjectPickerCubit(
      _FakeProjectRepository(failure: ApiFailure('errors.forbidden')),
    );
    addTearDown(cubit.close);
    final refused = throwsA(
      isA<ApiFailure>().having((f) => f.message, 'message', 'errors.forbidden'),
    );

    await expectLater(cubit.search(page: 0, size: 25), refused);
    await expectLater(cubit.resolve(['p1']), refused);
  });
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository({this.failure});

  static const _alpha = Project(
    id: 'p1',
    key: 'ALP',
    name: 'Alpha',
    color: '#AEC6F4',
  );

  final ApiFailure? failure;
  final List<({String? query, int page, int size})> searches = [];
  final List<List<String>> resolved = [];

  @override
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
  }) async {
    searches.add((query: query, page: page, size: size));
    if (failure != null) throw failure!;
    return (projects: const [_alpha], total: 26);
  }

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async {
    resolved.add(ids);
    if (failure != null) throw failure!;
    return const [_alpha];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
