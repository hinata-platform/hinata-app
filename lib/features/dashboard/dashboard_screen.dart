import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../issues/issue_form.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          FetchCubit<DashboardData>(context.read<HivoraRepository>().dashboard)..load(),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FetchCubit<DashboardData>, FetchState<DashboardData>>(
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: () => context.read<FetchCubit<DashboardData>>().load(),
          child: AsyncView(
            isLoading: state.isLoading,
            hasData: state.hasData,
            errorKey: state.errorKey,
            onRetry: () => context.read<FetchCubit<DashboardData>>().load(),
            builder: (context) {
              final data = state.data!;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(context.pageGutter),
                child: context.isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(onCreate: () => showIssueForm(context)),
                          const SizedBox(height: 16),
                          _TodayTasks(issues: data.todayTasks),
                          const SizedBox(height: 16),
                          _CompletionCard(completion: data.completion),
                          const SizedBox(height: 16),
                          _RankCard(ranking: data.ranking),
                          const SizedBox(height: 16),
                          _TrackerCard(tracker: data.tracker),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(onCreate: () => showIssueForm(context)),
                          const SizedBox(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _TodayTasks(issues: data.todayTasks),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 2,
                                child: _CompletionCard(completion: data.completion),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _RankCard(ranking: data.ranking)),
                              const SizedBox(width: 20),
                              Expanded(child: _TrackerCard(tracker: data.tracker)),
                            ],
                          ),
                        ],
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('dashboard.title'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                context.t('dashboard.subtitle'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(context.t('issues.new')),
        ),
      ],
    );
  }
}

class _TodayTasks extends StatelessWidget {
  const _TodayTasks({required this.issues});

  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: context.t('dashboard.todayTask'),
            actionLabel: context.t('common.seeAll'),
            onAction: () => context.go('/issues'),
          ),
          const SizedBox(height: 12),
          if (issues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.t('dashboard.noTasks'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: issues.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final issue = issues[index];
                  return _TaskCard(issue: issue, index: index);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.issue, required this.index});

  final Issue issue;
  final int index;

  @override
  Widget build(BuildContext context) {
    final progress = issue.estimateMinutes != null && issue.estimateMinutes! > 0
        ? (issue.spentMinutes / issue.estimateMinutes!).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      width: 220,
      child: SoftCard(
        color: AppColors.pastelFor(index),
        onTap: () => context.go('/issues/${issue.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PillChip(
              label: context.t('priority.${issue.priority.toLowerCase()}'),
              foreground: priorityColor(issue.priority),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Text(
                issue.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.6),
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  issue.readableId,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completion});

  final ProjectCompletion completion;

  @override
  Widget build(BuildContext context) {
    final entries = [
      (context.t('dashboard.done'), completion.donePercent, AppColors.accentPurple),
      (context.t('dashboard.inProgress'), completion.inProgressPercent,
          AppColors.accentOrange),
      (context.t('dashboard.backlog'), completion.backlogPercent, AppColors.accentBlue),
    ];
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: context.t('dashboard.projectCompleted'),
            actionLabel: context.t('dashboard.totalIssues',
                variables: {'count': '${completion.total}'}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, percent, color) in entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary, fontSize: 13)),
                            ),
                            Text(
                              '${(percent * 100).round()}%',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: 38,
                    startDegreeOffset: -90,
                    sections: [
                      for (final (_, percent, color) in entries)
                        PieChartSectionData(
                          value: percent <= 0 ? 0.001 : percent,
                          color: color,
                          radius: 16,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.ranking});

  final List<RankEntry> ranking;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: context.t('dashboard.rankPerformance')),
          const SizedBox(height: 4),
          if (ranking.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.t('dashboard.noRanking'),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
          for (final entry in ranking.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor:
                    AppColors.pastelFor(entry.displayName.hashCode.abs()),
                child: Text(
                  entry.displayName.isEmpty
                      ? '?'
                      : entry.displayName.characters.first.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(entry.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: entry.title != null
                  ? Text(entry.title!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12))
                  : null,
              trailing: Text(
                context.t('dashboard.points', variables: {'count': '${entry.points}'}),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.tracker});

  final List<TrackerDay> tracker;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = tracker.fold<int>(60, (max, day) =>
        day.focusMinutes > max ? day.focusMinutes : max);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: context.t('dashboard.trackerDetail'),
            actionLabel: context.t('common.seeAll'),
            onAction: () => context.go('/timesheet'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxMinutes / 60,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= tracker.length) {
                          return const SizedBox.shrink();
                        }
                        const days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            days[(tracker[index].date.weekday - 1) % 7],
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < tracker.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: tracker[i].focusMinutes / 60,
                          width: 18,
                          borderRadius: BorderRadius.circular(9),
                          color: i.isEven
                              ? AppColors.accentOrange
                              : AppColors.accentTeal,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxMinutes / 60,
                            color: AppColors.surfaceMuted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
