import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../shell/page_chrome.dart';
import 'board_manage_menu.dart';

/// Lists all boards for a single project and allows creating new ones.
class ProjectBoardsScreen extends StatefulWidget {
  const ProjectBoardsScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  State<ProjectBoardsScreen> createState() => _ProjectBoardsScreenState();
}

typedef _BoardsData = ({List<AgileBoard> boards, bool canManageProject});

class _ProjectBoardsScreenState extends State<ProjectBoardsScreen> {
  late final FetchCubit<_BoardsData> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<_BoardsData>(() async {
      final repo = context.read<HivoraRepository>();
      final me = context.read<AuthBloc>().state.user;
      final results = await Future.wait([
        repo.boards(projectId: widget.projectId),
        repo.project(widget.projectId),
        repo.teams(),
      ]);
      final boards = results[0] as List<AgileBoard>;
      final project = results[1] as Project;
      final teams = results[2] as List<Team>;
      // Project/team leads (and platform admins) may manage every board of this
      // project; the board owner is handled per-card.
      final canManageProject =
          me != null &&
          (me.isAdmin ||
              project.leadIds.contains(me.id) ||
              teams.any(
                (t) =>
                    t.projectIds.contains(widget.projectId) &&
                    (t.membershipOf(me.id)?.isAdmin ?? false),
              ));
      return (boards: boards, canManageProject: canManageProject);
    })..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _showCreate() async {
    final repository = context.read<HivoraRepository>();
    final created = await WoltModalSheet.show<AgileBoard?>(
      context: context,
      pageListBuilder: (modalContext) => [
        WoltModalSheetPage(
          backgroundColor: AppColors.surface,
          hasTopBarLayer: false,
          child: RepositoryProvider.value(
            value: repository,
            child: _CreateBoardBody(
              projectId: widget.projectId,
              projectName: widget.projectName,
            ),
          ),
        ),
      ],
    );
    if (created != null) _cubit.load();
  }

  Future<void> _openBoardMenu(BuildContext anchor, AgileBoard board) =>
      openBoardManageMenu(anchor, board: board, onChanged: _cubit.load);

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AuthBloc>().state.user?.id;
    return PageChrome(
      title: widget.projectName.isNotEmpty
          ? widget.projectName
          : context.t('board.boards'),
      child: BlocProvider.value(
        value: _cubit,
        child: BlocBuilder<FetchCubit<_BoardsData>, FetchState<_BoardsData>>(
          builder: (context, state) {
            final boardList = state.data?.boards ?? const <AgileBoard>[];
            final canManageProject = state.data?.canManageProject ?? false;
            return RefreshIndicator(
              onRefresh: _cubit.load,
              child: CustomScrollView(
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.projectName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkSoft,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  context.t('board.boards'),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _showCreate,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: const Color(0xFF2A2410),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            icon: const Icon(LucideIcons.plus, size: 18),
                            label: Text(context.t('board.newBoard')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (state.isLoading && boardList.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: HiveLoader()),
                    )
                  else if (state.errorKey != null && boardList.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.t(state.errorKey!),
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _cubit.load,
                              child: Text(context.t('common.retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (boardList.isEmpty)
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
                            message: context.t('board.emptyProject'),
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
                    SliverPadding(
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
                          ),
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          mainAxisExtent: 140,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final board = boardList[index];
                          final canManage =
                              canManageProject ||
                              (myId != null && board.ownerId == myId);
                          return _BoardCard(
                            board: board,
                            index: index,
                            canManage: canManage,
                            onMenu: (anchor) => _openBoardMenu(anchor, board),
                          );
                        }, childCount: boardList.length),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.board,
    required this.index,
    required this.canManage,
    required this.onMenu,
  });

  final AgileBoard board;
  final int index;
  final bool canManage;
  final void Function(BuildContext anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.pastelFor(index),
      onTap: () => context.push('/boards/${board.id}'),
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
                    const Icon(
                      LucideIcons.squareKanban,
                      size: 13,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.t('board.boardLabel'),
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
              // Manage menu (rename / delete) — only for the board owner, project
              // leads, team leads or platform admins.
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
                    onPressed: () => onMenu(btnContext),
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
          Text(
            board.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Row(
            children: [
              PillChip(
                label: context.t(
                  'board.projects',
                  variables: {'count': '${board.projectIds.length}'},
                ),
                background: Colors.white.withValues(alpha: 0.5),
                foreground: AppColors.textSecondary,
              ),
              const Spacer(),
              Icon(LucideIcons.arrowRight, size: 14, color: AppColors.inkSoft),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateBoardBody extends StatefulWidget {
  const _CreateBoardBody({required this.projectId, required this.projectName});

  final String projectId;
  final String projectName;

  @override
  State<_CreateBoardBody> createState() => _CreateBoardBodyState();
}

class _CreateBoardBodyState extends State<_CreateBoardBody> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        32 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t('board.newBoard'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              context.t(
                'board.forProject',
                variables: {'project': widget.projectName},
              ),
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: context.t('board.name')),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? context.t('errors.required')
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
                textAlign: TextAlign.center,
              ),
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
                        strokeWidth: 2,
                        color: Color(0xFF2A2410),
                      ),
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
        [widget.projectId],
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
