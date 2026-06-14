import 'package:flutter/material.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../issues/issue_detail_sheet.dart';
import '../issues/issue_form.dart';
import '../shell/page_chrome.dart';

// ─────────────────────────── BoardScreen ──────────────────────────────────
// Shown at /board — lists all boards across projects; can filter by project.
// Tapping a board card navigates to /boards/:id.

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  List<AgileBoard> _boards = const [];
  List<Project> _projects = const [];
  String? _projectFilter;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<HivoraRepository>();
    try {
      final results = await Future.wait([
        repo.projects(),
        repo.boards(projectId: _projectFilter),
      ]);
      _projects = results[0] as List<Project>;
      _boards = results[1] as List<AgileBoard>;
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _showCreate() async {
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('board.needsProject'))));
      return;
    }
    final repo = context.read<HivoraRepository>();
    final created = await WoltModalSheet.show<AgileBoard?>(
      context: context,
      pageListBuilder: (modalContext) => [
        WoltModalSheetPage(
          backgroundColor: AppColors.surface,
          hasTopBarLayer: false,
          child: RepositoryProvider.value(
            value: repo,
            child: _CreateBoardBody(
              projects: _projects,
              initialProjectId: _projectFilter,
            ),
          ),
        ),
      ],
    );
    if (created != null) {
      if (mounted) context.push('/boards/${created.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _boards.isEmpty && _error == null) {
      return const Center(
          child: HiveLoader());
    }
    if (_error != null && _boards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.t(_error!),
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _load, child: Text(context.t('common.retry'))),
          ],
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(context.pageGutter,
              16 + context.topGutter, context.pageGutter, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t('board.title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_projects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ProjectFilterChip(
                      projects: _projects,
                      selected: _projectFilter,
                      onChanged: (id) {
                        _projectFilter = id;
                        _load();
                      },
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _showCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF2A2410),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(context.t('board.newBoard')),
                ),
              ],
            ),
          ),
        ),
        if (_boards.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.view_kanban_rounded,
                      size: 56, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Text(context.t('board.empty'),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _showCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: const Color(0xFF2A2410),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(context.t('board.newBoard')),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(context.pageGutter, context.pageGutter,
                context.pageGutter, context.pageGutter + context.bottomGutter),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: context.gridColumns(minTileWidth: 280),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 150,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _BoardListCard(
                  board: _boards[index],
                  index: index,
                  projects: _projects,
                ),
                childCount: _boards.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────── KanbanBoardScreen ────────────────────────────
// Shown at /boards/:id — the actual drag-and-drop kanban for one board.

class KanbanBoardScreen extends StatefulWidget {
  const KanbanBoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  State<KanbanBoardScreen> createState() => _KanbanBoardScreenState();
}

class _KanbanBoardScreenState extends State<KanbanBoardScreen> {
  String? _sprintId;
  BoardView? _view;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final view = await context
          .read<HivoraRepository>()
          .boardView(widget.boardId, sprintId: _sprintId);
      setState(() {
        _view = view;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _moveIssue(Issue issue, BoardColumnView column) async {
    if (column.states.contains(issue.state) || column.states.isEmpty) return;
    try {
      await context
          .read<HivoraRepository>()
          .updateIssue(issue.id, {'state': column.states.first});
      await _load();
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _addIssue(BoardColumnView column) async {
    final view = _view;
    if (view == null) return;
    final projectId =
        view.board.projectIds.isNotEmpty ? view.board.projectIds.first : null;
    final created = await showIssueForm(
      context,
      projectId: projectId,
      initialState: column.states.isNotEmpty ? column.states.first : null,
    );
    if (created != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _view == null) {
      return const Center(
          child: HiveLoader());
    }
    if (_error != null && _view == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.t(_error!),
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _load, child: Text(context.t('common.retry'))),
          ],
        ),
      );
    }
    final view = _view!;
    final activeSprint = _sprintId != null
        ? view.sprints.where((s) => s.id == _sprintId).firstOrNull
        : view.sprints.firstOrNull;
    // Back navigation is handled by the shell app bar (via PageChrome), which
    // also shows the board name as the title.
    return PageChrome(
      title: view.board.name,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(context.pageGutter,
              22 + context.topGutter, context.pageGutter, 8),
          child: PageHead(
            title: view.board.name,
            subtitle: context.t('board.agileBoard'),
          ),
        ),
        // sprint chip + sprint selector
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
          child: Row(
            children: [
              if (activeSprint != null)
                Flexible(child: _SprintChip(sprint: activeSprint)),
              const Spacer(),
              if (view.sprints.isNotEmpty)
                _SprintSelector(
                  sprints: view.sprints,
                  selected: _sprintId,
                  onChanged: (value) {
                    _sprintId = value;
                    _load();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(context.pageGutter, 0,
                context.pageGutter, context.pageGutter + context.bottomGutter),
            itemCount: view.columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final column = view.columns[index];
              return _BoardColumn(
                column: column,
                onAccept: (issue) => _moveIssue(issue, column),
                onAddIssue: () => _addIssue(column),
                onOpenIssue: (issue) => showIssueDetailSheet(
                  context,
                  issueId: issue.id,
                  onChanged: _load,
                ),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

// ─────────────────────────── Sprint chip & selector ───────────────────────

class _SprintChip extends StatelessWidget {
  const _SprintChip({required this.sprint});
  final Sprint sprint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 13, color: AppColors.accentStrong),
                SizedBox(width: 4),
                Text('Active',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentStrong)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sprint.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                if ((sprint.goal ?? '').isNotEmpty)
                  Text(sprint.goal!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SprintSelector extends StatelessWidget {
  const _SprintSelector({
    required this.sprints,
    required this.selected,
    required this.onChanged,
  });

  final List<Sprint> sprints;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? sprints.where((s) => s.id == selected).firstOrNull?.name ??
            context.t('board.allSprints')
        : context.t('board.allSprints');
    return PopupMenuButton<String?>(
      initialValue: selected,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 40),
      itemBuilder: (_) => [
        PopupMenuItem(value: null, child: Text(context.t('board.allSprints'))),
        for (final s in sprints)
          PopupMenuItem(value: s.id, child: Text(s.name)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_outlined, size: 15, color: AppColors.inkSoft),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded,
                size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Board list card ──────────────────────────────

class _BoardListCard extends StatelessWidget {
  const _BoardListCard(
      {required this.board, required this.index, required this.projects});

  final AgileBoard board;
  final int index;
  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final projectNames = board.projectIds
        .map((id) => projects.firstWhere((p) => p.id == id,
            orElse: () => Project(id: id, key: id, name: id)))
        .map((p) => p.name)
        .join(', ');

    return SoftCard(
      color: AppColors.pastelFor(index),
      onTap: () => context.push('/boards/${board.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.view_kanban_rounded,
                    size: 13, color: AppColors.navy),
                const SizedBox(width: 4),
                Text(
                  context.t('board.boardLabel'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: AppColors.navy),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              board.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (projectNames.isNotEmpty)
            Text(
              projectNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child:
                Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Project filter chip ──────────────────────────

class _ProjectFilterChip extends StatelessWidget {
  const _ProjectFilterChip({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? selected;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? projects.firstWhere((p) => p.id == selected,
                orElse: () => projects.first)
            .name
        : context.t('board.allProjects');

    return PopupMenuButton<String?>(
      initialValue: selected,
      onSelected: onChanged,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 36),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: null,
          child: Text(context.t('board.allProjects')),
        ),
        ...projects.map(
          (p) => PopupMenuItem(value: p.id, child: Text(p.name)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded,
                size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Create Board dialog body ─────────────────────

class _CreateBoardBody extends StatefulWidget {
  const _CreateBoardBody({required this.projects, this.initialProjectId});

  final List<Project> projects;
  final String? initialProjectId;

  @override
  State<_CreateBoardBody> createState() => _CreateBoardBodyState();
}

class _CreateBoardBodyState extends State<_CreateBoardBody> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late String _selectedProjectId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedProjectId =
        widget.initialProjectId ?? widget.projects.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 32 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t('board.newBoard'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration:
                  InputDecoration(labelText: context.t('board.name')),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? context.t('errors.required')
                      : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedProjectId,
              decoration:
                  InputDecoration(labelText: context.t('board.project')),
              items: widget.projects
                  .map((p) =>
                      DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedProjectId = value);
                }
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: const Color(0xFF2A2410),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: HiveLoader(
                          strokeWidth: 2, color: Color(0xFF2A2410)),
                    )
                  : Text(context.t('common.create')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final board = await context.read<HivoraRepository>().createBoard(
            _name.text.trim(),
            [_selectedProjectId],
          );
      if (mounted) Navigator.of(context).pop(board);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}

// ─────────────────────────── Kanban column ────────────────────────────────

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.column,
    required this.onAccept,
    required this.onAddIssue,
    required this.onOpenIssue,
  });

  final BoardColumnView column;
  final void Function(Issue) onAccept;
  final VoidCallback onAddIssue;
  final void Function(Issue) onOpenIssue;

  @override
  Widget build(BuildContext context) {
    final overWip =
        column.wipLimit != null && column.issues.length > column.wipLimit!;
    // Tint from the column's first workflow state, falling back to its display
    // name so the header dot still matches the theme when `states` is empty.
    // stateColor normalises case/separators, so either form resolves correctly.
    final dotColor = AppColors.stateColor(
        column.states.isNotEmpty ? column.states.first : column.name);
    final countLabel = column.wipLimit != null
        ? '${column.issues.length}/${column.wipLimit}'
        : '${column.issues.length}';

    return SizedBox(
      width: 300,
      child: DragTarget<Issue>(
        onAcceptWithDetails: (details) => onAccept(details.data),
        builder: (context, candidates, rejected) {
          final dropping = candidates.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dropping ? AppColors.accentSoft : AppColors.canvas2,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: dropping
                  ? Border.all(color: AppColors.accentLine, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
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
                            color: dotColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          column.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
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
                                  : AppColors.hairline),
                        ),
                        child: Text(
                          countLabel,
                          style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: overWip
                                  ? AppColors.danger
                                  : AppColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: column.issues.isEmpty
                      ? const SizedBox(height: 8)
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          itemCount: column.issues.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 9),
                          itemBuilder: (context, index) {
                            final issue = column.issues[index];
                            return Draggable<Issue>(
                              data: issue,
                              dragAnchorStrategy:
                                  childDragAnchorStrategy,
                              maxSimultaneousDrags: 1,
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: 276,
                                  child: _BoardCard(
                                      issue: issue, dragging: true),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: _BoardCard(issue: issue)),
                              child: _BoardCard(
                                  issue: issue,
                                  onOpen: () => onOpenIssue(issue)),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: DottedAddButton(
                    label: context.t('board.addIssue'),
                    onTap: onAddIssue,
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

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.issue, this.dragging = false, this.onOpen});

  final Issue issue;
  final bool dragging;
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
              offset: Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: dragging ? null : onOpen,
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
                          height: 1.4),
                    ),
                    if (issue.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final t in issue.tags.take(3)) LabelTag(t),
                        ],
                      ),
                    ],
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        if (issue.estimateMinutes != null &&
                            issue.estimateMinutes! > 0)
                          _MiniMeta(
                            icon: Icons.timelapse_rounded,
                            text: fmtDuration(issue.spentMinutes),
                          ),
                        if (due != null) ...[
                          if (issue.estimateMinutes != null)
                            const SizedBox(width: 10),
                          _MiniMeta(
                            icon: Icons.calendar_today_rounded,
                            text: due.text,
                            color: due.late ? AppColors.danger : null,
                          ),
                        ],
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

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.inkFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontFamily: AppTheme.fontMono, fontSize: 11, color: c)),
      ],
    );
  }
}

/// Dashed "Add issue" button used at the foot of board columns.
class DottedAddButton extends StatelessWidget {
  const DottedAddButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 15, color: AppColors.inkFaint),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkFaint)),
            ],
          ),
        ),
      ),
    );
  }
}
