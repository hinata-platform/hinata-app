import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/models/time_usage_models.dart';
import '../../../core/repositories/time_usage_repository.dart';
import '../../../core/widgets/budget/budget.dart';
import '../../billing/billing_format.dart';
import 'project_usage.dart';

/// What the entry being typed does to its issue's estimate and its project's
/// budget, shown in the form before it is saved (HIN-153).
///
/// Quiet below the warning share, counting the entry. Shows the issue first,
/// because that is what somebody picked last, then the project. Nothing for a
/// project in OPEN mode, and nothing with the extended module off. It never
/// stops the save.
class EntryBudgetNotes extends StatefulWidget {
  const EntryBudgetNotes({
    super.key,
    required this.projectId,
    required this.issueId,
    required this.issueLabel,
    required this.projectLabel,
    required this.pendingMinutes,
    this.compact = false,
  });

  final String? projectId;
  final String? issueId;

  /// The issue's key, as the notice names it.
  final String? issueLabel;

  /// The project's name.
  final String? projectLabel;

  /// What this entry adds: its minutes, or the difference to what it had
  /// before when an entry is edited in place.
  final int pendingMinutes;

  /// Drops the explaining line, for a timesheet cell.
  final bool compact;

  @override
  State<EntryBudgetNotes> createState() => _EntryBudgetNotesState();
}

class _EntryBudgetNotesState extends State<EntryBudgetNotes> {
  IssueTimeUsage? _issue;
  String? _askedIssue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIssue();
  }

  @override
  void didUpdateWidget(EntryBudgetNotes old) {
    super.didUpdateWidget(old);
    if (old.issueId != widget.issueId) _loadIssue();
  }

  /// Whether the extended module is on; false where no config is provided,
  /// as in a test of one sheet.
  bool get _enabled {
    try {
      return context.read<AppConfigBloc>().state.meta?.advancedTimeTracking ??
          false;
    } on ProviderNotFoundException {
      return false;
    }
  }

  void _loadIssue() {
    final id = widget.issueId;
    if (id == _askedIssue) return;
    _askedIssue = id;
    _issue = null;
    if (id == null || !_enabled) return;
    TimeUsageRepository repository;
    try {
      repository = context.read<TimeUsageRepository>();
    } on ProviderNotFoundException {
      return;
    }
    unawaited(
      repository.issue(id).then(
        (usage) {
          if (mounted && _askedIssue == id) setState(() => _issue = usage);
        },
        // A side note: a failed read shows no note, never an error.
        onError: (Object _) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pendingMinutes < 0 ? 0 : widget.pendingMinutes;
    final issue = _issue;
    final notes = <Widget>[
      if (issue != null && issue.warns && issue.estimate != null)
        BudgetNotice(
          kind: BudgetNoticeKind.issueEstimate,
          subject: widget.issueLabel ?? '',
          gauge: issue.estimate!,
          pending: pending,
          compact: widget.compact,
        ),
    ];
    final projectId = widget.projectId;
    final project = projectId == null
        ? null
        : ProjectUsage(
            projectId: projectId,
            builder: (context, usage) {
              final budget = usage?.budget;
              final money = usage?.money;
              if (usage == null || !usage.budgetWarns) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (budget != null)
                    BudgetNotice(
                      kind: BudgetNoticeKind.projectBudget,
                      subject: widget.projectLabel ?? '',
                      gauge: budget,
                      pending: pending,
                      compact: widget.compact,
                    ),
                  // The money budget for a reader who may see it (HIN-155).
                  // Without the entry counted: what it is worth depends on
                  // a rate only the server resolves.
                  if (money != null && money.level != BudgetLevel.within) ...[
                    if (budget != null) const SizedBox(height: 8),
                    BudgetNotice(
                      kind: BudgetNoticeKind.moneyBudget,
                      subject: widget.projectLabel ?? '',
                      gauge: money,
                      format: (context, cents) =>
                          formatMoney(context, cents, usage.currency!),
                      compact: widget.compact,
                    ),
                  ],
                ],
              );
            },
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final note in notes) ...[note, const SizedBox(height: 8)],
        ?project,
      ],
    );
  }
}
