import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/features/admin/admin_settings_cubit.dart';

/// The admin screen's settings: read, saved without the time-tracking block
/// the Organisation page owns, and the logo the General section keeps.
void main() {
  late _FakeAdmin admin;
  late _FakeMeta meta;
  late AdminSettingsCubit cubit;

  setUp(() {
    admin = _FakeAdmin();
    meta = _FakeMeta();
    cubit = AdminSettingsCubit(admin: admin, meta: meta);
  });

  tearDown(() => cubit.close());

  test('a load holds the settings the server answered', () async {
    await cubit.load();

    expect(cubit.state.status, AdminSettingsStatus.ready);
    expect(cubit.state.settings, same(admin.stored));
  });

  test('a refused load keeps the key for the retry', () async {
    admin.failWith = 'error.forbidden';

    await cubit.load();

    expect(cubit.state.status, AdminSettingsStatus.failure);
    expect(cubit.state.errorKey, 'error.forbidden');
  });

  test('a malformed answer fails instead of loading forever', () async {
    admin.malformed = true;

    await cubit.load();

    expect(cubit.state.status, AdminSettingsStatus.failure);
    expect(cubit.state.errorKey, 'errors.unexpected');
  });

  test('a save leaves the time-tracking block out', () async {
    await cubit.load();
    cubit.state.settings!['general'] = {'name': 'AStA'};

    await cubit.save();

    final sent = admin.saved.single;
    expect(sent.containsKey('timeTracking'), isFalse);
    expect(sent['general'], {'name': 'AStA'});
    // The draft the sections keep writing into is still whole.
    expect(cubit.state.settings!.containsKey('timeTracking'), isTrue);
    expect(cubit.state.saving, isFalse);
  });

  test('a refused save passes the failure on and stops saving', () async {
    await cubit.load();
    admin.failWith = 'error.validation';

    await expectLater(cubit.save(), throwsA(isA<ApiFailure>()));
    expect(cubit.state.saving, isFalse);
  });

  test('nothing is saved before anything was read', () async {
    await cubit.save();

    expect(admin.saved, isEmpty);
  });

  test('the logo calls reach their repositories', () async {
    final file = MultipartFile.fromBytes(const [1, 2, 3], filename: 'a.png');

    expect(await cubit.uploadLogo(file), '/api/v1/meta/logo?v=1');
    expect(admin.uploaded.single, same(file));

    await cubit.deleteLogo();
    expect(admin.logoDeleted, isTrue);

    final logo = await cubit.logo(cacheBust: 4);
    expect(meta.cacheBusts.single, 4);
    expect(logo?.isSvg, isTrue);
  });
}

class _FakeAdmin implements AdminRepository {
  String? failWith;
  bool malformed = false;
  final Map<String, dynamic> stored = {
    'general': <String, dynamic>{},
    'timeTracking': <String, dynamic>{'approvalsEnabled': true},
  };
  final List<Map<String, dynamic>> saved = [];
  final List<MultipartFile> uploaded = [];
  bool logoDeleted = false;

  @override
  Future<Map<String, dynamic>> adminSettings() async {
    if (failWith != null) throw ApiFailure(failWith!, statusCode: 403);
    if (malformed) throw const FormatException('not json');
    return stored;
  }

  @override
  Future<Map<String, dynamic>> updateAdminSettings(
    Map<String, dynamic> settings,
  ) async {
    saved.add(settings);
    if (failWith != null) throw ApiFailure(failWith!, statusCode: 400);
    return {...stored};
  }

  @override
  Future<String> uploadOrganizationLogo(MultipartFile file) async {
    uploaded.add(file);
    return '/api/v1/meta/logo?v=1';
  }

  @override
  Future<void> deleteOrganizationLogo() async {
    logoDeleted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeMeta implements MetaRepository {
  final List<int?> cacheBusts = [];

  @override
  Future<({List<int> bytes, bool isSvg})?> organizationLogo({
    int? cacheBust,
  }) async {
    cacheBusts.add(cacheBust);
    return (bytes: const [60, 115, 118, 103], isSvg: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
