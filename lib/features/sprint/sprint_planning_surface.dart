import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_bulk_bar.dart';
import '../../core/widgets/hive_widgets.dart';
import '../search/search_tokens.dart';
import '../board/board_card_list.dart' show BoardReadOn;
import '../board/issue_quick_create.dart';
import 'planning/sprint_planning_cubit.dart';
import 'sprint_format.dart';
import 'widgets/plan_row.dart';
import 'widgets/sprint_widgets.dart';

/// Planning (backlog) surface: stacked sprint containers above the paginated
/// product backlog. Drag issues between any container; multi-select + bulk
/// move; per-row story-point estimate; start / complete a sprint.
///
/// Everything here comes from the server already searched and filtered. A
/// sprint shows its cards a page at a time and counts its head over all of
/// them, loaded or not. Its rows are built as they scroll into view, and it
/// reads its next page by itself once the end of its rows comes within reach.
class SprintPlanningSurface extends StatelessWidget {
  const SprintPlanningSurface({
    super.key,
    required this.planning,
    required this.sprints,
    required this.activeSprintId,
    required this.backlogPageSize,
    required this.names,
    this.pronouns = const {},
    required this.avatars,
    required this.selected,
    required this.onPage,
    required this.onLoadMore,
    required this.onToggleSelect,
    required this.onClearSelection,
    required this.onOpenIssue,
    required this.onEstimate,
    required this.onMoveToSprint,
    required this.onBulkMove,
    required this.quickCreateSeed,
    required this.onCreated,
    required this.onStartSprint,
    required this.onCompleteSprint,
    this.topInset = 0,
  });

  /// The sprints' cards and heads, and the backlog page on screen.
  final SprintPlanningState planning;

  /// The sprints in the order they stack: the one the board runs first.
  final List<Sprint> sprints;
  final String? activeSprintId;
  final int backlogPageSize;

  /// Display name / avatar URL per user id, so a row can show *who* an issue is
  /// assigned to. Without them a row only has the raw assignee id, which is not
  /// something to render at a person.
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> pronouns;
  final Set<String> selected;
  final ValueChanged<int> onPage;

