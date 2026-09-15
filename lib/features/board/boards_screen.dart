import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/events/board_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'board_links.dart';
import 'board_manage_menu.dart';
import 'create_board_dialog.dart';
import 'load_when_shown.dart';

// ─────────────────────────── BoardScreen ──────────────────────────────────
// Shown at /board — lists all boards across projects; can filter by project.
// Tapping a board card opens it at /board/:id, on top of this list.

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with LoadWhenShown<BoardScreen> {
  List<AgileBoard> _boards = const [];
  List<Project> _projects = const [];
  List<Team> _teams = const [];
  String? _projectFilter;
  bool _loading = true;
  String? _error;

  /// Re-fetch when the set of boards changes anywhere in the app.
  ///
  /// Including from this very screen: creating a board opens it on top of this
  /// list, so the list is still mounted and behind — and without this it was
  /// still showing the boards from before the one that had just been made.
  StreamSubscription<void>? _boardSub;

  /// Owner / project-lead / team-lead / platform-admin may manage a board.
  bool _canManageBoard(AgileBoard board) {
    final me = context.read<AuthBloc>().state.user;
    if (me == null) return false;
    if (me.isAdmin || board.ownerId == me.id) return true;
    for (final pid in board.projectIds) {
      final project = _projects.where((p) => p.id == pid).firstOrNull;
      if (project != null && project.leadIds.contains(me.id)) return true;
      final teamLead = _teams.any(
        (t) =>
            t.projectIds.contains(pid) &&
            (t.membershipOf(me.id)?.isAdmin ?? false),
      );
      if (teamLead) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _boardSub = BoardEvents.instance.changes.listen((_) => markStale());
  }

  /// Read once the list is on screen, see [LoadWhenShown].
  @override
  Future<void> loadShown() => _load();

  @override
  void dispose() {
    _boardSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        context.read<ProjectRepository>().projects(),
        context.read<BoardRepository>().boards(projectId: _projectFilter),
        context.read<TeamRepository>().teams(),
      ]);
      _projects = results[0] as List<Project>;
      _boards = results[1] as List<AgileBoard>;
      _teams = results[2] as List<Team>;
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
      showGlassToast(
        context,
        context.t('board.needsProject'),
        kind: GlassToastKind.warning,
      );
      return;
    }
    final created = await showCreateBoardDialog(
      context,
      projects: _projects,
      initialProjectId: _projectFilter,
    );
    if (created != null && mounted) {
      context.go(boardLocation(created.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _boards.isEmpty && _error == null) {
      return const Center(child: HiveLoader());
    }
    if (_error != null && _boards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            16 + context.topGutter,
            context.pageGutter,
            8,
          ),
          sliver: SliverToBoxAdapter(
            child: _BoardsListHeader(
              title: context.t('board.title'),
              filter: _projects.isEmpty
                  ? null
                  : _ProjectFilterChip(
                      projects: _projects,
                      selected: _projectFilter,
                      onChanged: (id) {
                        _projectFilter = id;
                        _load();
                      },
                    ),
              onCreate: _showCreate,
            ),
          ),
        ),
        if (_boards.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.pageGutter,
                vertical: 24,
              ),
              child: Center(
                child: HiveEmptyState(
                  title: context.t('board.title'),
                  message: context.t('board.empty'),
                  action: FilledButton.icon(
                    onPressed: _showCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: const Color(0xFF2A2410),
                    ),
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(context.t('board.newBoard')),
                  ),
                ),
              ),
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, room) => SliverPadding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                context.pageGutter,
                context.pageGutter,
                context.pageGutter + context.bottomGutter,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: context.gridColumns(
                    minTileWidth: 280,
                    width: room.crossAxisExtent,
                  ),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 150,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _BoardListCard(
                    board: _boards[index],
                    index: index,
                    projects: _projects,
                    canManage: _canManageBoard(_boards[index]),
                  ),
                  childCount: _boards.length,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Header for the boards-list screen.
///
/// On compact (phone) layouts the title gets a full-width row of its own and the
/// project filter + create button wrap onto a second row, so the title is never
/// squeezed to an ellipsis. On wider layouts everything sits inline.
class _BoardsListHeader extends StatelessWidget {
  const _BoardsListHeader({
    required this.title,
    required this.filter,
    required this.onCreate,
  });

  final String title;
  final Widget? filter;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final createButton = FilledButton.icon(
      onPressed: onCreate,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF2A2410),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      icon: const Icon(LucideIcons.plus, size: 18),
      label: Text(context.t('board.newBoard')),
    );

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleText,
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (filter != null)
                Flexible(child: filter!)
              else
                const SizedBox.shrink(),
              const SizedBox(width: 8),
              createButton,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleText),
        if (filter != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: filter!,
          ),
        createButton,
      ],
    );
  }
}

// ─────────────────────────── Board list card ──────────────────────────────

class _BoardListCard extends StatelessWidget {
  const _BoardListCard({
    required this.board,
    required this.index,
    required this.projects,
    required this.canManage,
  });

  final AgileBoard board;
  final int index;
  final List<Project> projects;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final projectNames = board.projectIds
        .map(
          (id) => projects.firstWhere(
            (p) => p.id == id,
            orElse: () => Project(id: id, key: id, name: id),
          ),
        )
        .map((p) => p.name)
        .join(', ');

    return SoftCard(
      color: AppColors.pastelFor(index),
      onTap: () => context.go(boardLocation(board.id)),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      board.isScrum ? LucideIcons.zap : LucideIcons.columns3,
                      size: 13,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.t(
                        board.isScrum ? 'board.typeScrum' : 'board.typeKanban',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (canManage)
                Builder(
                  builder: (btnContext) => IconButton(
                    tooltip: context.t('board.manageBoard'),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    // No onChanged: renaming, re-scoping and deleting all
                    // broadcast on BoardEvents, which the list this card sits
                    // in listens to.
                    onPressed: () =>
                        openBoardManageMenu(btnContext, board: board),
                    icon: Icon(
                      LucideIcons.ellipsisVertical,
                      size: 16,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              board.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (projectNames.isNotEmpty)
            Text(
              projectNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Icon(
              forwardArrow(context),
              size: 14,
              color: AppColors.inkSoft,
            ),
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
        ? projects
              .firstWhere((p) => p.id == selected, orElse: () => projects.first)
              .name
        : context.t('board.allProjects');

    return GlassPopupMenu<String?>(
      value: selected,
      onSelected: onChanged,
      items: [
        GlassMenuItem(value: null, label: context.t('board.allProjects')),
        ...projects.map((p) => GlassMenuItem(value: p.id, label: p.name)),
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
