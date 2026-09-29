import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/repositories/org_settings_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../admin/sections/admin_audit_section.dart';
import '../../shell/page_chrome.dart';

/// Organisation → Protokoll (HIN-129): the organisation's own audit records.
///
/// Time entries, absences, timesheets and the other organisational events
/// left the platform admin's feed for anyone who is not also an organisation
/// admin; this is where they are read now. The timeline, filters and detail
/// sheet are the admin log's, over `GET /api/v1/org/audit`.
class OrgAuditScreen extends StatelessWidget {
  const OrgAuditScreen({super.key});

  static const _titleKey = 'org.audit.title';

  @override
  Widget build(BuildContext context) {
    final load = context.read<OrgSettingsRepository>().auditLog;
    // Compact: the section docks its filter bar into its own app bar.
    if (context.isCompact) {
      return AdminAuditSection(
        load: load,
        titleKey: _titleKey,
        onBack: () => context.go('/organization'),
      );
    }
    return PageChrome(
      title: context.t(_titleKey),
      child: Padding(
        padding: EdgeInsets.only(top: context.topGutter + 14),
        child: AdminAuditSection(load: load, titleKey: _titleKey),
      ),
    );
  }
}
