import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart' show RelativeDateBasis;
import 'package:hinata/features/organization/organization_cubit.dart';

import 'organization_test_support.dart';

/// What a save of the Organisation page sends (HIN-129).
///
/// The time-tracking draft goes every time. The deadline basis goes only when
/// it was moved, and only while project templates are on: the server refuses a
/// basis while they are off, and a card nobody touched must not overwrite what
/// another organisation admin saved in the meantime.
void main() {
  Future<(OrganizationCubit, FakeOrgSettingsRepository)> loaded({
    String? basis,
  }) async {
    final repository = FakeOrgSettingsRepository(defaultDeadlineBasis: basis);
    final cubit = OrganizationCubit(repository);
    await cubit.load();
    return (cubit, repository);
  }

  test('loads the settings and the stored basis', () async {
    final (cubit, _) = await loaded(basis: 'WORKING');

    expect(cubit.state.status, OrganizationStatus.ready);
    expect(cubit.state.basis, RelativeDateBasis.working);
    expect(cubit.state.settings, isNotNull);
  });

  test('an untouched page sends the draft and no basis', () async {
    final (cubit, repository) = await loaded();
    cubit.state.settings!.timeTracking['approvalsEnabled'] = true;

    expect(await cubit.save(templates: true), isNull);

    final update = repository.updates.single;
    expect(update.timeTracking?['approvalsEnabled'], isTrue);
    expect(update.defaultDeadlineBasis, isNull);
    expect(update.clearDefaultDeadlineBasis, isFalse);
  });

  test('a chosen basis is sent as the organisation\'s own', () async {
    final (cubit, repository) = await loaded();
    cubit.setBasis(RelativeDateBasis.working);

    await cubit.save(templates: true);

    final update = repository.updates.single;
    expect(update.defaultDeadlineBasis, RelativeDateBasis.working);
    expect(update.clearDefaultDeadlineBasis, isFalse);
    // What the server kept becomes the page's state.
    expect(cubit.state.basis, RelativeDateBasis.working);
    expect(
      cubit.state.settings!.defaultDeadlineBasis,
      RelativeDateBasis.working,
    );
  });

  test('following the platform again clears the stored basis', () async {
    final (cubit, repository) = await loaded(basis: 'WORKING');
    cubit.setBasis(null);

    await cubit.save(templates: true);

    final update = repository.updates.single;
    expect(update.defaultDeadlineBasis, isNull);
    expect(update.clearDefaultDeadlineBasis, isTrue);
    expect(cubit.state.basis, isNull);
  });

  test('no basis goes while project templates are off', () async {
    final (cubit, repository) = await loaded();
    cubit.setBasis(RelativeDateBasis.working);

    await cubit.save(templates: false);

    final update = repository.updates.single;
    expect(update.defaultDeadlineBasis, isNull);
    expect(update.clearDefaultDeadlineBasis, isFalse);
    expect(update.timeTracking, isNotNull);
  });

  test('a refused save hands back the error key', () async {
    final (cubit, repository) = await loaded();
    repository.failWith = 'error.org.adminOnly';

    expect(await cubit.save(templates: true), 'error.org.adminOnly');
    expect(cubit.state.saving, isFalse);
  });

  test('a refused load ends in failure with the key', () async {
    final cubit = OrganizationCubit(
      FakeOrgSettingsRepository(failWith: 'error.org.adminOnly'),
    );
    await cubit.load();

    expect(cubit.state.status, OrganizationStatus.failure);
    expect(cubit.state.errorKey, 'error.org.adminOnly');
  });
}
