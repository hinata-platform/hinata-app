import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/features/projects/settings/project_time_settings_cubit.dart';

import '../../support/recording_fake.dart';

/// The time section's cubit reads and writes the settings of its own project.
void main() {
  late FakeTimeRepository time;
  late ProjectTimeSettingsCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = ProjectTimeSettingsCubit(time, projectId: 'p1');
  });
  tearDown(() => cubit.close());

  test('reads the project\'s settings', () async {
    const stored = ProjectTimeSettings(budgetMinutes: 600);
    time.answer(#projectSettings, stored);

    expect(await cubit.load(), stored);
    expect(time.callTo(#projectSettings).positionalArguments, ['p1']);
  });

  test('writes the draft and answers what the server kept', () async {
    const draft = ProjectTimeSettings(approvalRequired: true);
    const kept = ProjectTimeSettings(
      approvalRequired: true,
      approvalPeriod: 'WEEKLY',
    );
    time.answer(#saveProjectSettings, kept);

    expect(await cubit.save(draft), kept);
    expect(time.callTo(#saveProjectSettings).positionalArguments, [
      'p1',
      draft,
    ]);
  });

  test('passes a failure on', () async {
    time.fail(#saveProjectSettings, ApiFailure('errors.forbidden'));

    await expectLater(
      cubit.save(const ProjectTimeSettings()),
      throwsA(isA<ApiFailure>()),
    );
  });
}
