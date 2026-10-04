import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/features/setup/setup_cubit.dart';

/// The first-run wizard: the organisation and its first admin, in one request.
void main() {
  Future<void> complete(SetupCubit cubit) => cubit.complete(
    organizationName: 'AStA',
    adminEmail: 'admin@example.org',
    adminUsername: 'admin',
    adminDisplayName: 'Admin',
    adminPassword: 'correct horse',
  );

  test('sends every field as typed', () async {
    final meta = _FakeMeta();
    final cubit = SetupCubit(meta);

    await complete(cubit);

    expect(
      meta.calls.single,
      'AStA admin@example.org admin Admin correct horse',
    );
    await cubit.close();
  });

  test('a refusal passes through', () async {
    final cubit = SetupCubit(_FakeMeta(fail: true));

    await expectLater(complete(cubit), throwsA(isA<ApiFailure>()));
    await cubit.close();
  });
}

class _FakeMeta implements MetaRepository {
  _FakeMeta({this.fail = false});

  final bool fail;
  final List<String> calls = [];

  @override
  Future<void> completeSetup({
    required String organizationName,
    required String adminEmail,
    required String adminUsername,
    required String adminDisplayName,
    required String adminPassword,
  }) async {
    if (fail) throw ApiFailure('error.setup.done', statusCode: 409);
    calls.add(
      '$organizationName $adminEmail $adminUsername $adminDisplayName '
      '$adminPassword',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
