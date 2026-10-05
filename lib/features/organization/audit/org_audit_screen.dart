import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/org_settings_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../admin/sections/admin_audit_section.dart';
import '../../admin/sections/audit_log_cubit.dart';

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
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        AuditLogCubit.organization(context.read<OrgSettingsRepository>()),
    child: Builder(
      builder: (context) {
        // Compact: the section docks its filter bar into its own app bar.
        if (context.isCompact) {
          return AdminAuditSection(
            titleKey: _titleKey,
            onBack: () => context.go('/organization'),
          );
        }
        // Wide: the log is a section of the Organisation page, beside its
        // rail. A deep link, or a window widened while it was open, lands
        // there.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/organization?section=audit');
        });
        return const SizedBox.shrink();
      },
    ),
  );
}
