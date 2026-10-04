import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/organization/time_tracking/absence_managers_cubit.dart';

/// The names behind the absence keepers' ids.
void main() {
  test('asks the directory for exactly the ids given', () async {
    final users = _FakeUsers();
    final cubit = AbsenceManagersCubit(users);

    final people = await cubit.people(['u1', 'u2']);

    expect(users.asked.single, ['u1', 'u2']);
    expect(people.map((person) => person.id), ['u1', 'u2']);
    await cubit.close();
  });

  test('a failed read passes through', () async {
    final cubit = AbsenceManagersCubit(_FakeUsers(fail: true));

    await expectLater(cubit.people(['u1']), throwsA(isA<StateError>()));
    await cubit.close();
  });
}

class _FakeUsers implements UserRepository {
  _FakeUsers({this.fail = false});

  final bool fail;
  final List<List<String>> asked = [];

  @override
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async {
    asked.add(ids);
    if (fail) throw StateError('offline');
    return [
      for (final id in ids)
        DirectoryUser(id: id, username: id, displayName: 'Person $id'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