  /// Reads the next page of the sprint with the given id.
  final ValueChanged<String> onLoadMore;
  final ValueChanged<String> onToggleSelect;
  final VoidCallback onClearSelection;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue) onEstimate;
  final void Function(Issue, String?) onMoveToSprint;
  final void Function(String?) onBulkMove;

  /// Seeds the inline composer of a section: the sprint it belongs to (null for
  /// the backlog) decides what a ticket written there inherits.
  final IssueQuickCreateSeed Function(String? sprintId) quickCreateSeed;

  /// Fired once a composer created an issue, so the surface reloads.
  final ValueChanged<Issue> onCreated;
  final void Function(Sprint) onStartSprint;
  final void Function(Sprint) onCompleteSprint;

  /// Room left clear above the first sprint. On a phone the app bar and its
  /// docked row float over the top of the list, which scrolls up under them.
  final double topInset;

  int get _backlogPages => planning.backlogTotal == 0
      ? 1
      : (planning.backlogTotal + backlogPageSize - 1) ~/ backlogPageSize;

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    return Stack(
      children: [
        CustomScrollView(
          // Rows are built this far ahead of the screen, so a sprint reads on
          // before its last row comes into view.
          scrollCacheExtent: const ScrollCacheExtent.pixels(BoardReadOn.reach),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                topInset,
                gutter,
                gutter + context.bottomGutter + (selected.isNotEmpty ? 72 : 0),
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  for (final s in sprints) ...[
                    _SprintGroup(
                      key: ValueKey(s.id),
                      sprint: s,
                      isActive: s.id == activeSprintId,
                      container: planning.containerOf(s.id),
                      names: names,
                      avatars: avatars,
                      pronouns: pronouns,
                      selected: selected,
                      onToggleSelect: onToggleSelect,
                      onOpenIssue: onOpenIssue,
                      onEstimate: onEstimate,
                      onAccept: (issue) => onMoveToSprint(issue, s.id),
                      // A read of the whole planning answers for every sprint
                      // anew, so none reads on meanwhile.
                      onLoadMore: planning.refreshing
                          ? null
                          : () => onLoadMore(s.id),
                      quickCreate: quickCreateSeed(s.id),
                      onCreated: onCreated,
                      action: s.id == activeSprintId
                          ? GhostButton(
                              label: context.t('sprint.completeSprint'),
                              icon: LucideIcons.flag,
                              onPressed: () => onCompleteSprint(s),
                            )
                          : PrimaryButton(
                              label: context.t('sprint.startSprint'),
                              icon: LucideIcons.play,
                              // An empty sprint has nothing to start. A
                              // narrowed planning may not show all a sprint
                              // holds, so there the board counts the whole
                              // sprint before it starts it.
                              onPressed:
                                  planning.containerOf(s.id).total == 0 &&
                                      !planning.narrowed
                                  ? null
                                  : () => onStartSprint(s),
                            ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                  SliverToBoxAdapter(
                    child: _BacklogGroup(
                      issues: planning.backlog,
                      names: names,
                      avatars: avatars,
                      pronouns: pronouns,
                      total: planning.backlogTotal,
                      page: planning.backlogPage,
                      pages: _backlogPages,
                      pageSize: backlogPageSize,
                      // The search the backlog on screen was read with, not
                      // the letters typed since.
                      query: planning.query.text.trim(),
                      selected: selected,
                      onToggleSelect: onToggleSelect,
                      onOpenIssue: onOpenIssue,
                      onEstimate: onEstimate,
                      onAccept: (issue) => onMoveToSprint(issue, null),
                      quickCreate: quickCreateSeed(null),
                      onCreated: onCreated,
                      onPage: onPage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (selected.isNotEmpty)
          Positioned(
            left: gutter,
            right: gutter,
            bottom: context.bottomGutter + 12,
            child: Center(
              child: _BulkBar(
                count: selected.length,
                sprints: sprints,
                onMove: onBulkMove,
                onClose: onClearSelection,
              ),
            ),
          ),
      ],
    );
  }
}

/// A collapsible sprint container that takes the issues dropped on it.
///
/// Laid out as slivers, so a sprint's rows are built as they scroll into view
/// rather than all at once. It stays one drop target however many rows it has:
/// every part of it takes a card, and the whole group lights up while a card is
/// held over any part of it.
class _SprintGroup extends StatefulWidget {
  const _SprintGroup({
    super.key,
    required this.sprint,
    required this.isActive,
    required this.container,
    required this.names,
    required this.avatars,
    this.pronouns = const {},
    required this.selected,
    required this.onToggleSelect,
    required this.onOpenIssue,
    required this.onEstimate,
    required this.onAccept,
    this.onLoadMore,
    required this.quickCreate,
    required this.onCreated,
    required this.action,
  });

  final Sprint sprint;
  final bool isActive;

  /// The sprint's cards loaded so far, and its head over all of them.
  final SprintContainer container;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> pronouns;
  final Set<String> selected;
  final ValueChanged<String> onToggleSelect;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue) onEstimate;
  final void Function(Issue) onAccept;

  /// Reads the sprint's next page. Null while the whole planning is read
  /// again.
  final VoidCallback? onLoadMore;
  final IssueQuickCreateSeed quickCreate;
  final ValueChanged<Issue> onCreated;
  final Widget action;

  @override
  State<_SprintGroup> createState() => _SprintGroupState();
}

class _SprintGroupState extends State<_SprintGroup> {
  bool _collapsed = false;

  /// How many parts of the group a card is held over right now.
  int _hovering = 0;

  bool _takes(Issue issue) => issue.sprintId != widget.sprint.id;

  bool _willAccept(DragTargetDetails<Issue> details) {
    final taken = _takes(details.data);
    if (taken) setState(() => _hovering++);
    return taken;
  }

  void _left(Issue? issue) {
    if (issue == null || !_takes(issue)) return;
    setState(() => _hovering = math.max(0, _hovering - 1));
  }

  void _accept(DragTargetDetails<Issue> details) {
    setState(() => _hovering = 0);
    widget.onAccept(details.data);
  }

  /// [child] as a part of the group that takes a card.
  Widget _part(Widget child) => DragTarget<Issue>(
    onWillAcceptWithDetails: _willAccept,
    onLeave: _left,
    onAcceptWithDetails: _accept,
    builder: (context, _, _) => child,
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.sprint;
    final container = widget.container;
    final dropping = _hovering > 0;
    final readOn = container.hasMore ? widget.onLoadMore : null;
    return TweenAnimationBuilder<Decoration>(
      tween: DecorationTween(
        end: BoxDecoration(
          color: dropping ? AppColors.accentSoft : AppColors.canvas2,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: dropping || widget.isActive
                ? AppColors.accentLine
                : AppColors.hairline,
            width: dropping ? 2 : 1,
          ),
        ),
      ),
      duration: const Duration(milliseconds: 160),
      builder: (context, decoration, group) =>
          DecoratedSliver(decoration: decoration, sliver: group!),
      child: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: _part(
              _SprintGroupHeader(
                sprint: s,
                isActive: widget.isActive,
                container: container,
                collapsed: _collapsed,
                onToggleCollapse: () =>
                    setState(() => _collapsed = !_collapsed),
                action: widget.action,
              ),
            ),
          ),
          if (!_collapsed) ...[
            if (container.items.isEmpty && !container.hasMore)
              SliverToBoxAdapter(
                child: _part(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _EmptyDropHint(text: context.t('sprint.dragHere')),
                  ),
                ),
              )
            else
              SliverList.builder(
                // After the rows stands what reads the sprint on, built once
                // the end of the rows comes within reach.
                itemCount: container.items.length + (readOn == null ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == container.items.length) {
                    return _part(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                        child: BoardReadOn(
                          count: container.items.length,
                          loading: container.loadingMore,
                          onReadOn: readOn!,
                        ),
                      ),
                    );
                  }
                  final issue = container.items[index];
                  return _part(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                      child: _DraggableRow(
                        issue: issue,
                        assigneeName: widget.names[issue.assigneeId],
                        assigneeAvatar: widget.avatars[issue.assigneeId],
                        assigneePronouns: widget.pronouns[issue.assigneeId],
                        selected: widget.selected.contains(issue.id),
                        onToggleSelect: () => widget.onToggleSelect(issue.id),
                        onOpen: () => widget.onOpenIssue(issue),
                        onEstimate: () => widget.onEstimate(issue),
                      ),
                    ),
                  );
                },
              ),
            SliverToBoxAdapter(
              child: _part(
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: IssueQuickCreate(
                    label: context.t('sprint.addIssue'),
                    seed: widget.quickCreate,
                    onCreated: widget.onCreated,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SprintGroupHeader extends StatelessWidget {
  const _SprintGroupHeader({
    required this.sprint,
    required this.isActive,
    required this.container,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.action,
  });

  final Sprint sprint;
  final bool isActive;
  final SprintContainer container;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final title = Row(
      children: [
        InkWell(
          onTap: onToggleCollapse,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 180),
              turns: collapsed ? -0.25 : 0,
              child: Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            sprint.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StateBadge(active: isActive),
        if ((sprint.startDate != null && sprint.endDate != null)) ...[
          const SizedBox(width: 8),
          Text(
            dateRange(sprint.startDate, sprint.endDate),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ],
    );

    final issuesLabel = Text(
      container.total == 1
          ? context.t('sprint.issueOne', variables: {'count': '1'})
          : context.t(
              'sprint.issuesMany',
              variables: {'count': '${container.total}'},
            ),
      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
    );
    // Over every card of the sprint, not only the ones loaded.
    final points = bucketSummary(container.summary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: compact
          // Phone: stacked — count + buckets, full-width capacity, full-width
          // action (mirrors sprint.css body[data-bp="phone"] .sg-meta).
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if ((sprint.goal ?? '').isNotEmpty) _goal(context),
                const SizedBox(height: 12),
                Row(
                  children: [
                    issuesLabel,
                    const SizedBox(width: 12),
                    PointBuckets(points: points),
                  ],
                ),
                const SizedBox(height: 10),
                CapacityBar(
                  points: points,
                  capacity: sprint.capacityPoints,
                  width: double.infinity,
                ),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: action),
              ],
            )
          // Desktop: a single right-aligned row, action pinned to the far right.
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if ((sprint.goal ?? '').isNotEmpty) _goal(context),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                issuesLabel,
                const SizedBox(width: 14),
                PointBuckets(points: points),
                const SizedBox(width: 14),
                CapacityBar(
                  points: points,
                  capacity: sprint.capacityPoints,
                  width: context.isExpanded ? 188 : 150,
                ),
                const SizedBox(width: 14),
                action,
              ],
            ),
    );
  }

  Widget _goal(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 2, 0, 0),
    child: Text(
      sprint.goal!,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
    ),
  );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? AppColors.accentSoft : AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? LucideIcons.zap : LucideIcons.clock,
            size: 12,
            color: active ? AppColors.accentStrong : AppColors.inkSoft,
          ),
          const SizedBox(width: 4),
          Text(
            context.t(active ? 'board.active' : 'sprint.planned'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _BacklogGroup extends StatefulWidget {
  const _BacklogGroup({
    required this.issues,
    required this.names,
    required this.avatars,
    this.pronouns = const {},
    required this.total,
    required this.page,
    required this.pages,
    required this.pageSize,
    required this.query,
    required this.selected,
    required this.onToggleSelect,
    required this.onOpenIssue,
    required this.onEstimate,
    required this.onAccept,
    required this.quickCreate,
    required this.onCreated,
    required this.onPage,
  });

  final List<Issue> issues;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> pronouns;
  final int total;
  final int page;
  final int pages;
  final int pageSize;
  final String query;
  final Set<String> selected;
  final ValueChanged<String> onToggleSelect;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue) onEstimate;
  final void Function(Issue) onAccept;
  final IssueQuickCreateSeed quickCreate;
  final ValueChanged<Issue> onCreated;
  final ValueChanged<int> onPage;

  @override
  State<_BacklogGroup> createState() => _BacklogGroupState();
}

class _BacklogGroupState extends State<_BacklogGroup> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Issue>(
      onWillAcceptWithDetails: (d) => d.data.sprintId != null,
      onAcceptWithDetails: (d) => widget.onAccept(d.data),
      builder: (context, candidate, rejected) {
        final dropping = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: dropping ? AppColors.accentSoft : AppColors.canvas2,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: dropping ? AppColors.accentLine : AppColors.hairline,
              width: dropping ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 10),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _collapsed = !_collapsed),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: AnimatedRotation(
                          duration: const Duration(milliseconds: 180),
                          turns: _collapsed ? -0.25 : 0,
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 18,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.t('sprint.backlog'),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Text(
                        '${widget.total}',
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_collapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: IssueQuickCreate(
                          label: context.t('sprint.addBacklogItem'),
                          seed: widget.quickCreate,
                          onCreated: widget.onCreated,
                        ),
                      ),
                      if (widget.issues.isEmpty)
                        _EmptyDropHint(
                          text: widget.query.isEmpty
                              ? context.t('sprint.backlogEmpty')
                              : context.t(
                                  'sprint.noMatches',
                                  variables: {'query': widget.query},
                                ),
                        )
                      else
                        for (final issue in widget.issues)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: _DraggableRow(
                              issue: issue,
                              assigneeName: widget.names[issue.assigneeId],
                              assigneeAvatar: widget.avatars[issue.assigneeId],
                              assigneePronouns:
                                  widget.pronouns[issue.assigneeId],
                              selected: widget.selected.contains(issue.id),
                              onToggleSelect: () =>
                                  widget.onToggleSelect(issue.id),
                              onOpen: () => widget.onOpenIssue(issue),
                              onEstimate: () => widget.onEstimate(issue),
                            ),
                          ),
                      if (widget.pages > 1)
                        _Pager(
                          page: widget.page,
                          pages: widget.pages,
                          total: widget.total,
                          pageSize: widget.pageSize,
                          onPage: widget.onPage,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Wraps a [PlanRow] in a [Draggable] so it can be dragged between containers.
class _DraggableRow extends StatelessWidget {
  const _DraggableRow({
    required this.issue,
    required this.assigneeName,
    required this.assigneeAvatar,
    this.assigneePronouns,
    required this.selected,
    required this.onToggleSelect,
    required this.onOpen,
    required this.onEstimate,
  });

  final Issue issue;
  final String? assigneeName;
  final String? assigneeAvatar;
  final String? assigneePronouns;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onOpen;
  final VoidCallback onEstimate;

  @override
  Widget build(BuildContext context) {
    final row = PlanRow(
      issue: issue,
      assigneeName: assigneeName,
      assigneeAvatar: assigneeAvatar,
      assigneePronouns: assigneePronouns,
      selected: selected,
      onToggleSelect: onToggleSelect,
      onOpen: onOpen,
      onEstimate: onEstimate,
    );
    // Touch platforms get no drag — it fights the scroll gesture. Sprint
    // assignment happens via multi-select + bulk move or the detail sheet.
    final platform = Theme.of(context).platform;
    final isTouch =
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.fuchsia;
    if (isTouch) return row;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Draggable<Issue>(
          data: issue,
          dragAnchorStrategy: childDragAnchorStrategy,
          maxSimultaneousDrags: 1,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: width, child: row),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          child: row,
        );
      },
    );
  }
}

