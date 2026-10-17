import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/budget/budget.dart';
import '../../billing/billing_format.dart';
import 'project_usage.dart';

/// A project's budgets as capsules for a head or a card (HIN-152, HIN-155):
/// the time budget, and beside it the money budget for a reader who may see
/// it. Nothing for a project without either.
class ProjectBudgetCapsules extends StatelessWidget {
  const ProjectBudgetCapsules({
    super.key,
    required this.projectId,
    this.padding = EdgeInsets.zero,
  });

  final String projectId;

  /// Around the capsules when there are any, so an empty slot takes no room.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ProjectUsage(
      projectId: projectId,
      builder: (context, usage) {
        final time = usage?.budget;
        final money = usage?.money;
        if (time == null && money == null) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (time != null)
                BudgetCapsule(
                  label: context.t('budget.timeBudget'),
                  gauge: time,
                ),
              if (money != null)
                BudgetCapsule(
                  label: context.t(
                    usage!.costBudget
                        ? 'budget.money.cost'
                        : 'budget.money.revenue',
                  ),
                  gauge: money,
                  format: (context, cents) =>
                      formatMoney(context, cents, usage.currency!),
                ),
            ],
          ),
        );
      },
    );
  }
}
