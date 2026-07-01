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
import '../../../core/widgets/soft_card.dart';
import 'copy_field.dart';
import 'dev_rows.dart';
import 'provider_glyph.dart';

/// Issue right-rail quick-actions (`DeploymentPanel`): Open in IDE · Create
/// branch (with a copyable `git checkout -b …` + a branch-template gear) ·
/// Create commit (copy key + example commit). Popovers reveal **inline** (no
/// floating overlay) so nothing can overflow the narrow rail at any width; the
/// command fields are single-line and horizontally scrollable.
class DeploymentPanel extends StatefulWidget {
  const DeploymentPanel({
    super.key,
    required this.issue,
    required this.project,
    required this.onConnectInSettings,
    required this.onProjectChanged,
  });

  final Issue issue;
  final Project project;
  final VoidCallback onConnectInSettings;
  final ValueChanged<Project> onProjectChanged;

  @override
  State<DeploymentPanel> createState() => _DeploymentPanelState();
}

class _DeploymentPanelState extends State<DeploymentPanel> {
  bool _open = true;
  String? _pop; // 'branch' | 'commit'
  bool _gear = false;
  String? _templateOverride;

  HinataRepository get _repo => context.read<HinataRepository>();
  GitConnection? get _git => widget.project.git;
  GitProvider? get _provider => gitProviderFrom(_git?.provider);

