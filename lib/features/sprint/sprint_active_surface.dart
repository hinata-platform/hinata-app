import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../board/board_filter.dart';
import 'widgets/glass_sprint_header.dart';

/// Active-sprint surface: the Liquid-Glass sprint header above a sprint-scoped
/// Kanban board (To Do → In Progress → In Review → Done, WIP limits, drag).
class SprintActiveSurface extends StatelessWidget {
  const SprintActiveSurface({
    super.key,
    required this.sprint,
    required this.columns,
    required this.issues,
    required this.filter,
    required this.onOpenIssue,
    required this.onMoveState,
  });

  final Sprint sprint;
  final List<BoardColumnView> columns;
  final List<Issue> issues;
  final BoardFilter filter;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue, String) onMoveState;

  bool _isBacklogColumn(BoardColumnView c) =>
      c.name.trim().toLowerCase() == 'backlog' ||
      c.states.any((s) => s.toUpperCase() == 'BACKLOG');

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    final boardColumns =
        columns.where((c) => !_isBacklogColumn(c)).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
          child: GlassSprintHeader(sprint: sprint),
        ),
        Expanded(
          child: boardColumns.isEmpty
              ? Center(
                  child: Text(
                    context.t('board.empty'),
                    style: TextStyle(color: AppColors.inkSoft),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    0,
                    gutter,
                    gutter + context.bottomGutter,
                  ),
                  itemCount: boardColumns.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final column = boardColumns[index];
                    final colIssues = issues
                        .where((i) =>
                            column.states.contains(i.state) && filter.matches(i))
                        .toList();
                    return _SprintColumn(
                      column: column,
                      issues: colIssues,
                      onAccept: (issue) => onMoveState(
                        issue,
                        column.states.isNotEmpty ? column.states.first : issue.state,
                      ),
                      onOpenIssue: onOpenIssue,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SprintColumn extends StatelessWidget {
  const _SprintColumn({
    required this.column,
    required this.issues,
    required this.onAccept,
    required this.onOpenIssue,
  });

  final BoardColumnView column;
  final List<Issue> issues;
  final void Function(Issue) onAccept;
  final void Function(Issue) onOpenIssue;

  @override
  Widget build(BuildContext context) {
    final overWip = column.wipLimit != null && issues.length > column.wipLimit!;
    final dotColor = AppColors.stateColor(
      column.states.isNotEmpty ? column.states.first : column.name,
    );
    final countLabel = column.wipLimit != null
        ? '${issues.length}/${column.wipLimit}'
        : '${issues.length}';

    return SizedBox(
      width: 300,
      child: DragTarget<Issue>(
        onWillAcceptWithDetails: (d) => !column.states.contains(d.data.state),
        onAcceptWithDetails: (d) => onAccept(d.data),
        builder: (context, candidate, rejected) {
          final dropping = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dropping ? AppColors.accentSoft : AppColors.canvas2,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(
                color: dropping ? AppColors.accentLine : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          column.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(
                          color: overWip
                              ? AppColors.dangerSoft
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: overWip
                                ? AppColors.danger.withValues(alpha: 0.3)
                                : AppColors.hairline,
                          ),
                        ),
                        child: Text(
                          countLabel,
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color:
                                overWip ? AppColors.danger : AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: issues.isEmpty
                      ? const SizedBox(height: 8)
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          itemCount: issues.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 9),
                          itemBuilder: (context, index) {
                            final issue = issues[index];
                            final card = _SprintCard(issue: issue);
                            return Draggable<Issue>(
                              data: issue,
                              dragAnchorStrategy: childDragAnchorStrategy,
                              maxSimultaneousDrags: 1,
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(width: 276, child: card),
                              ),
                              childWhenDragging:
                                  Opacity(opacity: 0.35, child: card),
                              child: _SprintCard(
                                issue: issue,
                                onOpen: () => onOpenIssue(issue),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SprintCard extends StatelessWidget {
  const _SprintCard({required this.issue, this.onOpen});

  final Issue issue;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.stateColor(issue.state.toUpperCase());
    final due = dueLabel(issue.dueDate);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D191637),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 2, color: accent),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TypeGlyph(type: issue.type, size: 18),
                        const SizedBox(width: 8),
                        IdMono(issue.readableId),
                        const Spacer(),
                        PriorityFlag(priority: issue.priority),
                        const SizedBox(width: 8),
                        _PointsPill(points: issue.storyPoints),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      issue.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        if (due != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 13,
                                color: due.late
                                    ? AppColors.danger
                                    : AppColors.inkFaint,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                due.text,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMono,
                                  fontSize: 11,
                                  color: due.late
                                      ? AppColors.danger
                                      : AppColors.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        const Spacer(),
                        if (issue.assigneeId != null)
                          HiveAvatar(name: issue.assigneeId!, size: 24),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points});

  final int? points;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        points == null ? '—' : '$points',
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: points == null ? AppColors.inkFaint : AppColors.ink,
        ),
      ),
    );
  }
}
