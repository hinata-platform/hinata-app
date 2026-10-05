import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/git_dev_info.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/git/widgets/development_cubit.dart';

import '../../support/recording_fake.dart';

/// The issue's development panel reads its git activity and runs the pull
/// request actions through this cubit, one repository call each.
void main() {
  late FakeGitRepository git;
  late DevelopmentCubit cubit;

  setUp(() {
    git = FakeGitRepository();
    cubit = DevelopmentCubit(git);
  });
  tearDown(() => cubit.close());

  test('the activity is read for the issue key', () async {
    const info = DevInfo(connected: true);
    git.answer<DevInfo>(#gitDevInfo, info);

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
      git.answer<({DevInfo devInfo, Issue issue})>(#gitMergePr, result);
      git.answer<({DevInfo devInfo, Issue issue})>(#gitReadyPr, result);

      expect(await cubit.mergePr('HIN-1', 7), result);
      expect(await cubit.readyPr('HIN-1', 8), result);
      expect(git.calls.map((c) => c.memberName), [#gitMergePr, #gitReadyPr]);
      expect(git.calls[0].positionalArguments, ['HIN-1', 7]);
      expect(git.calls[1].positionalArguments, ['HIN-1', 8]);
    },
  );

  test('a refused merge comes back as the same failure', () async {
    git.fail(#gitMergePr, failure);

    await expectLater(cubit.mergePr('HIN-1', 7), throwsA(same(failure)));
  });
}
