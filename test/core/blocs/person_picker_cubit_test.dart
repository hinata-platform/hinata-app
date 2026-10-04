import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/person_picker_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/user_repository.dart';

/// The people picker's search goes through this cubit: the query and the page
/// must reach the directory as asked, and its answer or refusal come back.
void main() {
  const ada = DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada');

  test('asks the directory for the page it was given', () async {
    final users = _FakeUserRepository();
    final cubit = PersonPickerCubit(users);
    addTearDown(cubit.close);

    final result = await cubit.search('ad', page: 2, size: 25);

    expect(users.calls, [(query: 'ad', page: 2, size: 25)]);
    expect(result.items, [ada]);
    expect(result.total, 51);
  });

  test('passes a refusal through', () async {
    final cubit = PersonPickerCubit(
      _FakeUserRepository(failure: ApiFailure('errors.forbidden')),
    );
    addTearDown(cubit.close);

    await expectLater(
      cubit.search('', page: 0, size: 25),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          'errors.forbidden',
        ),
      ),
    );
  });
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository({this.failure});

  final ApiFailure? failure;
  final List<({String query, int page, int size})> calls = [];

  @override
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) async {
    calls.add((query: query, page: page, size: size));
    if (failure != null) throw failure!;
    return (
      items: const [
        DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada'),
      ],
      total: 51,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
