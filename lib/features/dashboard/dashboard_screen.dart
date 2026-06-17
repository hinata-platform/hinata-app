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
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart' show HexMark;
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../issues/issue_form.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          FetchCubit<DashboardData>(context.read<HivoraRepository>().dashboard)
            ..load(),
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
          color: AppColors.accent,
          edgeOffset: context.topGutter,
          onRefresh: () => context.read<FetchCubit<DashboardData>>().load(),
          child: AsyncView(
            isLoading: state.isLoading,
            hasData: state.hasData,
            errorKey: state.errorKey,
            onRetry: () => context.read<FetchCubit<DashboardData>>().load(),
            builder: (context) {
              final data = state.data!;
              final wide = !context.isCompact;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  context.pageGutter,
                  24 + context.topGutter,
                  context.pageGutter,
                  context.pageGutter + context.bottomGutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(onCreate: () => showIssueForm(context)),
                    const SizedBox(height: 20),
                    _KpiRow(
                      completion: data.completion,
                      today: data.todayTasks.length,
                    ),
                    const SizedBox(height: 18),
                    if (wide) ...[
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _FocusCard(issues: data.todayTasks),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 2,
                              child: _CompletionCard(
                                completion: data.completion,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _TrackerCard(tracker: data.tracker),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 2,
                              child: _LeaderboardCard(ranking: data.ranking),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      _FocusCard(issues: data.todayTasks),
                      const SizedBox(height: 16),
                      _CompletionCard(completion: data.completion),
                      const SizedBox(height: 16),
                      _TrackerCard(tracker: data.tracker),
                      const SizedBox(height: 16),
                      _LeaderboardCard(ranking: data.ranking),
                    ],
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
    return PageHead(
      title: context.t('dashboard.title'),
      subtitle: context.t('dashboard.subtitle'),
      actions: [
        if (!context.isCompact)
          GhostButton(
            icon: Icons.tune_rounded,
            label: context.t('dashboard.customize'),
            onPressed: () => context.go('/settings'),
          ),
        PrimaryButton(label: context.t('issues.new'), onPressed: onCreate),
      ],
    );
  }
}

// ─────────────────────────── KPI row ───────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.completion, required this.today});

  final ProjectCompletion completion;
  final int today;

  @override
  Widget build(BuildContext context) {
    final items = [
      _Kpi(
        label: context.t('dashboard.kpiToday'),
        value: '$today',
        icon: Icons.inbox_rounded,
        hue: AppColors.stTodo,
      ),
      _Kpi(
        label: context.t('dashboard.inProgress'),
        value: '${completion.inProgress}',
        icon: Icons.hourglass_top_rounded,
        hue: AppColors.stProgress,
      ),
      _Kpi(
        label: context.t('dashboard.backlog'),
        value: '${completion.backlog}',
        icon: Icons.layers_rounded,
        hue: AppColors.stBacklog,
      ),
      _Kpi(
        label: context.t('dashboard.done'),
        value: '${completion.done}',
        icon: Icons.check_circle_rounded,
        hue: AppColors.stDone,
      ),
    ];
    final columns = context.isCompact ? 2 : 4;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 18.0;
        final width = ((c.maxWidth - gap * (columns - 1)) / columns) - 0.5;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final k in items) SizedBox(width: width, child: k)],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.hue,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.soft(hue),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 15, color: hue),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.5,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Focus list ────────────────────────────────────

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.issues});
  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.todayTask'),
            leading: HexMark(size: 18),
            actionLabel: context.t('common.seeAll'),
            onAction: () => context.go('/issues'),
          ),
          const SizedBox(height: 14),
          if (issues.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                context.t('dashboard.noTasks'),
                style: TextStyle(color: AppColors.inkSoft),
              ),
            )
          else
            for (final issue in issues.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FocusItem(issue: issue),
              ),
        ],
      ),
    );
  }
}

