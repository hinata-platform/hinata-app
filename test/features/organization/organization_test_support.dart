import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/org_settings_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/models/work_models.dart' show RelativeDateBasis;

/// What one `PUT /api/v1/org/settings` carried.
typedef OrgUpdate = ({
  Map<String, dynamic>? timeTracking,
  RelativeDateBasis? defaultDeadlineBasis,
  bool clearDefaultDeadlineBasis,
});

/// The organisation settings as a test states them, with every write recorded.
class FakeOrgSettingsRepository implements OrgSettingsRepository {
  FakeOrgSettingsRepository({
    this.defaultDeadlineBasis,
    this.effectiveDeadlineBasis = 'CALENDAR',
    this.failWith,
  });

  String? defaultDeadlineBasis;
  String effectiveDeadlineBasis;

  /// An error key every call answers with, when set.
  String? failWith;
  final List<OrgUpdate> updates = [];

  /// A fresh answer every time, the way the server's is: the page writes into
  /// the block it is given.
  OrgSettings _answer() => OrgSettings.fromJson({
    // Growable on purpose: the page writes into the block it is given.
    // ignore: prefer_const_literals_to_create_immutables
    'timeTracking': <String, dynamic>{
      // ignore: prefer_const_literals_to_create_immutables
      'effective': <String, dynamic>{'advancedEnabled': false},
    },
    'defaultDeadlineBasis': defaultDeadlineBasis,
    'effectiveDeadlineBasis': defaultDeadlineBasis ?? effectiveDeadlineBasis,
  });

  @override
  Future<OrgSettings> settings() async {
    if (failWith != null) throw ApiFailure(failWith!, statusCode: 403);
    return _answer();
  }

  @override
  Future<OrgSettings> update({
    Map<String, dynamic>? timeTracking,
    RelativeDateBasis? defaultDeadlineBasis,
    bool clearDefaultDeadlineBasis = false,
  }) async {
    updates.add((
      timeTracking: timeTracking,
      defaultDeadlineBasis: defaultDeadlineBasis,
      clearDefaultDeadlineBasis: clearDefaultDeadlineBasis,
    ));
    if (failWith != null) throw ApiFailure(failWith!, statusCode: 403);
    if (defaultDeadlineBasis != null) {
      this.defaultDeadlineBasis = defaultDeadlineBasis.wire;
    }
    if (clearDefaultDeadlineBasis) this.defaultDeadlineBasis = null;
    return _answer();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// The catalogue and the policy the time-tracking cards read, all empty.
class FakeTimeRepository implements TimeRepository {
  @override
  Future<PageResult<TimeTag>> tags({
    String? query,
    int page = 0,
    int size = 50,
    bool withUsage = false,
  }) async => (items: const <TimeTag>[], total: 0);

  @override
  Future<List<ApprovalPeriod>> approvalPeriods({
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) async => const <ApprovalPeriod>[];

  @override
  Future<TimePolicySnapshot> policy() async => TimePolicySnapshot.none;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// An [AppConfigBloc] with one fixed answer about the server, which records the
/// events it is sent instead of reading `/api/v1/meta`.
class FakeOrgAppConfig extends AppConfigBloc {
  FakeOrgAppConfig({bool projectTemplates = true})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          featureFlags: {PlatformFlags.projectTemplates: projectTemplates},
        ),
      ),
      super(repository: _UnusedMeta(), storage: _UnusedStorage());

  final AppConfigState _fixed;
  final List<AppConfigEvent> events = [];

  @override
  AppConfigState get state => _fixed;

  @override
  void add(AppConfigEvent event) => events.add(event);
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
