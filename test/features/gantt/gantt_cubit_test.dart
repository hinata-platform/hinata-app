import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/features/gantt/gantt_cubit.dart';

class _Projects implements ProjectRepository {
  final asked = <String>[];
  Object? refusal;

  @override
  Future<List<Project>> projects({
    bool archived = false,
    bool? template,
  }) async {
    asked.add('projects');
    return const [Project(id: 'A', key: 'A', name: 'Alpha')];
  }

  @override
  Future<GanttView> gantt(String projectId) async {
    asked.add('gantt $projectId');
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return const GanttView();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Projects projects;
  late GanttCubit gantt;

  setUp(() {
    projects = _Projects();
    gantt = GanttCubit(projects);
  });

  tearDown(() => gantt.close());

  test('reads the projects and the chosen project\'s timeline', () async {
    expect([for (final p in await gantt.projects()) p.id], ['A']);
    expect(await gantt.gantt('A'), const GanttView());
    expect(projects.asked, ['projects', 'gantt A']);
  });

  test('passes a refusal on as it came', () async {
    final refusal = ApiFailure('error.accessDenied');
    projects.refusal = refusal;

    await expectLater(gantt.gantt('A'), throwsA(refusal));
  });
}