class _FocusItem extends StatelessWidget {
  const _FocusItem({required this.issue});
  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final progress =
        (issue.estimateMinutes != null && issue.estimateMinutes! > 0)
        ? (issue.spentMinutes / issue.estimateMinutes!).clamp(0.0, 1.0)
        : 0.0;
    final due = dueLabel(issue.dueDate);
    return InkWell(
      onTap: () => showIssueDetailSheet(
        context,
        issueId: issue.id,
        onChanged: () => context.read<FetchCubit<DashboardData>>().load(),
      ),
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          children: [
            TypeGlyph(type: issue.type),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                issue.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (issue.estimateMinutes != null && issue.estimateMinutes! > 0)
              SizedBox(width: 56, child: HiveProgress(value: progress)),
            if (due != null) ...[
              const SizedBox(width: 10),
              Text(
                due.text,
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 11.5,
                  color: due.late ? AppColors.danger : AppColors.inkSoft,
                ),
              ),
            ],
            const SizedBox(width: 10),
            IdMono(issue.readableId),
            const SizedBox(width: 10),
            if (issue.assigneeId != null)
              HiveAvatar(name: issue.assigneeId!, size: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Completion donut ──────────────────────────────

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completion});
  final ProjectCompletion completion;

  @override
  Widget build(BuildContext context) {
    final segs = [
      (context.t('dashboard.done'), completion.donePercent, AppColors.stDone),
      (
        context.t('dashboard.inProgress'),
        completion.inProgressPercent,
        AppColors.stProgress,
      ),
      (
        context.t('dashboard.backlog'),
        completion.backlogPercent,
        AppColors.stBacklog,
      ),
    ];
    final doneRounded = (completion.donePercent * 100).round();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.projectCompleted'),
            actionLabel: context.t(
              'dashboard.totalIssues',
              variables: {'count': '${completion.total}'},
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 40,
                        startDegreeOffset: -90,
                        sections: [
                          for (final (_, percent, color) in segs)
                            PieChartSectionData(
                              value: percent <= 0 ? 0.001 : percent,
                              color: color,
                              radius: 14,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    TweenAnimationBuilder<int>(
                      duration: const Duration(milliseconds: 900),
                      curve: hiveEase,
                      tween: IntTween(begin: 0, end: doneRounded),
                      builder: (_, value, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$value%',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBrand,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            context.t('dashboard.resolvedLabel'),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, percent, color) in segs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                            Text(
                              '${(percent * 100).round()}%',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Weekly tracker ────────────────────────────────

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.tracker});
  final List<TrackerDay> tracker;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = tracker.fold<int>(
      60,
      (m, d) => d.focusMinutes > m ? d.focusMinutes : m,
    );
    final total = tracker.fold<int>(0, (s, d) => s + d.focusMinutes);
    const days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.trackerDetail'),
            actionLabel: context.t(
              'dashboard.tracked',
              variables: {'time': fmtDuration(total)},
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: maxMinutes / 60,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= tracker.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            days[(tracker[i].date.weekday - 1) % 7],
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 10.5,
                              color: AppColors.inkFaint,
                            ),
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
                          width: 16,
                          borderRadius: BorderRadius.circular(99),
                          color: i.isEven ? AppColors.accent : AppColors.navy,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxMinutes / 60,
                            color: AppColors.canvas2,
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

// ─────────────────────────── Leaderboard ───────────────────────────────────

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.ranking});
  final List<RankEntry> ranking;

  @override
  Widget build(BuildContext context) {
    final shown = ranking.take(5).toList();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(title: context.t('dashboard.rankPerformance')),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.t('dashboard.noRanking'),
                style: TextStyle(color: AppColors.inkSoft),
              ),
            ),
          for (final (i, entry) in shown.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: i == shown.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: AppColors.hairline2)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 12,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                  HiveAvatar(name: entry.displayName, size: 30),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entry.title != null)
                          Text(
                            entry.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkSoft,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    context.t(
                      'dashboard.points',
                      variables: {'count': '${entry.points}'},
                    ),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentStrong,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Card header ───────────────────────────────────

class _CardHead extends StatelessWidget {
  const _CardHead({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.leading,
  });

  final String title;
  final Widget? leading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: leading),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: AppColors.ink,
            ),
          ),
        ),
        if (actionLabel != null)
          onAction != null
              ? GestureDetector(
                  onTap: onAction,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentStrong,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 13,
                        color: AppColors.accentStrong,
                      ),
                    ],
                  ),
                )
              : Text(
                  actionLabel!,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
                ),
      ],
    );
  }
}
