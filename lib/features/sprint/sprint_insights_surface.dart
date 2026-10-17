import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/budget/budget.dart';
import '../../core/widgets/figure_tiles.dart';
import '../../core/widgets/frosted_card.dart';
import '../../core/widgets/hive_widgets.dart';
import 'sprint_format.dart';
import 'widgets/burndown_chart.dart';
import '../../core/theme/app_type.dart';

/// Insights surface: summary figures, the burndown as a honey area, velocity
/// as glass vessels filled to what each sprint got done of what it committed,
/// the work per person and the scope-change log, all from the server-computed
/// [SprintReport]. Drawn like the report page (HIN-157): frosted cards on the
/// ambient background, the same figure tiles, the same vessels.
class SprintInsightsSurface extends StatelessWidget {
  const SprintInsightsSurface({
    super.key,
    required this.report,
    required this.loading,
    required this.error,
    required this.names,
    required this.onRetry,
    this.topInset = 0,
  });

  final SprintReport? report;
  final bool loading;
  final String? error;
  final Map<String, String> names;
  final VoidCallback onRetry;

  /// Room left clear above the first card, for a phone's app bar and its
  /// docked row, which the list scrolls up under.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    if (loading && report == null) {
      return const Center(child: HiveLoader());
    }
    if (error != null && report == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }
    final r = report;
    if (r == null) return const SizedBox.shrink();

    final gutter = context.pageGutter;
    return LayoutBuilder(
      builder: (context, room) => _cards(context, r, names, gutter, room),
    );
  }

  /// The cards, side by side once the surface itself is wide enough — the
  /// screen is wider than this surface wherever a rail or a sheet takes its
  /// share.
  Widget _cards(
    BuildContext context,
    SprintReport r,
    Map<String, String> names,
    double gutter,
    BoxConstraints room,
  ) {
    final wide = room.maxWidth >= Breakpoints.mediumMax;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        topInset,
        gutter,
        gutter + context.bottomGutter,
      ),
      children: [
        _summary(context, r.summary),
        const SizedBox(height: 14),
        _twoUp(
          wide: wide,
          left: _BurndownCard(
            points: r.burndown,
            top: r.summary.committed.toDouble(),
            remaining: r.summary.remaining,
          ),
          right: _VelocityCard(points: r.velocity),
        ),
        const SizedBox(height: 14),
        _twoUp(
          wide: wide,
          left: _BreakdownCard(breakdown: r.breakdown, names: names),
          right: _ScopeCard(scope: r.scope),
        ),
      ],
    );
  }

  /// Two cards beside each other in the golden ratio, stacked while the
  /// surface is narrow. They stretch to the taller of the two, so a chart and
  /// the figures next to it share one baseline.
  Widget _twoUp({
    required bool wide,
    required Widget left,
    required Widget right,
  }) {
    if (!wide) {
      return Column(children: [left, const SizedBox(height: 14), right]);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 1618, child: left),
          const SizedBox(width: 14),
          Expanded(flex: 1000, child: right),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, SprintSummary s) => FigureTiles(
    tiles: [
      (
        icon: LucideIcons.circleDot,
        label: context.t('sprint.committed'),
        value: '${s.committed}',
        note: context.t('sprint.storyPoints'),
        valueColor: null,
      ),
      (
        icon: LucideIcons.circleCheck,
        label: context.t('sprint.completed'),
        value: '${s.completed}',
        note: context.t(
          'sprint.percentOfCommitment',
          variables: {
            'percent':
                '${s.committed == 0 ? 0 : (s.completed / s.committed * 100).round()}',
          },
        ),
        valueColor: AppColors.successInk,
      ),
      (
        icon: LucideIcons.flame,
        label: context.t('sprint.remaining'),
        value: '${s.remaining}',
        note: context.t('sprint.pointsWord'),
        valueColor: null,
      ),
      (
        icon: LucideIcons.gauge,
        label: context.t('sprint.avgVelocity'),
        value: '${s.avgVelocity}',
        note: context.t('sprint.lastSprints'),
        valueColor: null,
      ),
    ],
  );
}

Widget _quiet(BuildContext context, String key) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 18),
  child: Text(
    context.t(key),
    style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
  ),
);

Widget _trailing(String text) => Text(
  text,
  style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
);

class _BurndownCard extends StatelessWidget {
  const _BurndownCard({
    required this.points,
    required this.top,
    required this.remaining,
  });