class _EmptyDropHint extends StatelessWidget {
  const _EmptyDropHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline, style: BorderStyle.solid),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });

  final int page;
  final int pages;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    // Window of up to 5 page buttons around the current page.
    final start = (page - 2).clamp(0, (pages - 5).clamp(0, pages));
    final visible = [
      for (var i = start; i < (start + 5).clamp(0, pages); i++) i,
    ];
    final from = page * pageSize + 1;
    final to = ((page + 1) * pageSize).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pageBtn(
            child: Icon(backChevron(context), size: 18),
            enabled: page > 0,
            onTap: () => onPage(page - 1),
          ),
          const SizedBox(width: 6),
          for (final i in visible) ...[
            _pageBtn(
              child: Text('${i + 1}'),
              selected: i == page,
              enabled: true,
              onTap: () => onPage(i),
            ),
            const SizedBox(width: 6),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$from–$to ${context.t('common.of')} $total',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.inkSoft,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _pageBtn(
            child: Icon(forwardChevron(context), size: 18),
            enabled: page < pages - 1,
            onTap: () => onPage(page + 1),
          ),
        ],
      ),
    );
  }

  Widget _pageBtn({
    required Widget child,
    required bool enabled,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: selected ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppColors.navy : AppColors.hairline,
                ),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.inkSoft,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: selected ? Colors.white : AppColors.inkSoft,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.sprints,
    required this.onMove,
    required this.onClose,
  });

  final int count;
  final List<Sprint> sprints;
  final void Function(String?) onMove;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    return GlassBulkBar(
      countLabel: context.t(
        'sprint.selectedCount',
        variables: {'count': '$count'},
      ),
      onClear: onClose,
      actions: [
        Container(
          decoration: BoxDecoration(
            color: tokens.field,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tokens.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              hint: Text(
                context.t('sprint.moveTo'),
                style: TextStyle(color: tokens.inkSoft, fontSize: 12.5),
              ),
              dropdownColor: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              isDense: true,
              iconEnabledColor: tokens.inkSoft,
              style: TextStyle(color: tokens.ink, fontSize: 12.5),
              items: [
                for (final s in sprints)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
                DropdownMenuItem(
                  value: '__backlog',
                  child: Text(context.t('sprint.backlog')),
                ),
              ],
              onChanged: (v) {
                if (v != null) onMove(v == '__backlog' ? null : v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
