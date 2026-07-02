import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/hinata_repository.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/git_connection.dart';
import '../../../core/models/git_dev_info.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../projects/settings/settings_common.dart';
import '../../sprint/modals/glass_modal.dart';
import '../widgets/copy_field.dart';
import '../widgets/provider_glyph.dart';
import 'connect_repo_wizard.dart';

/// Project-settings section: per-project repository connection + development
/// automation + branch-naming template. Connect/disconnect/automation each
/// persist immediately (their own endpoints), independent of the settings
/// draft/save bar — every mutation returns the updated project via
/// [onProjectChanged].
class GitIntegrationSection extends StatefulWidget {
  const GitIntegrationSection({
    super.key,
    required this.project,
    required this.users,
    required this.onProjectChanged,
  });

  final Project project;
  final Map<String, DirectoryUser> users;
  final ValueChanged<Project> onProjectChanged;

  @override
  State<GitIntegrationSection> createState() => _GitIntegrationSectionState();
}

class _GitIntegrationSectionState extends State<GitIntegrationSection> {
  GitAutomation? _automationOverride;
  String? _templateOverride;
  bool _busy = false;

  HinataRepository get _repo => context.read<HinataRepository>();
  GitConnection? get _git => widget.project.git;
  GitProvider? get _provider =>
      _git == null ? null : gitProviderFrom(_git!.provider);

  @override
  void didUpdateWidget(GitIntegrationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A server round-trip landed → drop the optimistic overrides.
    if (widget.project.git?.automation != oldWidget.project.git?.automation) {
      _automationOverride = null;
    }
    if (widget.project.git?.branchTemplate != oldWidget.project.git?.branchTemplate) {
      _templateOverride = null;
    }
  }

  void _toast(String message) => settingsToast(context, message);

  String _message(Object e) =>
      e is ApiFailure ? e.message : 'Something went wrong. Please try again.';

  Future<void> _connect({bool token = false}) async {
    final updated = await showConnectRepoWizard(
      context,
      project: widget.project,
      startToken: token,
    );
    if (updated != null && mounted) {
      widget.onProjectChanged(updated);
      final added = updated.allRepos.isNotEmpty ? updated.allRepos.last : null;
      _toast(added == null ? 'Repository connected' : 'Connected ${added.owner}/${added.repo}');
    }
  }

