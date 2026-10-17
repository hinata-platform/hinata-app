import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_usage_models.dart';
import '../../core/blocs/time_usage_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/budget/budget.dart';
import '../../core/widgets/frosted_card.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../billing/billing_format.dart';
import '../time/budget/budget_history_sheet.dart';
import 'report_budgets_cubit.dart';

/// Every budget the reader sees, fullest first (HIN-157): one frosted card
/// per project with its tubes and its forecast, the way to its history, and
/// over them the active sprints that have a budget.
///
/// Paged from the server twenty at a time and read on as the list scrolls; the
/// sprints come with the first page. Money only for readers the server gives
/// it to.
class ReportBudgetsView extends StatefulWidget {
  const ReportBudgetsView({
    super.key,
    required this.padding,
    this.projectIds = const [],
  });

  final EdgeInsets padding;

  /// The report's project filter; empty for every project.
  final List<String> projectIds;

  @override
  State<ReportBudgetsView> createState() => _ReportBudgetsViewState();
}

class _ReportBudgetsViewState extends State<ReportBudgetsView> {
  ReportBudgetsCubit? _pages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pages ??= _cubit();
  }

  ReportBudgetsCubit? _cubit() {
    final usage = TimeUsageCubit.maybeOf(context);
    if (usage == null) return null;
    return ReportBudgetsCubit(usage, projectIds: widget.projectIds)..load();
  }

  @override
  void didUpdateWidget(ReportBudgetsView old) {
    super.didUpdateWidget(old);
    if (old.projectIds.join(',') != widget.projectIds.join(',')) {
      unawaited(_pages?.close());
      _pages = _cubit();
    }
  }

  @override
  void dispose() {
    unawaited(_pages?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages == null) return _empty();
    return BlocBuilder<ReportBudgetsCubit, PagedState<ProjectTimeUsage>>(
      bloc: pages,
      builder: (context, state) {
        if (state.isLoading && state.items.isEmpty) {
          return const Center(child: HiveLoader());
        }
        final sprints = pages.sprints;
        if (state.items.isEmpty && sprints.isEmpty) return _empty();
        final head = sprints.isEmpty ? 0 : 1;
        return RefreshIndicator(
          onRefresh: pages.load,
          child: ListView.builder(
            padding: widget.padding,
            itemCount: head + state.items.length + 1,
            itemBuilder: (context, index) {
              if (head == 1 && index == 0) return _sprintCard(sprints);
              final row = index - head;
              if (row == state.items.length) {
                if (state.hasMore) {
                  unawaited(pages.loadMore());
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: HiveLoader(size: 22)),
                  );
                }
                return const SizedBox(height: 8);
              }
              final usage = state.items[row];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ProjectBudget(
                  usage: usage,
                  name: pages.names[usage.projectId] ?? '',
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _empty() => ListView(
    padding: widget.padding,
    children: [
      HiveEmptyState(
        title: context.t('budget.report.emptyTitle'),
        message: context.t('budget.dashboard.emptyHint'),
      ),
    ],
  );

  Widget _sprintCard(List<BudgetedSprint> sprints) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: FrostedCard(
      title: context.t('budget.report.sprints'),
      child: Column(
        children: [
          for (final sprint in sprints)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: BudgetMeter(
                label: '${sprint.name} · ${sprint.board}',
                gauge: sprint.gauge,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ProjectBudget extends StatelessWidget {
  const _ProjectBudget({required this.usage, required this.name});

  final ProjectTimeUsage usage;
  final String name;

  @override
  Widget build(BuildContext context) {
    final money = usage.money;
    return FrostedCard(
      title: name,
      trailing: IconButton(
        tooltip: context.t('budget.history.open'),
        onPressed: () => showBudgetHistorySheet(
          context,
          projectId: usage.projectId,
          projectName: name,
        ),
        icon: Icon(LucideIcons.chartArea, size: 18, color: AppColors.inkSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (usage.budget case final budget?)
            BudgetMeter(
              label: context.t('budget.timeBudget'),
              gauge: budget,
              footer: ProjectForecast(
                projectId: usage.projectId,
                builder: (context, forecast) => forecast == null
                    ? const SizedBox.shrink()
                    : ForecastLine(forecast: forecast),
              ),
            ),
          if (usage.estimates case final estimates?) ...[
            const SizedBox(height: 16),
            BudgetMeter(label: context.t('budget.estimates'), gauge: estimates),
          ],
          if (money != null) ...[
            const SizedBox(height: 16),
            BudgetMeter(
              label: context.t(
                usage.costBudget ? 'budget.money.cost' : 'budget.money.revenue',
              ),
              gauge: money,
              format: (context, cents) =>
                  formatMoney(context, cents, usage.currency!),
            ),
          ],
        ],
      ),
    );
  }
}
