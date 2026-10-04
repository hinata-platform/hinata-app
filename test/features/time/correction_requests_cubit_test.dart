import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/correction_requests_cubit.dart';

import 'recording_repository.dart';

/// The list of requests reads, names and answers through this cubit: each call
/// reaches the repository as asked and comes back as it answered.
void main() {
  const request = TimeCorrectionRequest(id: 'r1');
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha');

  late _FakeTime time;
  late _FakeProjects projects;
  late CorrectionRequestsCubit cubit;

  setUp(() {
    time = _FakeTime();
    projects = _FakeProjects();
    cubit = CorrectionRequestsCubit(time, projects);
    addTearDown(cubit.close);
  });

  test('reads the page it was given', () async {
    time.answers[#correctionRequests] = Future.value((
      items: [request],
      total: 1,
    ));

    final page = await cubit.correctionRequests(page: 2, size: 25);

    expect(page.items, [request]);
    expect(page.total, 1);
    expect(
      time.calls.single,
      invoked(#correctionRequests, named: {#page: 2, #size: 25}),
    );
  });

  test('names the projects asked about', () async {
    projects.answers[#resolveProjects] = Future.value([alpha]);

    expect(await cubit.resolveProjects(['p1']), [alpha]);
    expect(
      projects.calls.single,
      invoked(
        #resolveProjects,
        positional: [
          ['p1'],
        ],
      ),
    );
  });

  test('answers, and opens the days, with the sentence', () async {
    time.answers[#answerCorrection] = Future.value(request);
    time.answers[#grantCorrection] = Future.value(request);

    expect(await cubit.answer('r1', 'fixed it'), request);
    expect(await cubit.grant('r1', ''), request);

    expect(time.calls, [
      invoked(#answerCorrection, positional: ['r1', 'fixed it']),
      invoked(#grantCorrection, positional: ['r1', '']),
    ]);
  });

  test('passes a refusal through', () async {
    time.failure = refusal;
    projects.failure = refusal;

    await expectLater(
      () => cubit.correctionRequests(page: 0, size: 25),
      throwsRefusal,
    );
    await expectLater(() => cubit.resolveProjects(['p1']), throwsRefusal);
    await expectLater(() => cubit.answer('r1', 'no'), throwsRefusal);
    await expectLater(() => cubit.grant('r1', ''), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeProjects with RecordingRepository implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
