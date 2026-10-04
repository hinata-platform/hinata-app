import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/features/admin/sections/admin_connect_cubit.dart';

/// Admin → Connect: every call reaches the server and answers with the status
/// it holds afterwards.
void main() {
  late _FakeAdmin admin;
  late AdminConnectCubit cubit;

  setUp(() {
    admin = _FakeAdmin();
    cubit = AdminConnectCubit(admin);
  });

  tearDown(() => cubit.close());

  test('each call answers with the server status', () async {
    expect(await cubit.status(), {'call': 'status'});
    expect(await cubit.startHandshake(), {'call': 'handshakeStart'});
    expect(await cubit.cancelHandshake(), {'call': 'handshakeCancel'});
    expect(await cubit.enroll('tok-1'), {'call': 'enroll tok-1'});
    expect(await cubit.disconnect(), {'call': 'disconnect'});
  });

  test('a refusal passes through', () async {
    admin.fail = true;

    await expectLater(cubit.enroll('bad'), throwsA(isA<ApiFailure>()));
  });
}

class _FakeAdmin implements AdminRepository {
  bool fail = false;

  Future<Map<String, dynamic>> _answer(String call) async {
    if (fail) throw ApiFailure('error.connect.token', statusCode: 400);
    return {'call': call};
  }

  @override
  Future<Map<String, dynamic>> connectStatus() => _answer('status');

  @override
  Future<Map<String, dynamic>> connectHandshakeStart() =>
      _answer('handshakeStart');

  @override
  Future<Map<String, dynamic>> connectHandshakeCancel() =>
      _answer('handshakeCancel');

  @override
  Future<Map<String, dynamic>> connectEnroll(String token) =>
      _answer('enroll $token');

  @override
  Future<Map<String, dynamic>> connectDisconnect() => _answer('disconnect');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
