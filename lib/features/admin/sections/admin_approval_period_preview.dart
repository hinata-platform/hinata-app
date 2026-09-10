import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_approval_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../time/lock_notice.dart';
import '../admin_form_helpers.dart';

/// The next three periods the configured rhythm will cut.
///
/// An operator picking "biweekly from the 3rd" has no way to know which days that
/// makes, and the cost of getting it wrong is a payroll period that is a day
/// short. So the choice is shown rather than described — and **fetched**, never
/// derived here: the arithmetic lives once, on the server, because two
/// implementations would disagree on exactly one day a year and nobody would
/// notice until somebody complained about their hours.
///
/// A note rather than a refusal when the rhythm has no grid: under FREE the
/// person submitting picks their own span, so there are no periods to preview and
/// saying so is the preview.
class ApprovalPeriodPreview extends StatefulWidget {
  const ApprovalPeriodPreview({super.key, required this.rhythm});

  /// The type currently chosen in the form.
  ///
  /// The preview itself always shows the *saved* rhythm — the server computes from
  /// the stored policy, which is the only thing it can honestly do. This is here so
  /// that a change re-asks, and the note below says which one is being shown.
  final String? rhythm;

  @override
  State<ApprovalPeriodPreview> createState() => _ApprovalPeriodPreviewState();
}

class _ApprovalPeriodPreviewState extends State<ApprovalPeriodPreview> {
  List<ApprovalPeriod>? _periods;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ApprovalPeriodPreview old) {
    super.didUpdateWidget(old);
    // The saved rhythm is what the server answers about, so the preview is only
    // correct after a save — which is exactly what the note below says. Re-asking
    // on a change keeps it from showing the *previous* rhythm's periods once the
    // save has landed.
    if (old.rhythm != widget.rhythm) unawaited(_load());
  }

  Future<void> _load() async {
    if (widget.rhythm == 'FREE') {
      // Not a fetch and not a failure: there are no periods under a free rhythm,
      // and saying so *is* the preview. `_failed` is cleared with it, or one
      // earlier failure would keep hiding this note for the life of the screen.
      if (mounted) {
        setState(() {
          _periods = const [];
          _failed = false;
        });
      }
      return;
    }
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Just wide enough for three periods of the widest rhythm the form offers —
      // three quarters — and no wider. The route pays for the window it is given:
      // an aggregation over the reader's entries and a status per project per
      // period, all but three of which this widget throws away.
      final periods = await context.read<TimeRepository>().approvalPeriods(
        from: DateTime(today.year, today.month, 1),
        to: DateTime(today.year, today.month + 9, 1),
      );
      if (!mounted) return;
      setState(() {
        _periods = periods
            .where((period) => !period.end.isBefore(today))
            .take(3)
            .toList(growable: false);
        _failed = false;
      });
    } on ApiFailure {
      // With approvals off the route does not exist, which is not an error — it
      // is the answer. Either way a preview that cannot be fetched says nothing
      // rather than something wrong.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    if (widget.rhythm == 'FREE') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AdminNote(
          icon: LucideIcons.calendarRange,
          tone: AdminNoteTone.info,
          text: context.t('admin.timeTracking.periodPreviewFree'),
        ),
      );
    }
    final periods = _periods;
    if (periods == null || periods.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('admin.timeTracking.periodPreviewTitle'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 6),
            for (final period in periods)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.calendarDays,
                      size: 12,
                      color: AppColors.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        formatPeriod(context, period.start, period.end),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              context.t('admin.timeTracking.periodPreviewHint'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
