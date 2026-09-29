import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/org_settings_repository.dart';
import 'package:hinata/core/models/work_models.dart' show RelativeDateBasis;

/// The wire contract of the organisation role (HIN-129): the settings an
/// organisation admin keeps, and the switch an admin grants the role with.
void main() {
  late _RecordingApiClient api;

  setUp(() => api = _RecordingApiClient());

  group('OrgSettingsRepository', () {
    test('reads the block, the stored basis and the one in force', () async {
      api.response = {
        'timeTracking': {
          'advancedEnabled': true,
          'effective': {'advancedEnabled': true},
        },
        'defaultDeadlineBasis': null,
        'effectiveDeadlineBasis': 'WORKING',
      };

      final settings = await OrgSettingsRepository(api).settings();

      expect(api.calls.single.$1, 'get');
      expect(api.calls.single.$2, '/api/v1/org/settings');
      expect(settings.timeTracking['advancedEnabled'], isTrue);
      expect(settings.defaultDeadlineBasis, isNull);
      expect(settings.effectiveDeadlineBasis, RelativeDateBasis.working);
    });

    test('an answer without a block still gives the page a draft', () async {
      api.response = <String, dynamic>{};
      final settings = await OrgSettingsRepository(api).settings();

      settings.timeTracking['advancedEnabled'] = true;
      expect(settings.timeTracking['advancedEnabled'], isTrue);
      expect(settings.effectiveDeadlineBasis, RelativeDateBasis.calendar);
    });

    test('writes the block without its read-only effective values', () async {
      api.response = <String, dynamic>{};
      await OrgSettingsRepository(api).update(
        timeTracking: {
          'approvalsEnabled': true,
          'effective': {'approvalsEnabled': false},
        },
      );

      final (method, path, body) = api.calls.single;
      expect(method, 'put');
      expect(path, '/api/v1/org/settings');
      expect(body, {
        'timeTracking': {'approvalsEnabled': true},
      });
    });

    test('a basis is sent only when given', () async {
      api.response = <String, dynamic>{};
      await OrgSettingsRepository(
        api,
      ).update(defaultDeadlineBasis: RelativeDateBasis.working);
      expect(api.calls.single.$3, {'defaultDeadlineBasis': 'WORKING'});
    });

    test('the organisation log reads its own feed', () async {
      api.response = {
        'items': <dynamic>[],
        'total': 0,
        'page': 2,
        'perPage': 30,
      };
      final page = await OrgSettingsRepository(
        api,
      ).auditLog(query: ' sick ', page: 2);

      final (method, path, query) = api.calls.single;
      expect(method, 'get');
      expect(path, '/api/v1/org/audit');
      expect(query, {'query': 'sick', 'page': '2', 'perPage': '30'});
      expect(page.page, 2);
    });

    test('clearing hands the basis back to the platform', () async {
      api.response = <String, dynamic>{};
      await OrgSettingsRepository(api).update(clearDefaultDeadlineBasis: true);
      expect(api.calls.single.$3, {'clearDefaultDeadlineBasis': true});
    });
  });

  group('AdminRepository and the organisation role', () {
    test('grants it on the org-role route', () async {
      await AdminRepository(api).adminSetOrgRole(['u1', 'u2'], true);

      final (method, path, body) = api.calls.single;
      expect(method, 'post');
      expect(path, '/api/v1/admin/users/org-role');
      expect(body, {
        'ids': ['u1', 'u2'],
        'orgAdmin': true,
      });
    });

    test('a user row carries it, and misses it as false', () {
      AdminUser row(Map<String, dynamic> extra) =>
          AdminUser.fromJson({'id': 'u1', 'role': 'USER', ...extra});

      expect(row({'orgAdmin': true}).orgAdmin, isTrue);
      expect(row(const {}).orgAdmin, isFalse);
      // Independent of the platform role, both ways.
      expect(row({'orgAdmin': true}).role, AdminRole.user);
    });
  });
}

class _RecordingApiClient implements ApiClient {
  final List<(String, String, Object?)> calls = [];
  Object? response;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add(('get', path, query));
    return response;
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('put', path, body));
    return response;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add(('post', path, body));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
