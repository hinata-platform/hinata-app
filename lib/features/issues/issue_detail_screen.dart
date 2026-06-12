import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import 'issue_form.dart';
import 'work_log_sheet.dart';

typedef _Detail = ({Issue issue, List<IssueComment> comments, List<WorkItem> workItems});

class IssueDetailScreen extends StatefulWidget {
  const IssueDetailScreen({super.key, required this.issueId});

  final String issueId;

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  late final FetchCubit<_Detail> _cubit;
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    final repository = context.read<HivoraRepository>();
    _cubit = FetchCubit(() async => (
          issue: await repository.issue(widget.issueId),
          comments: await repository.comments(widget.issueId),
          workItems: await repository.workItems(widget.issueId),
        ))
      ..load();
  }

  @override
  void dispose() {
    _comment.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<_Detail>, FetchState<_Detail>>(
        builder: (context, state) {
          return AsyncView(
            isLoading: state.isLoading,
            hasData: state.hasData,
            errorKey: state.errorKey,
            onRetry: _cubit.load,
            builder: (context) {
              final detail = state.data!;
              final issue = detail.issue;
              return SingleChildScrollView(
                padding: context.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.canPop()
                              ? context.pop()
                              : context.go('/issues'),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        Expanded(
                          child: Text(
                            issue.readableId,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: context.t('issues.edit'),
                          onPressed: () async {
                            final updated =
                                await showIssueForm(context, existing: issue);
                            if (updated != null) _cubit.load();
                          },
                          icon: const Icon(Icons.edit_rounded),
                        ),
                        IconButton(
                          tooltip: context.t('common.delete'),
                          onPressed: () => _confirmDelete(issue),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.danger),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            issue.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _StatePicker(issue: issue, onChanged: _patch),
                              PillChip(
                                label: context
                                    .t('priority.${issue.priority.toLowerCase()}'),
                                background: AppColors.surfaceMuted,
                                foreground: priorityColor(issue.priority),
                              ),
                              PillChip(
                                label:
                                    context.t('type.${issue.type.toLowerCase()}'),
                                background: AppColors.surfaceMuted,
                              ),
                              for (final tag in issue.tags)
                                PillChip(
                                    label: '#$tag',
                                    background: AppColors.pastelLavender),
                            ],
                          ),
                          if ((issue.description ?? '').isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(issue.description!,
                                style: const TextStyle(height: 1.55)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(
                            title: context.t('issues.timeTracking'),
                            actionLabel: context.t('issues.logTime'),
                            onAction: () async {
                              final logged =
                                  await showWorkLogSheet(context, issue.id);
                              if (logged == true) _cubit.load();
                            },
                          ),
                          Text(
                            context.t('issues.spent', variables: {
                              'spent': _formatMinutes(issue.spentMinutes),
                              'estimate': issue.estimateMinutes != null
                                  ? _formatMinutes(issue.estimateMinutes!)
                                  : '–',
                            }),
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          for (final item in detail.workItems.take(8))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.timer_outlined,
                                  color: AppColors.accentPurple),
                              title: Text(
                                  '${_formatMinutes(item.durationMinutes)} · ${item.activityType}'),
                              subtitle: item.description != null
                                  ? Text(item.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)
                                  : null,
                              trailing: Text(
                                item.date != null
                                    ? MaterialLocalizations.of(context)
                                        .formatShortDate(item.date!)
                                    : '',
                                style: const TextStyle(
                                    color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(title: context.t('issues.comments')),
                          for (final comment in detail.comments)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(comment.text,
                                        style: const TextStyle(height: 1.45)),
                                    const SizedBox(height: 6),
                                    Text(
                                      comment.createdAt != null
                                          ? MaterialLocalizations.of(context)
                                              .formatShortDate(
                                                  comment.createdAt!.toLocal())
                                          : '',
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _comment,
                                  decoration: InputDecoration(
                                    hintText: context.t('issues.addComment'),
                                  ),
                                  onSubmitted: (_) => _submitComment(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                    backgroundColor: AppColors.navy),
                                onPressed: _submitComment,
                                icon: const Icon(Icons.send_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    try {
      await context.read<HivoraRepository>().updateIssue(widget.issueId, patch);
      await _cubit.load();
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _submitComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<HivoraRepository>().addComment(widget.issueId, text);
      _comment.clear();
      await _cubit.load();
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _confirmDelete(Issue issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(dialogContext.t('issues.deleteTitle')),
        content: Text(dialogContext
            .t('issues.deleteBody', variables: {'id': issue.readableId})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<HivoraRepository>().deleteIssue(issue.id);
      if (mounted) context.go('/issues');
    }
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '${rest}m';
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}

class _StatePicker extends StatelessWidget {
  const _StatePicker({required this.issue, required this.onChanged});

  final Issue issue;
  final Future<void> Function(Map<String, dynamic>) onChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Project>>(
      future: context.read<HivoraRepository>().projects(),
      builder: (context, snapshot) {
        final project = snapshot.data
            ?.where((candidate) => candidate.id == issue.projectId)
            .firstOrNull;
        final states = project?.workflowStates ?? [issue.state];
        return PopupMenuButton<String>(
          tooltip: context.t('issues.changeState'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (state) => onChanged({'state': state}),
          itemBuilder: (context) => [
            for (final state in states)
              PopupMenuItem(value: state, child: Text(state)),
          ],
          child: PillChip(
            label: '${issue.state} ▾',
            background: AppColors.navy,
            foreground: Colors.white,
          ),
        );
      },
    );
  }
}
