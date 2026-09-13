import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../time/correction_requests.dart';
import '../admin_form_helpers.dart';

/// Admin → Time tracking: the correction requests waiting for an answer.
///
/// Beside the lock exceptions on purpose. A request about the lock date is
/// answered here, and the act that actually opens the day is the card above it:
/// both halves of the way back out of a freeze sit on one screen.
class AdminCorrectionRequestsCard extends StatelessWidget {
  const AdminCorrectionRequestsCard({super.key});

  @override
  Widget build(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.messageSquareWarning,
    title: context.t('admin.timeTracking.correctionsTitle'),
    subtitle: context.t('admin.timeTracking.correctionsHint'),
    children: const [CorrectionRequestsList(embedded: true)],
  );
}