  Future<void> _disconnect(GitConnection repo) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.unlink,
      title: 'Disconnect ${repo.owner}/${repo.repo}?',
      message:
          'Development information and automation from this repository will stop '
          'updating. You can reconnect at any time.',
      confirmLabel: 'Disconnect',
      confirmIcon: LucideIcons.unlink,
      destructive: true,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final updated = await _repo.gitDisconnect(widget.project.id, repoId: repo.id);
      if (mounted) {
        widget.onProjectChanged(updated);
        _toast('Disconnected ${repo.owner}/${repo.repo}');
      }
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resync(GitConnection repo) async {
    setState(() => _busy = true);
    try {
      final updated = await _repo.gitResync(widget.project.id, repoId: repo.id);
      if (mounted) {
        widget.onProjectChanged(updated);
        _toast('Development information synced');
      }
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateAutomation(GitAutomation next) async {
    setState(() => _automationOverride = next);
    try {
      final updated = await _repo.gitSetAutomation(widget.project.id, next);
      if (mounted) widget.onProjectChanged(updated);
    } catch (e) {
      if (mounted) setState(() => _automationOverride = null);
      _toast(_message(e));
    }
  }

  Future<void> _updateTemplate(String next) async {
    setState(() => _templateOverride = next);
    try {
      final updated = await _repo.gitSetBranchTemplate(widget.project.id, next);
      if (mounted) widget.onProjectChanged(updated);
    } catch (e) {
      if (mounted) setState(() => _templateOverride = null);
      _toast(_message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final git = _git;
    final prov = _provider;
    return SettingsSection(
      title: 'Git integration',
      trailing: (git != null && prov != null)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProviderGlyph(provider: prov, size: 16),
                const SizedBox(width: 6),
                Text(
                  prov.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            )
          : null,
      child: (git != null && prov != null)
          ? _connected(git, prov)
          : _cta(),
    );
  }

  // ── not connected ────────────────────────────────────────────────────────
  Widget _cta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final p in GitProvider.values) ...[
              if (p != GitProvider.values.first) const SizedBox(width: 10),
              ProviderGlyph(provider: p, size: 36),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Connect ${widget.project.name} to a repository',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            'See branches, commits and pull / merge requests on every issue, '
            'create branches straight from an issue, and transition issues '
            'automatically as work is pushed. Each project links to its own '
            'repository.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: 'Connect repository',
          icon: LucideIcons.link,
          onPressed: () => _connect(),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'OAuth for GitHub, GitLab & Bitbucket — or '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GestureDetector(
                  onTap: () => _connect(token: true),
                  child: Text(
                    'connect with a URL & token',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentStrong,
                    ),
                  ),
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  // ── connected ────────────────────────────────────────────────────────────
  Widget _connected(GitConnection git, GitProvider prov) {
    final repos = widget.project.allRepos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < repos.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _repoCard(repos[i], gitProviderFrom(repos[i].provider) ?? prov),
        ],
        const SizedBox(height: 12),
        _addRepoButton(),
        const SizedBox(height: 20),
        _automation(git, prov),
        const SizedBox(height: 20),
        _branchNaming(git),
        const SizedBox(height: 16),
        _keyCallout(prov),
      ],
    );
  }

  Widget _addRepoButton() {
    return GhostButton(
      label: 'Add repository',
      icon: LucideIcons.plus,
      onPressed: _busy ? null : () => _connect(),
    );
  }

  Widget _repoCard(GitConnection git, GitProvider prov) {
    final by = git.connectedBy == null ? null : widget.users[git.connectedBy];
    final connectedName = by?.displayName.split(' ').first;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProviderGlyph(provider: prov, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${git.owner}/',
                                style: TextStyle(color: AppColors.inkSoft),
                              ),
                              TextSpan(text: git.repo),
                            ],
                          ),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _branchChip(git.defaultBranch),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _metaLine(git, connectedName),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GhostButton(
                label: 'Re-sync',
                icon: LucideIcons.refreshCw,
                onPressed: _busy ? null : () => _resync(git),
              ),
              const Spacer(),
              _iconAction(
                icon: LucideIcons.unlink,
                tooltip: 'Disconnect repository',
                onTap: _busy ? null : () => _disconnect(git),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaLine(GitConnection git, String? connectedName) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.refreshCw, size: 13, color: AppColors.success),
            const SizedBox(width: 5),
            Text(
              'Synced ${_syncedLabel(git.lastSyncAt)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
        _dot(),
        Text(
          [
            if (connectedName != null) 'Connected by $connectedName',
            if (git.connectedAt != null) agoSuffixed(git.connectedAt),
          ].where((s) => s.isNotEmpty).join(' · '),
          style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
        ),
        _dot(),
        _methodBadge(git.isOAuth ? 'OAuth app' : 'Access token'),
      ],
    );
  }

  String _syncedLabel(DateTime? at) {
    final s = agoSuffixed(at);
    return s.isEmpty ? 'recently' : s;
  }

  // ── automation ─────────────────────────────────────────────────────────
  Widget _automation(GitConnection git, GitProvider prov) {
    final auto = _automationOverride ?? git.automation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subHeader(LucideIcons.workflow, 'Development automation'),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Move an issue automatically when work happens in '),
              TextSpan(
                text: '${git.owner}/${git.repo}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '. Rules use '),
              TextSpan(
                text: widget.project.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(
                text: '’s own workflow, so each project transitions on its own states.',
              ),
            ],
          ),
          style: TextStyle(fontSize: 12, height: 1.55, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 10),
        _ruleRow(
          icon: LucideIcons.gitBranch,
          verb: 'Branch created',
          when: 'A branch containing the key is created',
          rule: auto.branchCreated,
          onChanged: (r) => _updateAutomation(auto.copyWith(branchCreated: r)),
        ),
        _ruleRow(
          icon: LucideIcons.gitCommitHorizontal,
          verb: 'Commit pushed',
          when: 'A commit referencing the key is pushed to the default branch',
          rule: auto.commitPushed,
          onChanged: (r) => _updateAutomation(auto.copyWith(commitPushed: r)),
        ),
        _ruleRow(
          icon: LucideIcons.gitPullRequest,
          verb: '${prov.prShort} opened',
          when: 'A ${prov.prTerm.toLowerCase()} that references the key is opened',
          rule: auto.prOpened,
          onChanged: (r) => _updateAutomation(auto.copyWith(prOpened: r)),
        ),
        _ruleRow(
          icon: LucideIcons.gitMerge,
          verb: '${prov.prShort} merged',
          when: 'A ${prov.prTerm.toLowerCase()} that references the key is merged',
          rule: auto.prMerged,
          onChanged: (r) => _updateAutomation(auto.copyWith(prMerged: r)),
        ),
        _smartCommitsRow(auto),
      ],
    );
  }

  Widget _ruleRow({
    required IconData icon,
    required String verb,
    required String when,
    required GitRule rule,
    required ValueChanged<GitRule> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline2)),
      ),
      child: Opacity(
        opacity: rule.on ? 1 : 0.62,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ruleIcon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        verb,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Icon(LucideIcons.arrowRight, size: 14, color: AppColors.inkFaint),
                      _stateSelect(rule, onChanged),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    when,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: HiveSwitch(
                value: rule.on,
                onChanged: (v) => onChanged(rule.copyWith(on: v)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stateSelect(GitRule rule, ValueChanged<GitRule> onChanged) {
    WorkflowState? target;
    for (final s in widget.project.workflowStates) {
      if (s.id == rule.toStateId) target = s;
    }
    final enabled = rule.on;
    return Builder(
      builder: (chipContext) => Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          onTap: enabled
              ? () => _pickState(
                  chipContext,
                  rule,
                  (id) => onChanged(rule.copyWith(toStateId: id)),
                )
              : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (target != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: hueColor(target.hue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  target?.name ?? 'Choose state',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickState(
    BuildContext chipContext,
    GitRule rule,
    ValueChanged<String> onPicked,
  ) async {
    final box = chipContext.findRenderObject() as RenderBox?;
    Rect? anchor;
    if (box != null && box.hasSize) {
      anchor = box.localToGlobal(Offset.zero) & box.size;
    }
    final picked = await showGlassOptions<String>(
      context,
      title: 'Move to',
      anchorRect: anchor,
      options: [
        for (final s in widget.project.workflowStates)
          (
            value: s.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: hueColor(s.hue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  s.name,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
    if (picked != null && picked != rule.toStateId) onPicked(picked);
  }

  Widget _smartCommitsRow(GitAutomation auto) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ruleIcon(LucideIcons.terminal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart commits',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Run commands written in commit messages — comment, log time '
                  'and transition issues.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
                if (auto.smartCommits) ...[
                  const SizedBox(height: 10),
                  _scExample('${widget.project.key}-42', '#comment', 'ready for QA', '→ adds a comment'),
                  const SizedBox(height: 6),
                  _scExample('${widget.project.key}-42', '#time', '2h 30m', '→ logs work'),
                  const SizedBox(height: 6),
                  _scExample('${widget.project.key}-42', '#done', '', '→ transitions the issue'),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: HiveSwitch(
              value: auto.smartCommits,
              onChanged: (v) => _updateAutomation(auto.copyWith(smartCommits: v)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scExample(String key, String cmd, String rest, String explain) {
    return Wrap(
      spacing: 9,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.canvas2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: key,
                  style: TextStyle(color: AppColors.inkSoft),
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: cmd,
                  style: TextStyle(
                    color: AppColors.accentStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (rest.isNotEmpty) TextSpan(text: ' $rest'),
              ],
            ),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11.5,
              color: AppColors.ink,
            ),
          ),
        ),
        Text(
          explain,
          style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  // ── branch naming ────────────────────────────────────────────────────────
  Widget _branchNaming(GitConnection git) {
    final template = _templateOverride ?? git.branchTemplate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subHeader(LucideIcons.gitBranch, 'Branch naming'),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'The name suggested when creating a branch from an issue. '),
              _mono('{key}'),
              const TextSpan(text: ' and '),
              _mono('{summary}'),
              const TextSpan(text: ' are filled in per issue.'),
            ],
          ),
          style: TextStyle(fontSize: 12, height: 1.55, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CopyField(text: template, onCopied: () => _toast('Copied')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _tokenChip('+ {key}', () => _appendToken(template, '{key}')),
                  _tokenChip('+ {summary}', () => _appendToken(template, '{summary}')),
                  _tokenChip('reset', () => _updateTemplate('{key}-{summary}')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _appendToken(String current, String token) {
    final joined =
        current + (current.isNotEmpty && !current.endsWith('-') ? '-' : '') + token;
    _updateTemplate(joined);
  }

  // ── key callout ──────────────────────────────────────────────────────────
  Widget _keyCallout(GitProvider prov) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.accentLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.info, size: 16, color: AppColors.accentStrong),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Include '),
                  _mono('${widget.project.key}-123', boldAccent: true),
                  TextSpan(
                    text: ' in branch names, commit messages and '
                        '${prov.prTerm.toLowerCase()} titles to link work to this '
                        'project’s issues automatically.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: AppColors.accentStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── small shared bits ─────────────────────────────────────────────────────
  Widget _subHeader(IconData icon, String label) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.accentStrong),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _ruleIcon(IconData icon) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 16, color: AppColors.accentStrong),
  );

  Widget _branchChip(String branch) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      border: Border.all(color: AppColors.accentLine),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.gitBranch, size: 12, color: AppColors.accentStrong),
        const SizedBox(width: 5),
        Text(
          branch,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.accentStrong,
          ),
        ),
      ],
    ),
  );

  Widget _methodBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.canvas2,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppColors.inkSoft,
      ),
    ),
  );

  Widget _tokenChip(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.accentLine),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11,
          color: AppColors.accentStrong,
        ),
      ),
    ),
  );

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 16, color: AppColors.inkSoft),
        ),
      ),
    ),
  );

  Widget _dot() => Container(
    width: 3,
    height: 3,
    decoration: BoxDecoration(color: AppColors.inkFaint, shape: BoxShape.circle),
  );

  InlineSpan _mono(String text, {bool boldAccent = false}) => TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: AppTheme.fontMono,
      fontWeight: boldAccent ? FontWeight.w700 : FontWeight.w400,
    ),
  );
}
