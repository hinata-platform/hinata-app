import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/entity_avatar_editor.dart';
import '../projects/project_create_form.dart';
import 'team_modal_kit.dart';
import 'team_widgets.dart';

/// Add-project modal: attach an existing project or create a new one.
///
/// The second tab is [ProjectCreateFields] — the same form the project list
/// creates from, so a project made here is made the same way, with the same
/// key suggestion, the same accents and the same lead picker.
Future<bool?> showAddProjectModal(
  BuildContext context, {
  required Team team,
  required List<Project> available,
  required List<DirectoryUser> leadCandidates,
  required String currentUserId,
  Set<String> takenKeys = const {},
}) {
  final repo = context.read<TeamRepository>();
  return showTeamModal<bool>(
    context,
    _AddProjectBody(
      repo: repo,
      team: team,
      available: available,
      leadCandidates: leadCandidates,
      currentUserId: currentUserId,
      takenKeys: takenKeys,
    ),
  );
}

class _AddProjectBody extends StatefulWidget {
  const _AddProjectBody({
    required this.repo,
    required this.team,
    required this.available,
    required this.leadCandidates,
    required this.currentUserId,
    required this.takenKeys,
  });

  final TeamRepository repo;
  final Team team;
  final List<Project> available;

  /// Only the attach tab needs these: it names each available project's lead.
  final List<DirectoryUser> leadCandidates;
  final String currentUserId;
  final Set<String> takenKeys;

  @override
  State<_AddProjectBody> createState() => _AddProjectBodyState();
}

class _AddProjectBodyState extends State<_AddProjectBody> {
  late bool _attachMode = widget.available.isNotEmpty;
  final _selected = <String>{};

  /// The new project, kept for the life of the modal so switching back and
  /// forth between the two tabs does not throw away what was typed. It opens on
  /// the team's own accent, which is a better guess than the palette's first.
  late final ProjectDraft _draft = ProjectDraft(
    takenKeys: widget.takenKeys,
    hue: widget.team.colorHue,
    meId: widget.currentUserId.isEmpty ? null : widget.currentUserId,
  );

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_refresh);
  }

  @override
  void dispose() {
    _draft.removeListener(_refresh);
    _draft.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _attach() => _run(
    () => widget.repo.attachTeamProjects(widget.team.id, _selected.toList()),
  );

  Future<void> _create() => _run(() async {
    final created = await widget.repo.createTeamProject(
      widget.team.id,
      key: _draft.trimmedKey,
      name: _draft.trimmedName,
      description: _draft.trimmedDescription,
      color: _draft.colorHex,
      leadId: _draft.lead?.id,
    );
    if (mounted) {
      final repo = context.read<ProjectRepository>();
      await uploadPendingAvatar(
        context,
        _draft.pendingAvatar,
        EntityAvatarStrings.project,
        (file) => repo.uploadProjectAvatar(created.id, file),
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = _attachMode ? _selected.isNotEmpty : _draft.valid;
    return ModalShell(
      icon: LucideIcons.folderPlus,
      title: context.t('teams.addProjectTitle'),
      subtitle: context.t(
        'teams.addProjectSubtitle',
        variables: {'name': widget.team.name},
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeToggle(
            attachMode: _attachMode,
            onChanged: (v) => setState(() => _attachMode = v),
          ),
          const SizedBox(height: 18),
          if (_attachMode) ..._attachStep(context) else ..._createStep(context),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ],
        ],
      ),
      footer: ModalFooter(
        primaryLabel: _attachMode
            ? context.t(
                'teams.attachCta',
                variables: {'count': '${_selected.length}'},
                count: _selected.length,
              )
            : context.t('teams.createProjectCta'),
        primaryIcon: _attachMode ? LucideIcons.link : LucideIcons.check,
        busy: _busy,
        onPrimary: canSubmit ? (_attachMode ? _attach : _create) : null,
      ),
    );
  }

  List<Widget> _attachStep(BuildContext context) {
    if (widget.available.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            context.t('teams.allProjectsAttached'),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < widget.available.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        () {
          final p = widget.available[i];
          final lead = p.leadId != null
              ? widget.leadCandidates
                    .where((u) => u.id == p.leadId)
                    .map((u) => u.displayName.split(' ').first)
                    .cast<String?>()
                    .firstOrNull
              : null;
          return CheckRow(
            selected: _selected.contains(p.id),
            onTap: () => setState(
              () => _selected.contains(p.id)
                  ? _selected.remove(p.id)
                  : _selected.add(p.id),
            ),
            leading: ProjectKeyGlyph(
              label: p.key,
              color: projectHexColor(p.color),
              avatarUrl: p.avatarUrl,
              size: 32,
              radius: 8,
            ),
            title: p.name,
            subtitle: lead != null
                ? context.t('teams.leadName', variables: {'name': lead})
                : null,
          );
        }(),
      ],
    ];
  }

  List<Widget> _createStep(BuildContext context) => [
    ProjectCreateFields(draft: _draft),
  ];
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.attachMode, required this.onChanged});

  final bool attachMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          _seg(
            context,
            true,
            LucideIcons.link,
            context.t('teams.attachExisting'),
          ),
          const SizedBox(width: 6),
          _seg(context, false, LucideIcons.plus, context.t('teams.createNew')),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, bool mode, IconData icon, String label) {
    final on = attachMode == mode;
    return Expanded(
      child: Material(
        color: on ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => onChanged(mode),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: on ? AppColors.ink : AppColors.inkSoft,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: on ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
