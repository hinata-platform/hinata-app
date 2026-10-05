import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/time/correction_requests_cubit.dart';

import '../../support/recording_fake.dart';

/// The list of requests reads, names and answers through this cubit: each call
/// reaches the repository as asked and comes back as it answered.
void main() {
  const request = TimeCorrectionRequest(id: 'r1');
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha');

  late FakeTimeRepository time;
  late FakeProjectRepository projects;
  late CorrectionRequestsCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    projects = FakeProjectRepository();
    cubit = CorrectionRequestsCubit(time, projects);
    addTearDown(cubit.close);
  });

  test('reads the page it was given', () async {
    time.answer(#correctionRequests, (items: [request], total: 1));

    final page = await cubit.correctionRequests(page: 2, size: 25);

    expect(page.items, [request]);
    expect(page.total, 1);
    expect(
      time.calls.single,
      invoked(#correctionRequests, named: {#page: 2, #size: 25}),
    );
  });

  test('names the projects asked about', () async {
    projects.answer(#resolveProjects, [alpha]);

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
    time.answer(#answerCorrection, request);
    time.answer(#grantCorrection, request);

    expect(await cubit.answer('r1', 'fixed it'), request);
    expect(await cubit.grant('r1', ''), request);

    expect(time.calls, [
      invoked(#answerCorrection, positional: ['r1', 'fixed it']),
      invoked(#grantCorrection, positional: ['r1', '']),
    ]);
  });

  test('passes a failure through', () async {
    time.fail(#correctionRequests, failure);
    time.fail(#answerCorrection, failure);
    time.fail(#grantCorrection, failure);
    projects.fail(#resolveProjects, failure);

    await expectLater(
      () => cubit.correctionRequests(page: 0, size: 25),
      throwsFailure,
    );
    await expectLater(() => cubit.resolveProjects(['p1']), throwsFailure);
    await expectLater(() => cubit.answer('r1', 'no'), throwsFailure);
    await expectLater(() => cubit.grant('r1', ''), throwsFailure);
  });
}
