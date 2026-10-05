import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/features/projects/project_lead_cubit.dart';

import '../../support/recording_fake.dart';

/// The project form's own lookup: the person creating the project, by id.
void main() {
  late FakeUserRepository users;
  late ProjectLeadCubit cubit;

  setUp(() {
    users = FakeUserRepository();
    cubit = ProjectLeadCubit(users);
  });
  tearDown(() => cubit.close());

  test('looks the ids up and answers what the directory found', () async {
    const me = DirectoryUser(id: 'u1', username: 'uma', displayName: 'Uma');
    users.answer(#usersByIds, const [me]);

    expect(await cubit.usersByIds(['u1']), [me]);
    expect(users.callTo(#usersByIds).positionalArguments, [
      ['u1'],
    ]);
  });

  test('passes a failure on', () async {
    users.fail(#usersByIds, ApiFailure('errors.x'));

    await expectLater(cubit.usersByIds(['u1']), throwsA(isA<ApiFailure>()));
  });
}
