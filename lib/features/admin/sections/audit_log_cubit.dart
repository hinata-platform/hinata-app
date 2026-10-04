import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/audit_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/org_settings_repository.dart';

/// Reads one filtered page of an audit feed.
typedef AuditLoader =
    Future<AuditPage> Function({
      String query,
      AuditCategory? category,
      AuditSeverity? severity,
      String? outcome,
      int page,
      int perPage,
    });

/// The feed behind an audit timeline: the platform admin's, or the
/// organisation's own (HIN-129). Both pages draw the same timeline.
///
/// Holds no state: the timeline keeps its pages, filters and request token
/// itself, because a page that lands after a newer filter is dropped there.
/// Failures pass through as the repository's `ApiFailure`.
class AuditLogCubit extends Cubit<void> {
  AuditLogCubit(this._load) : super(null);

  AuditLogCubit.admin(AdminRepository admin) : this(admin.auditLog);

  AuditLogCubit.organization(OrgSettingsRepository org) : this(org.auditLog);

  final AuditLoader _load;

  /// One page (1-based) of the feed, narrowed by the filters given.
  Future<AuditPage> entries({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? outcome,
    int page = 1,
    int perPage = 30,
  }) => _load(
    query: query,
    category: category,
    severity: severity,
    outcome: outcome,
    page: page,
    perPage: perPage,
  );
}