  final List<BurndownPoint> points;
  final double top;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final left = context.t(
      'sprint.ptsRemaining',
      variables: {'points': '$remaining'},
    );
    return FrostedCard(
      title: context.t('sprint.burndown'),
      trailing: _trailing(left),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (points.isEmpty)
            SizedBox(
              height: 200,
              child: Center(child: _quiet(context, 'sprint.noBurndown')),
            )
          else
            Semantics(
              label: '${context.t('sprint.burndown')}: $left',
              excludeSemantics: true,
              child: BurndownChart(points: points, top: top),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _legend(
                context.t('sprint.actual'),
                HoneyGlass.liquid(BudgetLevel.within)[2],
                false,
              ),
              _legend(context.t('sprint.guideline'), AppColors.inkFaint, true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color, bool dashed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 2,
          child: dashed
              ? CustomPaint(painter: _DashLegendPainter(color))
              : ColoredBox(color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
        ),
      ],
    );
  }
}

class _DashLegendPainter extends CustomPainter {
  _DashLegendPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 4).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashLegendPainter old) => old.color != color;
}

/// Each completed sprint a vessel, filled to what it got done of what it
/// committed, the figure over it reading done of committed.
class _VelocityCard extends StatelessWidget {
  const _VelocityCard({required this.points});

  final List<VelocityPoint> points;

  @override
  Widget build(BuildContext context) {
    final committed = {for (final v in points) _label(v): v.committed};
    return FrostedCard(
      title: context.t('sprint.velocity'),
      trailing: _trailing(context.t('sprint.doneOfCommitted')),
      child: points.isEmpty
          ? _quiet(context, 'sprint.noVelocity')
          : LiquidColumns(
              items: [
                for (final v in points)
                  (
                    label: _label(v),
                    value: v.completed,
                    color: v.completed >= v.committed
                        ? AppColors.success
                        : AppColors.accent,
                  ),
              ],
              limitOf: (item) => committed[item.label] ?? 0,
              height: 150,
            ),
    );
  }

  String _label(VelocityPoint v) {
    final m = RegExp(r'(\d+)').allMatches(v.name).lastOrNull;
    return m != null ? 'S${m.group(1)}' : v.name;
  }
}

/// Points done of points held, per person, as tubes in each person's hue.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.breakdown, required this.names});

  final List<AssigneeLoad> breakdown;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    String nameOf(AssigneeLoad a) => a.userId.isEmpty
        ? context.t('sprint.unassigned')
        : (names[a.userId] ?? a.userId);
    final totals = {for (final a in breakdown) nameOf(a): a.total};
    final points = context.t('sprint.pointsWord');
    return FrostedCard(
      title: context.t('sprint.workBreakdown'),
      child: breakdown.isEmpty
          ? _quiet(context, 'sprint.noBreakdown')
          : LiquidRows(
              items: [
                for (final a in breakdown)
                  (
                    label: nameOf(a),
                    value: a.done,
                    color: a.userId.isEmpty
                        ? AppColors.inkFaint
                        : hiveHueColor(nameOf(a)),
                  ),
              ],
              limitOf: (item) => totals[item.label] ?? 0,
              figure: (item) =>
                  '${item.value}/${totals[item.label] ?? 0} $points',
            ),
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.scope});

  final List<SprintScopeChange> scope;

  @override
  Widget build(BuildContext context) {
    final net = scope.fold<int>(0, (s, c) => s + c.delta);
    return FrostedCard(
      title: context.t('sprint.scopeChanges'),
      child: scope.isEmpty
          ? _quiet(context, 'sprint.noScope')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in scope)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: MediaQuery.textScalerOf(context).scale(52),
                          child: Text(
                            c.date != null ? shortDate(c.date!) : '—',
                            style: TextStyle(
                              fontSize: AppType.caption,
                              color: AppColors.inkSoft,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: MediaQuery.textScalerOf(context).scale(40),
                          child: Text(
                            '${c.delta > 0 ? '+' : ''}${c.delta}',
                            style: TextStyle(
                              fontSize: AppType.label,
                              fontWeight: FontWeight.w700,
                              // Added scope is more work; removed is less.
                              color: c.delta > 0
                                  ? AppColors.dangerInkOnGlass
                                  : AppColors.successInk,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            c.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.label,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  context.t(
                    'sprint.netScope',
                    variables: {'delta': '${net > 0 ? '+' : ''}$net'},
                  ),
                  style: TextStyle(
                    fontSize: AppType.label,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
    );
  }
}
