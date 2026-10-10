import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/billing_models.dart';
import '../../core/repositories/billing_repository.dart';
import 'rate_timeline_sheet.dart';

/// The issue's own hourly rate (HIN-96), from its detail: for the project's
/// lead, who prices the work. Opens the issue's rate timeline, where a rate
/// is set from a day on and overrides every other rate for this issue.
class IssueRateButton extends StatelessWidget {
  const IssueRateButton({
    super.key,
    required this.issueId,
    required this.label,
  });

  final String issueId;

  /// What the sheet calls the issue: its readable id and title.
  final String label;

  Future<void> _open(BuildContext context) async {
    final billing = context.read<BillingRepository>();
    String currency = 'EUR';
    try {
      currency = (await billing.access()).currency;
    } on ApiFailure {
      // The sheet still opens; it shows the rates in their own currency.
    }
    if (!context.mounted) return;
    await showRateTimelineSheet(
      context,
      billing: billing,
      target: RateTarget(
        kind: RateKind.billable,
        scope: RateScope.issue,
        scopeId: issueId,
        label: label,
      ),
      currency: currency,
    );
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      onPressed: () => unawaited(_open(context)),
      icon: const Icon(LucideIcons.coins, size: 16),
      label: Text(context.t('billing.issueRate')),
    ),
  );
}
