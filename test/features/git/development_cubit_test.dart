import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/git_dev_info.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/git_repository.dart';
import 'package:hinata/features/git/widgets/development_cubit.dart';

import '../recording_fake.dart';

class _FakeGit with RecordingFake implements GitRepository {}

/// The issue's development panel reads its git activity and runs the pull
/// request actions through this cubit, one repository call each.
void main() {
  late _FakeGit git;
  late DevelopmentCubit cubit;

  setUp(() {
    git = _FakeGit();
    cubit = DevelopmentCubit(git);
  });
  tearDown(() => cubit.close());

  test('the activity is read for the issue key', () async {
    const info = DevInfo(connected: true);
    git.answers[#gitDevInfo] = () => Future<DevInfo>.value(info);

    expect(await cubit.devInfo('HIN-1'), same(info));
    expect(git.only.positionalArguments, ['HIN-1']);
  });

  test(
    'merge and ready forward the issue key and the request number',
    () async {
      const result = (
        devInfo: DevInfo(connected: true),
        issue: Issue(
          id: 'i1',
          projectId: 'p1',
          readableId: 'HIN-1',
          title: 'Title',
          state: 'Open',
        ),
      );
      git.answers[#gitMergePr] = () =>
          Future<({DevInfo devInfo, Issue issue})>.value(result);
      git.answers[#gitReadyPr] = () =>
          Future<({DevInfo devInfo, Issue issue})>.value(result);

      expect(await cubit.mergePr('HIN-1', 7), result);
      expect(await cubit.readyPr('HIN-1', 8), result);
      expect(git.calls.map((c) => c.memberName), [#gitMergePr, #gitReadyPr]);
      expect(git.calls[0].positionalArguments, ['HIN-1', 7]);
      expect(git.calls[1].positionalArguments, ['HIN-1', 8]);
    },
  );

  test('a refused merge comes back as the same failure', () async {
    git.answers[#gitMergePr] = () =>
        Future<({DevInfo devInfo, Issue issue})>.error(failure);

    await expectLater(cubit.mergePr('HIN-1', 7), throwsA(same(failure)));
  });
}
