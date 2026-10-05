import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/issue_move.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_move_cubit.dart';

import '../../support/recording_fake.dart';

void main() {
  late FakeIssueRepository issues;
  late IssueMoveCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    cubit = IssueMoveCubit(issues);
  });

  tearDown(() => cubit.close());

  test('analyses the move', () async {
    const preflight = MovePreflight(
      targetProject: Project(id: 'p2', key: 'MOB', name: 'Mobile'),
      targetStates: ['TODO'],
      stateMappings: [],
      issues: [],
      warnings: [],
    );
    await expectForwarded(
      issues,
      #movePreflight,
      () => Future.value(preflight),
      () => cubit.analyse(const ['i1'], 'p2', includeEpicChildren: true),
      positional: [
        ['i1'],
        'p2',
      ],
      named: {#includeEpicChildren: true},
    );
  });

  test('moves with the confirmed status mapping', () async {
    await expectForwarded(
      issues,
      #moveIssues,
      () => Future.value(<Issue>[]),
      () => cubit.move(
        const ['i1'],
        'p2',
        stateMap: const {'OPEN': 'TODO'},
        keepSprint: false,
      ),
      positional: [
        ['i1'],
        'p2',
      ],
      named: {
        #stateMap: {'OPEN': 'TODO'},
        #includeEpicChildren: false,
        #keepSprint: false,
      },
    );
  });

  test('passes a refused move on unchanged', () async {
    await expectFailurePassedOn(
      issues,
      #moveIssues,
      () => cubit.move(const ['i1'], 'p2', stateMap: const {}),
    );
  });
}
