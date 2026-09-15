import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassProgressIndicator;

import '../../../core/i18n/i18n.dart';
import '../../../core/models/board_page_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../sprint_tokens.dart';

/// Story points of an issue (0 when unestimated).
int pointsOf(Issue issue) => issue.storyPoints ?? 0;

int sumPoints(Iterable<Issue> issues) =>
    issues.fold(0, (sum, i) => sum + pointsOf(i));

/// Workflow bucket used for the point-bucket pills and capacity bar. Done is
/// driven by the resolved flag; the rest is split heuristically by state name
/// so it works for any project workflow.
enum WorkBucket { todo, progress, done }

/// Story points by bucket.
typedef PointsByBucket = ({int todo, int progress, int done});

WorkBucket bucketOf(Issue issue) =>
    bucketOfState(issue.state, resolved: issue.resolved);

WorkBucket bucketOfState(String state, {required bool resolved}) {
  if (resolved) return WorkBucket.done;
  final s = state.toLowerCase();
  if (s.contains('progress') || s.contains('review') || s.contains('doing')) {
    return WorkBucket.progress;
  }
  return WorkBucket.todo;
}

PointsByBucket bucketPoints(Iterable<Issue> issues) => _addUp([
  for (final issue in issues)
    (bucket: bucketOf(issue), points: pointsOf(issue)),
]);

/// The same over a sprint's summary by state, which counts every card of the
/// sprint rather than the ones loaded.
PointsByBucket bucketSummary(Iterable<BoardStateSummary> summary) => _addUp([
  for (final row in summary)
    (
      bucket: bucketOfState(row.state, resolved: row.resolved),
      points: row.points,
    ),
]);

PointsByBucket _addUp(Iterable<({WorkBucket bucket, int points})> parts) {
  var todo = 0, progress = 0, done = 0;
  for (final part in parts) {
    switch (part.bucket) {
      case WorkBucket.todo:
        todo += part.points;
      case WorkBucket.progress:
        progress += part.points;
      case WorkBucket.done:
        done += part.points;
    }
  }
  return (todo: todo, progress: progress, done: done);
}

/// Three mono pills: Σ points in to-do / in-progress / done.
class PointBuckets extends StatelessWidget {
  const PointBuckets({super.key, required this.points});

  final PointsByBucket points;

  @override
  Widget build(BuildContext context) {
    final b = points;
    Widget pill(int v, Color c) => Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      alignment: Alignment.center,
      child: Text(
        '$v',
        style: const TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill(b.todo, SprintTokens.todo),
        const SizedBox(width: 6),
        pill(b.progress, SprintTokens.progress),
        const SizedBox(width: 6),
        pill(b.done, SprintTokens.done),
      ],
    );
  }
}

/// Capacity bar: how full the sprint is — committed story points against the
/// team's capacity, flagged red once it is over.
///
/// The fill is the package's [GlassProgressIndicator], so it carries the same
/// liquid-glass treatment (rounded track, lit fill) as the rest of the app's
/// chrome. The done/in-progress/to-do split lives in the [PointBuckets] pills
/// right next to it, so the bar answers one question and answers it clearly.
class CapacityBar extends StatelessWidget {
  const CapacityBar({
    super.key,
    required this.points,
    required this.capacity,
    this.width = 188,
  });

  final PointsByBucket points;
  final int? capacity;
  final double width;

  @override
  Widget build(BuildContext context) {
    final b = points;
    final committed = b.todo + b.progress + b.done;
    final cap = capacity ?? 0;
    final over = cap > 0 && committed > cap;
    // Over capacity fills the whole track (and turns red); the number above it
    // says by how much.
    final fill = cap <= 0 ? 0.0 : (committed / cap).clamp(0.0, 1.0);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                context.t('sprint.capacity'),
                style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$committed',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontWeight: FontWeight.w600,
                        color: over ? AppColors.danger : AppColors.ink,
                      ),
                    ),
                    TextSpan(
                      text: cap > 0 ? ' / $cap pts' : ' pts',
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
          // Without a capacity there is nothing to fill against, and a bar that
          // is always full says nothing — the points above stand on their own.
          if (cap > 0) ...[
            const SizedBox(height: 5),
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: fill),
              builder: (context, value, _) => GlassProgressIndicator.linear(
                value: value,
                height: 8,
                // The package defaults to a 200px minimum, which would blow the
                // desktop meta row apart; this bar owns its own width.
                minWidth: 0,
                color: over ? SprintTokens.over : SprintTokens.progress,
                // The package's default track is 15 % white — invisible on the
                // light sprint card.
                backgroundColor: AppColors.canvas2,
                semanticLabel: context.t('sprint.capacity'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
