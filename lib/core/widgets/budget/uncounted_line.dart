import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../hive_widgets.dart' show fmtDuration;

/// The recorded time a money budget leaves out, and why (HIN-158): hours that
/// are not billable, which a revenue budget does not value, and hours no rate
/// was in force for on their day. Nothing when every hour counts.
///
/// Without it a money budget can sit at zero beside a time budget that has
/// clearly moved, and the reader is left to guess which setting is missing.
class UncountedLine extends StatelessWidget {
  const UncountedLine({
    super.key,
    required this.unbilledMinutes,
    required this.unratedMinutes,
    this.costBudget = false,
    this.onOpenRates,
  });

  final int unbilledMinutes;
  final int unratedMinutes;

  /// Valued at cost rates: the missing rate is a cost rate, which only an
  /// organization admin sets, and a project's revenue rate does not stand in
  /// for it.
  final bool costBudget;

  /// The way to the rates, offered while hours lack one. Null leaves it out.
  final VoidCallback? onOpenRates;

  @override
  Widget build(BuildContext context) {
    final lines = [
      if (unbilledMinutes > 0)
        context.t(
          'budget.money.unbilled',
          variables: {'duration': fmtDuration(context, unbilledMinutes)},
        ),
      if (unratedMinutes > 0)
        context.t(
          costBudget ? 'budget.money.unratedCost' : 'budget.money.unrated',
          variables: {'duration': fmtDuration(context, unratedMinutes)},
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    LucideIcons.info,
                    size: 14,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: AppType.caption,
                      height: 1.4,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (unratedMinutes > 0 && onOpenRates != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onOpenRates,
              icon: const Icon(LucideIcons.badgePercent, size: 16),
              label: Text(context.t('billing.rates.title')),
            ),
          ),
      ],
    );
  }
}