  @override
  void didUpdateWidget(DeploymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project.git?.branchTemplate != oldWidget.project.git?.branchTemplate) {
      _templateOverride = null;
    }
  }

  String get _key => widget.issue.readableId;

  String get _template =>
      _templateOverride ?? _git?.branchTemplate ?? '{key}-{summary}';

  String get _branchName => _template
      .replaceAll('{key}', _key)
      .replaceAll('{summary}', _slug(widget.issue.title));

  String get _checkout => 'git checkout -b $_branchName';

  String get _commitExample => 'git commit -m "$_key ${widget.issue.title}"';

  static String _slug(String s) {
    final cleaned = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.split('-').where((w) => w.isNotEmpty).take(5).join('-');
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

  void _togglePop(String which) =>
      setState(() => _pop = _pop == which ? null : which);

  Future<void> _setTemplate(String next) async {
    setState(() => _templateOverride = next);
    try {
      final updated = await _repo.gitSetBranchTemplate(widget.project.id, next);
      if (mounted) widget.onProjectChanged(updated);
    } catch (e) {
      if (mounted) setState(() => _templateOverride = null);
      _toast(e is ApiFailure ? e.message : 'Could not save the template');
    }
  }

  void _appendToken(String token) {
    final t = _template;
    _setTemplate(t + (t.isNotEmpty && !t.endsWith('-') ? '-' : '') + token);
  }

  String? _stateName(String? id) {
    if (id == null) return null;
    for (final s in widget.project.workflowStates) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final connected = _git != null && _provider != null;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(connected),
          if (_open) ...[
            const SizedBox(height: 4),
            if (connected) _connectedBody() else _disconnected(),
          ],
        ],
      ),
    );
  }

  Widget _header(bool connected) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            AnimatedRotation(
              turns: _open ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(LucideIcons.chevronRight, size: 15, color: AppColors.inkFaint),
            ),
            const SizedBox(width: 8),
            Text(
              'DEPLOYMENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: AppColors.inkSoft,
              ),
            ),
            const Spacer(),
            if (connected)
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProviderGlyph(provider: _provider!, size: 15),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _git!.repo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 11,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _connectedBody() {
    final auto = _git!.automation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _actionRow(
          icon: LucideIcons.squareTerminal,
          label: 'Open in IDE',
          trailing: Icon(LucideIcons.externalLink, size: 14, color: AppColors.inkFaint),
          onTap: () => _toast('Opening $_key in your IDE…'),
        ),
        _actionRow(
          icon: LucideIcons.gitBranch,
          label: 'Create branch',
          open: _pop == 'branch',
          trailing: _chevron(_pop == 'branch'),
          onTap: () => _togglePop('branch'),
        ),
        if (_pop == 'branch') _branchPop(auto),
        _actionRow(
          icon: LucideIcons.gitCommitHorizontal,
          label: 'Create commit',
          open: _pop == 'commit',
          trailing: _chevron(_pop == 'commit'),
          onTap: () => _togglePop('commit'),
        ),
        if (_pop == 'commit') _commitPop(auto),
      ],
    );
  }

  Widget _branchPop(GitAutomation auto) {
    final moveTo = _stateName(auto.branchCreated.toStateId);
    return _Pop(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _gear
                      ? 'Branch name template · ${widget.project.name}'
                      : 'APPLY “GIT BRANCH” & “GIT CHECKOUT” TO A NEW BRANCH',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _GearButton(active: _gear, onTap: () => setState(() => _gear = !_gear)),
            ],
          ),
          const SizedBox(height: 9),
          if (_gear) ...[
            CopyField(text: _template, onCopied: () => _toast('Copied')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip('+ {key}', () => _appendToken('{key}')),
                _chip('+ {summary}', () => _appendToken('{summary}')),
                _chip('reset', () => _setTemplate('{key}-{summary}')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tokens are filled in when the branch is created. Applies to every '
              'issue in this project.',
              style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.inkSoft),
            ),
          ] else ...[
            CopyField(text: _checkout, onCopied: () => _toast('Copied to clipboard')),
            if (auto.branchCreated.on && moveTo != null) ...[
              const SizedBox(height: 10),
              _autoHint('Pushing this branch moves $_key to ', moveTo, '.'),
            ],
          ],
        ],
      ),
    );
  }

  Widget _commitPop(GitAutomation auto) {
    return _Pop(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Link commits to this issue',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Add the issue key to your commit messages to link them here '
            'automatically.',
            style: TextStyle(fontSize: 12, height: 1.55, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 10),
          _fieldLabel('Copy key'),
          CopyField(text: _key, onCopied: () => _toast('Copied')),
          const SizedBox(height: 10),
          _fieldLabel('Copy example commit'),
          CopyField(text: _commitExample, onCopied: () => _toast('Copied')),
          if (auto.smartCommits) ...[
            const SizedBox(height: 10),
            _autoHintRich(),
          ],
        ],
      ),
    );
  }

  Widget _disconnected() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GitEmptyBox(
        icon: LucideIcons.gitBranch,
        action: FilledButton.icon(
          onPressed: widget.onConnectInSettings,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: const Color(0xFF2A2410),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
          ),
          icon: const Icon(LucideIcons.link, size: 14),
          label: const Text('Connect in settings'),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'No repository is connected to '),
              TextSpan(
                text: widget.project.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(
                text: ' yet. Connect one to create branches and link commits.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── bits ────────────────────────────────────────────────────────────────
  Widget _actionRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    required VoidCallback onTap,
    bool open = false,
  }) {
    return Material(
      color: open ? AppColors.surfaceMuted : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppColors.accentStrong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _chevron(bool open) => AnimatedRotation(
    turns: open ? 0.5 : 0,
    duration: const Duration(milliseconds: 180),
    child: Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkFaint),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.inkFaint,
      ),
    ),
  );

  Widget _chip(String label, VoidCallback onTap) => GestureDetector(
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

  Widget _autoHint(String pre, String bold, String post) => Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Icon(LucideIcons.zap, size: 12, color: AppColors.accentStrong),
          ),
        ),
        TextSpan(text: pre),
        TextSpan(text: bold, style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: post),
      ],
    ),
    style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.inkSoft),
  );

  Widget _autoHintRich() => Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Icon(LucideIcons.zap, size: 12, color: AppColors.accentStrong),
          ),
        ),
        const TextSpan(text: 'Smart commits are on — add '),
        _monoChip('#done'),
        const TextSpan(text: ', '),
        _monoChip('#comment'),
        const TextSpan(text: ' or '),
        _monoChip('#time 2h'),
        const TextSpan(text: '.'),
      ],
    ),
    style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.inkSoft),
  );

  InlineSpan _monoChip(String text) => TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: 11.5,
      color: AppColors.accentStrong,
    ),
  );
}

class _Pop extends StatelessWidget {
  const _Pop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.hairline),
      ),
      child: child,
    );
  }
}

class _GearButton extends StatelessWidget {
  const _GearButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Branch name template',
      child: Material(
        color: active ? AppColors.accentSoft : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Icon(
              LucideIcons.settings2,
              size: 14,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}
