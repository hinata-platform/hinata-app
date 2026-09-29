import '../api/api_client.dart';
import '../models/audit_models.dart';
import '../models/work_models.dart' show RelativeDateBasis;

/// What an organisation admin keeps for the organisation (HIN-129): the
/// time-tracking policies and the default basis of new relative deadlines.
///
/// [timeTracking] is the same block the admin settings used to carry, with the
/// server's read-only `effective` beside the stored values. It is handed to the
/// page as its draft, so it is a fresh, mutable map on every read, which the
/// policy controls write into. The class is therefore deliberately not
/// immutable; the two basis fields are only ever replaced with a new read.
class OrgSettings {
  const OrgSettings({
    required this.timeTracking,
    this.defaultDeadlineBasis,
    this.effectiveDeadlineBasis = RelativeDateBasis.calendar,
  });

  /// The time-tracking block, the page's draft.
  final Map<String, dynamic> timeTracking;

  /// The basis this organisation chose for new relative deadlines, or null
  /// while it follows the platform's default.
  final RelativeDateBasis? defaultDeadlineBasis;

  /// What is in force: [defaultDeadlineBasis], or the platform's default while
  /// that is null.
  final RelativeDateBasis effectiveDeadlineBasis;

  factory OrgSettings.fromJson(Map<String, dynamic> json) => OrgSettings(
    timeTracking: json['timeTracking'] is Map
        ? Map<String, dynamic>.of(json['timeTracking'] as Map<String, dynamic>)
        : <String, dynamic>{},
    defaultDeadlineBasis: json['defaultDeadlineBasis'] is String
        ? RelativeDateBasis.fromWire(json['defaultDeadlineBasis'] as String)
        : null,
    effectiveDeadlineBasis: RelativeDateBasis.fromWire(
      json['effectiveDeadlineBasis'] as String?,
    ),
  );
}

/// The organisation settings behind `/api/v1/org/settings`. Organisation admins
/// only: anyone else is answered 403 `error.org.adminOnly`.
class OrgSettingsRepository {
  OrgSettingsRepository(this._api);

  final ApiClient _api;

  Future<OrgSettings> settings() async => OrgSettings.fromJson(
    await _api.get('/api/v1/org/settings') as Map<String, dynamic>,
  );

  /// Writes what is given and leaves the rest as stored.
  ///
  /// [timeTracking] goes without its read-only `effective` block. A
  /// [defaultDeadlineBasis] sets the organisation's own basis;
  /// [clearDefaultDeadlineBasis] hands it back to the platform's default.
  /// Send neither while project templates are off.
  Future<OrgSettings> update({
    Map<String, dynamic>? timeTracking,
    RelativeDateBasis? defaultDeadlineBasis,
    bool clearDefaultDeadlineBasis = false,
  }) async => OrgSettings.fromJson(
    await _api.put(
          '/api/v1/org/settings',
          body: {
            'timeTracking': ?(timeTracking == null
                ? null
                : ({...timeTracking}..remove('effective'))),
            'defaultDeadlineBasis': ?defaultDeadlineBasis?.wire,
            if (clearDefaultDeadlineBasis) 'clearDefaultDeadlineBasis': true,
          },
        )
        as Map<String, dynamic>,
  );

  /// One page of the organisation's audit records: time, absences, timesheets
  /// and the other organisational events. Same filters and shape as the admin
  /// feed; the platform admin's feed no longer carries these for anyone who
  /// is not also an organisation admin.
  Future<AuditPage> auditLog({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? outcome,
    int page = 1,
    int perPage = 30,
  }) async => AuditPage.fromJson(
    await _api.get(
          '/api/v1/org/audit',
          query: auditQuery(
            query: query,
            category: category,
            severity: severity,
            outcome: outcome,
            page: page,
            perPage: perPage,
          ),
        )
        as Map<String, dynamic>,
  );
}
