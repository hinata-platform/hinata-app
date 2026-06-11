import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';

/// Agile board with drag & drop between workflow columns.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  List<AgileBoard> _boards = const [];
  String? _boardId;
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
    final repository = context.read<HivoraRepository>();
    try {
      _boards = await repository.boards();
      if (_boards.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _boardId ??= _boards.first.id;
      _view = await repository.boardView(_boardId!, sprintId: _sprintId);
      setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _view == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.navy));
    }
    if (_error != null && _view == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.t(_error!),
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(context.t('common.retry'))),
          ],
        ),
      );
    }
    if (_boards.isEmpty) {
      return _EmptyBoards(onCreated: _load);
    }
    final view = _view!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              EdgeInsets.fromLTRB(context.pageGutter, 16, context.pageGutter, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.t('board.title'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              DropdownButton<String>(
                value: _boardId,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(16),
                items: [
                  for (final board in _boards)
                    DropdownMenuItem(value: board.id, child: Text(board.name)),
                ],
                onChanged: (value) {
                  _boardId = value;
                  _sprintId = null;
                  _load();
                },
              ),
              if (view.sprints.isNotEmpty)
                DropdownButton<String?>(
                  value: _sprintId,
                  hint: Text(context.t('board.allSprints')),
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
                  items: [
                    DropdownMenuItem(
                        value: null, child: Text(context.t('board.allSprints'))),
                    for (final sprint in view.sprints)
                      DropdownMenuItem(value: sprint.id, child: Text(sprint.name)),
                  ],
                  onChanged: (value) {
                    _sprintId = value;
                    _load();
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.all(context.pageGutter),
            itemCount: view.columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final column = view.columns[index];
              return _BoardColumn(
                column: column,
                onAccept: (issue) => _moveIssue(issue, column),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyBoards extends StatelessWidget {
  const _EmptyBoards({required this.onCreated});

  final Future<void> Function() onCreated;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_kanban_rounded,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(context.t('board.empty'),
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final repository = context.read<HivoraRepository>();
              try {
                final projects = await repository.projects();
                if (projects.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(context.t('board.needsProject'))));
                  }
                  return;
                }
                await repository.createBoard(
                    context.mounted ? context.t('board.defaultName') : 'Board',
                    [projects.first.id]);
                await onCreated();
              } on ApiFailure catch (failure) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(failure.message)));
                }
              }
            },
            child: Text(context.t('board.create')),
          ),
        ],
      ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({required this.column, required this.onAccept});

  final BoardColumnView column;
  final void Function(Issue) onAccept;

  @override
  Widget build(BuildContext context) {
    final overWip =
        column.wipLimit != null && column.issues.length > column.wipLimit!;
    return SizedBox(
      width: 300,
      child: DragTarget<Issue>(
        onAcceptWithDetails: (details) => onAccept(details.data),
        builder: (context, candidates, rejected) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: candidates.isNotEmpty
                  ? AppColors.pastelLavender.withValues(alpha: 0.5)
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          column.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                      PillChip(
                        label: column.wipLimit != null
                            ? '${column.issues.length}/${column.wipLimit}'
                            : '${column.issues.length}',
                        background: overWip
                            ? AppColors.danger.withValues(alpha: 0.15)
                            : Colors.white,
                        foreground:
                            overWip ? AppColors.danger : AppColors.textPrimary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: column.issues.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final issue = column.issues[index];
                      return LongPressDraggable<Issue>(
                        data: issue,
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 270,
                            child: _BoardCard(issue: issue, dragging: true),
                          ),
                        ),
                        childWhenDragging:
                            Opacity(opacity: 0.35, child: _BoardCard(issue: issue)),
                        child: _BoardCard(issue: issue),
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

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.issue, this.dragging = false});

  final Issue issue;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      onTap: dragging ? null : () => context.go('/issues/${issue.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            issue.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                issue.readableId,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Icon(Icons.flag_rounded,
                  size: 14, color: priorityColor(issue.priority)),
            ],
          ),
        ],
      ),
    );
  }
}
