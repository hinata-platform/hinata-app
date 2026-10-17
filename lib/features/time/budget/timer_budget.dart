import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/time_usage_cubit.dart';

import '../../../core/blocs/timer_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_usage_models.dart';
import '../../../core/widgets/budget/budget.dart';
import 'project_usage.dart';

/// The running timer's issue estimate, or its project's budget, as a tiny
/// honey tube in the timer bar (HIN-154), counting the minutes that are
/// running now.
///
/// Rebuilds once a minute, not once a second: the figure moves in minutes.
/// With [onlyWhenNear] (the phone's one-line bar) it appears only from the
/// warning share on, because there every point of width is the description's.
class TimerBudget extends StatefulWidget {
  const TimerBudget({
    super.key,
    required this.projectId,
    required this.issueId,
    this.onlyWhenNear = false,
  });

  final String? projectId;
  final String? issueId;
  final bool onlyWhenNear;

  @override
  State<TimerBudget> createState() => _TimerBudgetState();
}

class _TimerBudgetState extends State<TimerBudget> {
  IssueTimeUsage? _issue;
  String? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(TimerBudget old) {
    super.didUpdateWidget(old);
    if (old.issueId != widget.issueId) _load();
  }

  void _load() {
    final id = widget.issueId;
    if (id == _asked) return;
    _asked = id;
    _issue = null;
    if (id == null) return;
    final cubit = TimeUsageCubit.maybeOf(context);
    if (cubit == null) return;
    unawaited(
      cubit.issue(id).then((usage) {
        if (mounted && _asked == id) setState(() => _issue = usage);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = context.select<TimerCubit, int>(
      (cubit) => cubit.state.elapsed.inMinutes,
    );
    BudgetGauge? lift(BudgetGauge? gauge) => gauge == null
        ? null
        : BudgetGauge(
            used: gauge.used + running,
            limit: gauge.limit,
            nearPercent: gauge.nearPercent,
          );
    Widget dot(String label, BudgetGauge gauge) {
      if (widget.onlyWhenNear && gauge.level == BudgetLevel.within) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 10),
        child: TimerBudgetDot(label: label, gauge: gauge),
      );
    }

    final issue = lift(_issue?.estimate);
    if (issue != null) return dot(context.t('budget.estimate'), issue);
    final projectId = widget.projectId;
    if (projectId == null) return const SizedBox.shrink();
    return ProjectUsage(
      projectId: projectId,
      builder: (context, usage) {
        final budget = lift(usage?.budget);
        if (budget == null) return const SizedBox.shrink();
        return dot(context.t('budget.timeBudget'), budget);
      },
    );
  }
}
