import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import 'issue_form.dart';

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key, this.projectId});

  final String? projectId;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  late FetchCubit<({List<Issue> issues, int total})> _cubit;
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit(() => context.read<HivoraRepository>().issues(
          projectId: widget.projectId,
          query: _query,
        ))
      ..load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _cubit.close();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value;
      _cubit.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                context.pageGutter, 16, context.pageGutter, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: context.t('issues.searchHint'),
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final created = await showIssueForm(context,
                        projectId: widget.projectId);
                    if (created != null) _cubit.load();
                  },
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(context.t('issues.new')),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<FetchCubit<({List<Issue> issues, int total})>,
                FetchState<({List<Issue> issues, int total})>>(
              builder: (context, state) {
                return RefreshIndicator(
                  onRefresh: _cubit.load,
                  child: AsyncView(
                    isLoading: state.isLoading,
                    hasData: state.hasData,
                    errorKey: state.errorKey,
                    onRetry: _cubit.load,
                    builder: (context) {
                      final issues = state.data!.issues;
                      if (issues.isEmpty) {
                        return ListView(
                          children: [
                            const SizedBox(height: 120),
                            Center(
                              child: Text(
                                context.t('issues.empty'),
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        );
                      }
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(context.pageGutter, 8,
                            context.pageGutter, context.pageGutter),
                        itemCount: issues.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            IssueListTile(issue: issues[index]),
                      );
                    },
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

class IssueListTile extends StatelessWidget {
  const IssueListTile({super.key, required this.issue, this.onTap});

  final Issue issue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      onTap: onTap ?? () => context.go('/issues/${issue.id}'),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 44,
            decoration: BoxDecoration(
              color: priorityColor(issue.priority),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${issue.readableId} · ${context.t('type.${issue.type.toLowerCase()}')}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PillChip(
            label: issue.state,
            background: issue.resolved
                ? AppColors.pastelMint
                : AppColors.surfaceMuted,
          ),
        ],
      ),
    );
  }
}
