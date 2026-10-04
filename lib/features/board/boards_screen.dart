import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/access/project_permissions.dart';
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
import '../../core/theme/glass_chrome.dart' show kOnAmber;
import '../../core/widgets/glass_filter_bar.dart'
    show GlassFilterChip, kGlassDockRow;
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import '../shell/page_chrome.dart';
import 'board_links.dart';
import 'board_list_cubit.dart';
import 'board_manage_menu.dart';
import 'create_board_dialog.dart';
import 'load_when_shown.dart';

// ─────────────────────────── BoardScreen ──────────────────────────────────
// Shown at /board — lists all boards across projects; can filter by project.
// Tapping a board card opens it at /board/:id, on top of this list.

class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => BoardListCubit(
      boards: context.read<BoardRepository>(),
      projects: context.read<ProjectRepository>(),
      teams: context.read<TeamRepository>(),
    ),
    child: const _BoardList(),
  );
}

class _BoardList extends StatefulWidget {
  const _BoardList();

  @override
  State<_BoardList> createState() => _BoardListState();
}

class _BoardListState extends State<_BoardList> with LoadWhenShown<_BoardList> {
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

  /// The board's owner, a lead of one of its projects, or a Team-Admin of a
  /// team owning one of them may manage it. The platform admin role adds
  /// nothing: the server refuses it like anybody else's.
  bool _canManageBoard(AgileBoard board) {
    final me = context.read<AuthBloc>().state.user;
    if (me == null) return false;
    if (board.ownerId == me.id) return true;
    for (final pid in board.projectIds) {
      final project = _projects.where((p) => p.id == pid).firstOrNull;
      if (project != null && canManageProject(project, me, _teams)) {
        return true;
      }
      // A project the list did not return (an archived one) can still be owned
      // by one of my teams.
      if (project == null &&
          _teams.any(
            (t) =>
                t.projectIds.contains(pid) &&
                (t.membershipOf(me.id)?.isAdmin ?? false),
          )) {
        return true;
      }
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
      final list = context.read<BoardListCubit>();
      final results = await Future.wait([
        list.projects(),
        list.boards(projectId: _projectFilter),
        list.teams(),
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

    final compact = context.isCompact;
    final filter = _projects.isEmpty
        ? null
        : _ProjectFilterChip(
            projects: _projects,
            selected: _projectFilter,
            onChanged: (id) {
              _projectFilter = id;
              _load();
            },
          );
    // On a phone the title and the one page action ride in the glass app bar
    // and the project filter docks below them, in the bar's blur: two lines
    // of chrome, not a second title and a row of controls down the page. On a
    // wide window the page carries its own head, where the button can show
    // its name.
    return PageChrome(
      title: context.t('board.title'),
      actions: compact
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('board.newBoard'),
                primary: true,
                onTap: (_) => _showCreate(),
              ),
            ]
          : const [],
      bottom: compact && filter != null
          ? Padding(
              padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
              // The bar hands the reserved height down as a tight constraint;
              // the Align lets the pill come in under it.
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: filter,
              ),
            )
          : null,
      bottomHeight: compact && filter != null ? kGlassDockRow : 0,
      child: _scroller(context, compact: compact, filter: filter),
    );
  }

  Widget _scroller(
    BuildContext context, {
    required bool compact,
    required Widget? filter,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            (compact ? 8 : 24) + context.topGutter,
            context.pageGutter,
            compact ? 0 : 8,
          ),
          sliver: SliverToBoxAdapter(
            child: compact
                ? const SizedBox.shrink()
                : PageHead(
                    title: context.t('board.title'),
                    actions: [
                      ?filter,
                      PrimaryButton(
                        icon: LucideIcons.plus,
                        label: context.t('board.newBoard'),
                        onPressed: _showCreate,
                      ),
                    ],
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
                      foregroundColor: kOnAmber,
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

  /// A glass filter pill, the toolbar idiom of every list page: washed amber
  /// while it narrows the boards to one project, so a filtered list never
  /// passes for a short one.
  @override
  Widget build(BuildContext context) => GlassFilterChip<String?>(
    icon: LucideIcons.folder,
    label: context.t('board.allProjects'),
    value: selected,
    options: [
      (null, context.t('board.allProjects')),
      for (final p in projects) (p.id, p.name),
    ],
    onChanged: onChanged,
  );
}
