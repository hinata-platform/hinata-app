import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/hinata_repository.dart';
import '../../../core/models/git_connection.dart';
import '../../../core/models/git_dev_info.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../git_tokens.dart';
import 'dev_rows.dart';

/// Issue main-column summary: the auto-linked git activity for the issue,
/// categorised into Branches · Commits · Pull/Merge requests · Builds. Fetches
/// its own [DevInfo]; PR/MR merge & ready actions run real optimistic
/// transitions reconciled against the server (which applies the project's
/// automation rules).
class DevelopmentSummary extends StatefulWidget {
  const DevelopmentSummary({
    super.key,
    required this.issue,
    required this.project,
    required this.names,
    required this.avatars,
    required this.onIssueChanged,
  });

  final Issue issue;
  final Project project;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final ValueChanged<Issue> onIssueChanged;

  @override
  State<DevelopmentSummary> createState() => _DevelopmentSummaryState();
}

class _DevelopmentSummaryState extends State<DevelopmentSummary> {
  DevInfo? _info;
  bool _loading = true;
  bool _busy = false;
  String? _openKey;

  HinataRepository get _repo => context.read<HinataRepository>();
  GitProvider get _prov =>
      gitProviderFrom(widget.project.git?.provider) ?? GitProvider.github;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(DevelopmentSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.issue.readableId != widget.issue.readableId) _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final info = await _repo.gitDevInfo(widget.issue.readableId);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
        _openKey = _firstCategory(info);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String? _firstCategory(DevInfo i) {
    if (i.branches.isNotEmpty) return 'branches';
    if (i.commits.isNotEmpty) return 'commits';
    if (i.prs.isNotEmpty) return 'prs';
    if (i.builds.isNotEmpty) return 'builds';
    return null;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  String _message(Object e) =>
      e is ApiFailure ? e.message : 'Something went wrong. Please try again.';

  String _transitionNote(GitRule rule) {
    if (!rule.on || rule.toStateId == null) return '';
    for (final s in widget.project.workflowStates) {
      if (s.id == rule.toStateId) return ' → ${s.name}';
    }
    return '';
  }

  Future<void> _merge(GitPullRequest pr) =>
      _prAction(pr, PrState.merged, () => _repo.gitMergePr(widget.issue.readableId, pr.number),
          _transitionNote(widget.project.git!.automation.prMerged), 'merged');

  Future<void> _ready(GitPullRequest pr) =>
      _prAction(pr, PrState.open, () => _repo.gitReadyPr(widget.issue.readableId, pr.number),
          _transitionNote(widget.project.git!.automation.prOpened), 'ready for review');

  Future<void> _prAction(
    GitPullRequest pr,
    PrState optimistic,
    Future<({DevInfo devInfo, Issue issue})> Function() call,
    String note,
    String verb,
  ) async {
    final before = _info;
    if (before == null) return;
    setState(() {
      _busy = true;
      _info = before.withPr(pr.copyWith(state: optimistic));
    });
    try {
      final result = await call();
      if (!mounted) return;
      setState(() {
        _info = result.devInfo;
        _busy = false;
      });
      widget.onIssueChanged(result.issue);
      _toast('${_prov.prShort} $verb · ${widget.issue.readableId}$note');
    } catch (e) {
      if (mounted) {
        setState(() {
          _info = before;
          _busy = false;
        });
      }
      _toast(_message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    // The sheet only mounts this when the project has a repo connected; while the
    // first fetch is in flight (or if it failed / is unconnected) render nothing.
    if (_loading && info == null) return const SizedBox.shrink();
    if (info == null || !info.connected) return const SizedBox.shrink();
    // Jira-style: the whole Development section stays hidden until there is
    // linked work (a branch, commit, PR/MR or build). No empty placeholder.
    if (!info.hasAny) return const SizedBox.shrink();

    final git = widget.project.git!;
    // Owns its own leading gap so an empty (collapsed) section leaves no orphan
    // spacing in the sheet's main column.
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Development',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Expanded(child: _repoChip(git)),
            ],
          ),
          const SizedBox(height: 10),
          ..._categories(info),
        ],
      ),
    );
  }

  Widget _repoChip(GitConnection git) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.22),
                spreadRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            '${_prov.label} · ${git.owner}/${git.repo}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 12,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _categories(DevInfo info) {
    final cats = <Widget>[];
    void add(
      String key,
      String label,
      int hue,
      int count,
      Widget? badge,
      List<Widget> body,
    ) {
      if (count == 0) return;
      cats.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _DevCat(
            label: label,
            hue: hue,
            count: count,
            badge: badge,
            open: _openKey == key,
            onToggle: () => setState(() => _openKey = _openKey == key ? null : key),
            body: body,
          ),
        ),
      );
    }

    add('branches', 'Branches', kHueBranch, info.branches.length, null, [
      for (final b in info.branches)
        BranchRow(
          branch: b,
          names: widget.names,
          avatars: widget.avatars,
          onOpen: () => _toast('Opening branch on ${_prov.label}'),
        ),
    ]);
    add(
      'commits',
      'Commits',
      kHueCommit,
      info.commits.length,
      info.commits.isNotEmpty && info.commits.first.at != null
          ? Text(
              'latest ${agoSuffixed(info.commits.first.at)}',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11.5,
                color: AppColors.inkFaint,
              ),
            )
          : null,
      [
        for (final c in info.commits)
          CommitRow(commit: c, names: widget.names, avatars: widget.avatars),
      ],
    );
    add('prs', _prov.prTermPlural, kHuePullRequest, info.prs.length, _prBadge(info), [
      for (final pr in info.prs)
        PrRow(
          pr: pr,
          provider: _prov,
          names: widget.names,
          avatars: widget.avatars,
          busy: _busy,
          onMerge: () => _merge(pr),
          onReady: () => _ready(pr),
          onOpen: () => _toast('Opening ${_prov.prShort} #${pr.number} on ${_prov.label}'),
        ),
    ]);
    add('builds', 'Builds', kHueBuild, info.builds.length, _buildBadge(info), [
      for (final b in info.builds) BuildRow(run: b),
    ]);
    return cats;
  }

  Widget? _prBadge(DevInfo info) {
    if (info.prs.isEmpty) return null;
    final s = prStateStyle(info.prs.first.state);
    return StatePill(hue: s.hue, icon: s.icon, label: s.label);
  }

  Widget? _buildBadge(DevInfo info) {
    if (info.builds.isEmpty) return null;
    final s = checkStyle(info.builds.first.status);
    return StatePill(hue: s.hue, icon: s.icon, label: s.label);
  }
}

class _DevCat extends StatelessWidget {
  const _DevCat({
    required this.label,
    required this.hue,
    required this.count,
    required this.badge,
    required this.open,
    required this.onToggle,
    required this.body,
  });

  final String label;
  final int hue;
  final int count;
  final Widget? badge;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              child: Row(
                children: [
                  DevGlyph(hue: hue, icon: categoryIcon(_keyForLabel(label)), size: 30),
                  const SizedBox(width: 11),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11.5,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  if (badge != null) ...[badge!, const SizedBox(width: 8)],
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.hairline2)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: body),
            ),
        ],
      ),
    );
  }

  // The category icon is driven by the label; map the visible label back to the
  // token key (provider-adaptive PR/MR labels both map to 'prs').
  String _keyForLabel(String label) {
    if (label == 'Branches') return 'branches';
    if (label == 'Commits') return 'commits';
    if (label == 'Builds') return 'builds';
    return 'prs';
  }
}
