import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/project_template_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/projects/project_copy_cubit.dart';

import 'repository_recorders.dart';

/// The copy sheet's cubit hands each request to the repository as the sheet
/// filled it in, and hands back the answer or the refusal unchanged.
void main() {
  late RecordingProjects projects;
  late ProjectCopyCubit cubit;

  const copy = Project(id: 'p2', key: 'BFQ2', name: 'Copy');
  const result = ProjectCopyResult(project: copy, issuesCopied: 3);

  setUp(() {
    projects = RecordingProjects();
    cubit = ProjectCopyCubit(projects);
  });
  tearDown(() => cubit.close());

  test('asks the scope of the source', () async {
    const scope = ProjectCopyScope(issues: 4, suggestedKey: 'BFQ2');
    projects.answers[#scopeOfCopy] = () async => scope;

    expect(await cubit.scopeOfCopy('p1'), scope);
    expect(projects.callTo(#scopeOfCopy).positionalArguments, ['p1']);
  });

  test('copies with every switch as set', () async {
    projects.answers[#copyProject] = () async => result;
    final date = DateTime(2026, 11, 7);

    final answer = await cubit.copy(
      'p1',
      name: 'Copy',
      key: 'BFQ2',
      eventDate: date,
      includeMembers: false,
      includeAttachments: true,
      includeTimeSettings: false,
      includeBoard: true,
      asTemplate: true,
      deadlineBasis: RelativeDateBasis.working,
    );

    expect(answer, result);
    final call = projects.callTo(#copyProject);
    expect(call.positionalArguments, ['p1']);
    expect(call.namedArguments, {
      #name: 'Copy',
      #key: 'BFQ2',
      #eventDate: date,
      #includeMembers: false,
      #includeAttachments: true,
      #includeTimeSettings: false,
      #includeBoard: true,
      #asTemplate: true,
      #deadlineBasis: RelativeDateBasis.working,
    });
  });

  test('instantiates a template', () async {
    projects.answers[#instantiateTemplate] = () async => result;

    final answer = await cubit.instantiate('t1', name: 'Fest', key: '');

    expect(answer, result);
    final call = projects.callTo(#instantiateTemplate);
    expect(call.positionalArguments, ['t1']);
    expect(call.namedArguments[#name], 'Fest');
    expect(call.namedArguments[#key], '');
    expect(call.namedArguments[#eventDate], isNull);
    expect(call.namedArguments[#deadlineBasis], isNull);
  });

  test('passes a refusal on', () async {
    projects.answers[#copyProject] = () async =>
        throw ApiFailure('projects.copy.tooManyIssues');

    await expectLater(
      cubit.copy(
        'p1',
        name: 'Copy',
        key: '',
        includeMembers: true,
        includeAttachments: false,
        includeTimeSettings: true,
        includeBoard: false,
        asTemplate: false,
      ),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          'projects.copy.tooManyIssues',
        ),
      ),
    );
  });
}
