import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/time_usage_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_models.dart';
import '../../../core/widgets/budget/budget.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassToast;

/// What every place that saves an entry says afterwards, said once.
///
/// The overlap advice and the budget advice (HIN-153) arrive with the same
/// answer, and only one toast shows at a time: two separate toasts would
/// replace each other before the first was read. So both go into one, the
/// overlap first because it is about the entry itself. And the project's bars
/// everywhere learn the new figures at once.
void announceSavedEntry(BuildContext context, SavedTimeEntry saved) {
  final projectId = saved.entry.projectId;
  if (projectId != null) {
    try {
      unawaited(context.read<TimeUsageCubit>().refresh(projectId));
    } on ProviderNotFoundException {
      // No usage cubit in this tree (a test of one sheet): nothing to refresh.
    }
  }
  final lines = <String>[
    if (saved.hasOverlaps)
      // count: rather than a {'count': ...} variable. i18next casts the
      // variable to int to pick a plural form; a string casts to null.
      context.t('time.overlapWarning', count: saved.overlaps.length),
    ?budgetLine(context, saved.budgetWarnings),
  ];
  if (lines.isEmpty) return;
  showGlassToast(context, lines.join('\n'), kind: GlassToastKind.warning);
}

/// The one sentence about the most pressing limit a save touched, or null:
/// a limit passed before one only near, the fuller before the emptier.
String? budgetLine(BuildContext context, List<BudgetWarning> warnings) {
  if (warnings.isEmpty) return null;
  final worst = [...warnings]
    ..sort((a, b) {
      if (a.over != b.over) return a.over ? -1 : 1;
      return b.percent.compareTo(a.percent);
    });
  final warning = worst.first;
  final gauge = BudgetGauge(used: warning.used, limit: warning.limit);
  final state = gauge.reached
      ? 'reached'
      : warning.over
      ? 'over'
      : 'near';
  return context.t(
    'budget.toast.$state.${warning.kind}',
    variables: {
      'percent': BudgetStyle.percent(context, gauge),
      'sums': BudgetStyle.usedOfLimit(context, gauge, budgetMinutes),
      'left': budgetMinutes(context, gauge.left),
    },
  );
}
