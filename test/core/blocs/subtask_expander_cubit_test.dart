import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/subtask_expander_cubit.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';

/// The sub-task expander reads an issue's children through this cubit: it asks
/// for the right issue's hierarchy and hands back only the children.
void main() {
  const child = Issue(
    id: 'i2',
    projectId: 'p1',
    readableId: 'HIN-2',
    title: 'Child',
    state: 'TODO',
  );

  test("answers the issue's direct children", () async {
    final issues = _FakeIssueRepository(
      const IssueHierarchy(children: [child]),
    );
    final cubit = SubtaskExpanderCubit(issues);
    addTearDown(cubit.close);

    expect(await cubit.children('i1'), [child]);
    expect(issues.asked, ['i1']);
  });

  test('passes a refusal through', () async {
    final cubit = SubtaskExpanderCubit(
      _FakeIssueRepository(null, failure: ApiFailure('errors.notFound')),
    );
    addTearDown(cubit.close);

    await expectLater(
      cubit.children('i1'),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          'errors.notFound',
        ),
      ),
    );
  });
}

class _FakeIssueRepository implements IssueRepository {
  _FakeIssueRepository(this.hierarchy, {this.failure});

  final IssueHierarchy? hierarchy;
  final ApiFailure? failure;
  final List<String> asked = [];

  @override
  Future<IssueHierarchy> issueHierarchy(String id) async {
    asked.add(id);
    if (failure != null) throw failure!;
    return hierarchy!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
