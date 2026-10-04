import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/events/board_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_chrome.dart' show kOnAmber;
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart' show glassWoltSurface;
import 'board_edit_cubit.dart';
import 'board_links.dart';
import 'board_manage_menu.dart';
import 'load_when_shown.dart';
import 'project_boards_cubit.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/widgets/hive_widgets.dart' show forwardArrow;

/// Lists all boards for a single project and allows creating new ones.
class ProjectBoardsScreen extends StatelessWidget {
  const ProjectBoardsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => ProjectBoardsCubit(
      boards: context.read<BoardRepository>(),
      projects: context.read<ProjectRepository>(),
      teams: context.read<TeamRepository>(),
      projectId: projectId,
      me: () => context.read<AuthBloc>().state.user,
    ),
    child: _ProjectBoards(projectId: projectId),
  );
}

class _ProjectBoards extends StatefulWidget {
  const _ProjectBoards({required this.projectId});

  final String projectId;

  @override
  State<_ProjectBoards> createState() => _ProjectBoardsState();
}

class _ProjectBoardsState extends State<_ProjectBoards>
    with LoadWhenShown<_ProjectBoards> {
  late final ProjectBoardsCubit _cubit = context.read<ProjectBoardsCubit>();

  /// Re-fetch when the set of boards changes anywhere in the app — a board
  /// created or deleted from the overview belongs in this project's list too.
  StreamSubscription<void>? _boardSub;

  @override
  void initState() {
    super.initState();
    _boardSub = BoardEvents.instance.changes.listen((_) => markStale());
  }

  @override
  void dispose() {
    _boardSub?.cancel();
    super.dispose();
  }

  /// Read once the list is on screen, see [LoadWhenShown].
  @override
  Future<void> loadShown() => _cubit.load();

  Future<void> _showCreate() async {
    final boards = context.read<BoardRepository>();
    final projectName = _cubit.state.data?.projectName ?? '';
    await WoltModalSheet.show<AgileBoard?>(
      context: context,
      pageContentDecorator: glassWoltSurface,
      pageListBuilder: (modalContext) => [
        WoltModalSheetPage(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          hasTopBarLayer: false,
          child: BlocProvider(
            create: (_) => BoardEditCubit(boards),
            child: _CreateBoardBody(
              projectId: widget.projectId,
              projectName: projectName,
            ),
          ),
        ),
      ],
    );
    // Nothing to do with `created`: createBoard broadcasts on BoardEvents and
    // this screen reloads from that, whichever screen the board was made on.
  }

  // No onChanged: every board mutation broadcasts on BoardEvents, which this
  // screen already listens to. Passing both would fetch the list twice.
  Future<void> _openBoardMenu(BuildContext anchor, AgileBoard board) =>
      openBoardManageMenu(anchor, board: board);

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AuthBloc>().state.user?.id;
    return BlocBuilder<ProjectBoardsCubit, FetchState<ProjectBoardsData>>(
      bloc: _cubit,
      builder: (context, state) {
        final projectName = state.data?.projectName ?? '';
        final boardList = state.data?.boards ?? const <AgileBoard>[];
        final canManageProject = state.data?.canManageProject ?? false;
        return PageChrome(
          title: projectName.isNotEmpty
              ? projectName
              : context.t('board.boards'),
          child: RefreshIndicator(
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
                          // The project name already heads the shell bar via
                          // PageChrome — only the section title lives here.
                          child: Text(
                            context.t('board.boards'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _showCreate,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: kOnAmber,
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
                // Also before the first read: the list starts unread and only
                // reads once it is on screen.
                if (boardList.isEmpty &&
                    state.errorKey == null &&
                    (state.isLoading || !state.hasData))
                  const SliverFillRemaining(child: Center(child: HiveLoader()))
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
                            // Under this project's boards, so back returns here.
                            onOpen: () => context.go(
                              projectBoardLocation(widget.projectId, board.id),
                            ),
                            onMenu: (anchor) => _openBoardMenu(anchor, board),
                          );
                        }, childCount: boardList.length),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.board,
    required this.index,
    required this.canManage,
    required this.onOpen,
    required this.onMenu,
  });

  final AgileBoard board;
  final int index;
  final bool canManage;
  final VoidCallback onOpen;
  final void Function(BuildContext anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.pastelFor(index),
      onTap: onOpen,
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
              Icon(forwardArrow(context), size: 14, color: AppColors.inkSoft),
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

  /// Empty while the project has not been read yet.
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
            if (widget.projectName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                context.t(
                  'board.forProject',
                  variables: {'project': widget.projectName},
                ),
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: context.t('board.name')),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? context.t('errors.required')
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: AppColors.dangerInk),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: kOnAmber,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: HiveLoader(strokeWidth: 2, color: kOnAmber),
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
      final board = await context.read<BoardEditCubit>().create(
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
