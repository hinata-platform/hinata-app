import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/entity_avatar.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/entity_avatar_editor.dart';
import '../sprint/modals/glass_modal.dart';
import 'project_copy_sheet.dart';
import 'project_create_form.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

typedef _ProjectsData = ({
  List<Project> active,
  List<Project> archived,
  Map<String, String> names,
  Map<String, String> avatars,
});

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final FetchCubit<_ProjectsData> _cubit;

  /// Which of the three lists is on screen: the running projects, the
  /// templates, or the archive. Templates only exist while the module is on.
  _ProjectTab _tab = _ProjectTab.active;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<_ProjectsData>(() async {
      final results = await Future.wait([
        context.read<ProjectRepository>().projects(),
        context.read<ProjectRepository>().projects(archived: true),
        context.read<UserRepository>().users(),
      ]);
      final active = results[0] as List<Project>;
      final archived = results[1] as List<Project>;
      final users = results[2] as List<DirectoryUser>;
      final names = {for (final u in users) u.id: u.displayName};
      final avatars = {
        for (final u in users)
          if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
            u.id: u.avatarUrl!,
      };
      return (
        active: active,
        archived: archived,
        names: names,
        avatars: avatars,
      );
    })..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<_ProjectsData>, FetchState<_ProjectsData>>(
        builder: (context, state) {
          final all = state.data?.active ?? const <Project>[];
          final archived = state.data?.archived ?? const <Project>[];
          final names = state.data?.names ?? const <String, String>{};
          final avatars = state.data?.avatars ?? const <String, String>{};
          // The list route answers with both kinds unless asked otherwise, so
          // the split happens here rather than in a second request.
          final templatesOffered = context
              .select<AppConfigBloc, bool>(
                (bloc) => bloc.state.meta?.projectTemplates ?? false,
              );
          final templates = templatesOffered
              ? all.where((p) => p.template).toList(growable: false)
              : const <Project>[];
          final active = templatesOffered
              ? all.where((p) => !p.template).toList(growable: false)
              : all;
          // A tab that stopped existing — the flag went off while we were
          // looking at it — falls back to the running projects rather than to
          // an empty screen with no way out.
          final tab = _tab == _ProjectTab.templates && !templatesOffered
              ? _ProjectTab.active
              : _tab;
          final projects = switch (tab) {
            _ProjectTab.active => active,
            _ProjectTab.templates => templates,
            _ProjectTab.archived => archived,
          };
          return RefreshIndicator(
            onRefresh: _cubit.load,
            color: AppColors.accent,
            edgeOffset: context.topGutter,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    24 + context.topGutter,
                    context.pageGutter,
                    16,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: PageHead(
                      title: context.t('projects.title'),
                      subtitle: context.t(
                        'projects.summary',
                        variables: {
                          'active': '${active.length}',
                          'archived': '${archived.length}',
                        },
                      ),
                      actions: [
                        PrimaryButton(
                          icon: LucideIcons.plus,
                          label: context.t('projects.new'),
                          onPressed: _showCreate,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    0,
                    context.pageGutter,
                    16,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SegmentedControl(
                        selected: _tabIndex(tab, templatesOffered),
                        onChanged: (i) => setState(
                          () => _tab = _tabAt(i, templatesOffered),
                        ),
                        items: [
                          SegmentItem(
                            label: context.t('projects.active'),
                            icon: LucideIcons.folderOpen,
                          ),
                          if (templatesOffered)
                            SegmentItem(
                              label: templates.isEmpty
                                  ? context.t('projects.templates')
                                  : '${context.t('projects.templates')} · ${templates.length}',
                              icon: LucideIcons.copy,
                            ),
                          SegmentItem(
                            label: archived.isEmpty
                                ? context.t('projects.archived')
                                : '${context.t('projects.archived')} · ${archived.length}',
                            icon: LucideIcons.archive,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (state.isLoading && projects.isEmpty)
                  const SliverFillRemaining(child: Center(child: HiveLoader()))
                else if (projects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.pageGutter,
                        vertical: 24,
                      ),
                      child: Center(
                        child: HiveEmptyState(
                          title: context.t('projects.title'),
                          message: switch (tab) {
                            _ProjectTab.archived => context.t(
                              'projects.emptyArchived',
                            ),
                            _ProjectTab.templates => context.t(
                              'projects.emptyTemplates',
                            ),
                            _ProjectTab.active => context.t('projects.empty'),
                          },
                        ),
                      ),
                    ),
                  )
                else
                  SliverLayoutBuilder(
                    builder: (context, room) => SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        context.pageGutter,
                        0,
                        context.pageGutter,
                        context.pageGutter + context.bottomGutter,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: context.gridColumns(
                            minTileWidth: 300,
                            width: room.crossAxisExtent,
                          ),
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 18,
                          mainAxisExtent: 210,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _ProjectCard(
                            project: projects[index],
                            names: names,
                            avatars: avatars,
                            onSettings: () => _openSettings(projects[index]),
                            onCopy: templatesOffered
                                ? () => _copy(projects[index])
                                : null,
                            onInstantiate:
                                templatesOffered && projects[index].template
                                ? () => _instantiate(projects[index])
                                : null,
                          ),
                          childCount: projects.length,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Keys of the projects this user can see — archived ones included, since
  /// they hold their key too. What the create dialog steps around when it
  /// suggests one.
  Set<String> _takenProjectKeys() {
    final data = _cubit.state.data;
    if (data == null) return const {};
    return {
      for (final p in [...data.active, ...data.archived]) p.key.toUpperCase(),
    };
  }

  Future<void> _showCreate() async {
    final projects = context.read<ProjectRepository>();
    final users = context.read<UserRepository>();
    final meId = context.read<AuthBloc>().state.user?.id;
    final created = await showGlassModal<Project>(
      context,
      width: 580,
      builder: (modalContext) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: projects),
          RepositoryProvider.value(value: users),
        ],
        child: _CreateProjectBody(meId: meId, takenKeys: _takenProjectKeys()),
      ),
    );
    if (created != null) _cubit.load();
  }

  Future<void> _openSettings(Project project) async {
    await context.push('/projects/${project.id}/settings');
    if (mounted) _cubit.load();
  }

  /// Where a tab sits in the control, which is one place to the left when
  /// templates are not offered.
  int _tabIndex(_ProjectTab tab, bool templatesOffered) => switch (tab) {
    _ProjectTab.active => 0,
    _ProjectTab.templates => 1,
    _ProjectTab.archived => templatesOffered ? 2 : 1,
  };

  _ProjectTab _tabAt(int index, bool templatesOffered) {
    if (index == 0) return _ProjectTab.active;
    if (!templatesOffered) return _ProjectTab.archived;
    return index == 1 ? _ProjectTab.templates : _ProjectTab.archived;
  }

  Future<void> _copy(Project project) =>
      _copyThrough(project, ProjectCopyMode.copy);

  Future<void> _instantiate(Project project) =>
      _copyThrough(project, ProjectCopyMode.instantiate);

  /// Opens the sheet, and on success lands in the new project's issues with a
  /// toast saying what came along.
  Future<void> _copyThrough(Project project, ProjectCopyMode mode) async {
    final result = await showProjectCopySheet(
      context,
      source: project,
      mode: mode,
    );
    if (result == null || !mounted) return;
    _cubit.load();
    showGlassToast(
      context,
      context.t(
        'projects.copy.done',
        variables: {
          'issues': '${result.issuesCopied}',
          'deadlines': '${result.deadlinesSet}',
        },
      ),
    );
    if (mounted) context.go('/issues?projectId=${result.project.id}');
  }
}

/// The three lists the projects page holds.
enum _ProjectTab { active, templates, archived }

/// Parses a project's stored hex color (e.g. "#AEC6F4") to a Color, with a
/// stable hue fallback derived from the project key.
Color _projectColor(Project project) {
  final raw = project.color.replaceAll('#', '').trim();
  if (raw.length == 6) {
    final value = int.tryParse(raw, radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  return hiveHueColor(project.key);
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.names,
    required this.avatars,
    required this.onSettings,
    this.onCopy,
    this.onInstantiate,
  });

  final Project project;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final VoidCallback onSettings;

  /// Null while project templates are switched off: then there is no way to
  /// copy a project and the entry does not exist.
  final VoidCallback? onCopy;

  /// Only on a template, and the first thing offered there.
  final VoidCallback? onInstantiate;

  @override
  Widget build(BuildContext context) {
    // Mobile shows the compact gear in the corner; larger views show the
    // full-width "Settings" button in the footer instead.
    final compact = context.isCompact;
    // Only project leads (and platform admins) may open project settings —
    // regular members work on the project but never see its configuration.
    final me = context.read<AuthBloc>().state.user;
    final canManage =
        me != null && (me.isAdmin || project.leadIds.contains(me.id));
    final color = _projectColor(project);
    final glyphColor = project.archived
        ? HSLColor.fromColor(color).withSaturation(0.25).toColor()
        : color;
    final leadName = project.leadId != null ? names[project.leadId!] : null;
    final memberNames = project.memberIds
        .map((id) => names[id] ?? id)
        .toList(growable: false);
    final memberAvatars = project.memberIds
        .map((id) => avatars[id])
        .toList(growable: false);
    final subtitle = leadName != null
        ? '${project.key} · ${context.t('projects.lead')} ${leadName.split(' ').first}'
        : project.key;

    final card = SoftCard(
      onTap: () => context.go('/issues?projectId=${project.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The project's picture when it has one, the mono-key square
              // otherwise — same 44px footprint either way, so the card's
              // header row never shifts.
              EntityAvatar(
                avatarUrl: project.avatarUrl,
                size: 44,
                radius: 12,
                fallback: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.soft(glyphColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    project.key,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: glyphColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leave room for the corner gear only when it's shown.
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: compact && canManage ? 26 : 0,
                      ),
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11.5,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ),
                        if (project.template) ...[
                          const SizedBox(width: 6),
                          _TemplateBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(
                value: '${project.memberIds.length}',
                label: context.t('projects.membersLabel'),
              ),
              const SizedBox(width: 20),
              _Stat(
                value: '${project.workflowStates.length}',
                label: context.t('projects.statesLabel'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HiveProgress(value: _completion(project), color: glyphColor),
          const Spacer(),
          const SizedBox(height: 12),
          Row(
            children: [
              if (memberNames.isNotEmpty)
                Expanded(
                  child: HiveAvatarStack(
                    names: memberNames,
                    imageUrls: memberAvatars,
                    size: 26,
                  ),
                )
              else
                const Spacer(),
              if (project.labels.isNotEmpty) ...[
                Icon(LucideIcons.tag, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 4),
                Text(
                  '${project.labels.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (onInstantiate != null)
                _CardAction(
                  icon: LucideIcons.sparkles,
                  label: context.t('projects.copy.fromTemplateShort'),
                  onTap: onInstantiate!,
                  primary: true,
                )
              else if (onCopy != null && !compact)
                _CardAction(
                  icon: LucideIcons.copy,
                  label: context.t('projects.copy.short'),
                  onTap: onCopy!,
                ),
              if ((onInstantiate != null || (onCopy != null && !compact)) &&
                  !compact &&
                  canManage)
                const SizedBox(width: 8),
              if (!compact && canManage) _SettingsButton(onTap: onSettings),
            ],
          ),
        ],
      ),
    );

    final stacked = Stack(
      children: [
        card,
        if (compact && canManage)
          Positioned(top: 10, right: 10, child: _GearButton(onTap: onSettings)),
      ],
    );

    return project.archived ? Opacity(opacity: 0.82, child: stacked) : stacked;
  }

  // Resolved-state ratio gives a rough completion proxy when no counts exist.
  double _completion(Project project) {
    if (project.workflowStates.isEmpty) return 0.0;
    return (project.resolvedStates.length / project.workflowStates.length)
        .clamp(0.0, 1.0);
  }
}

/// Small gear affordance in the card corner that opens project settings.
class _GearButton extends StatelessWidget {
  const _GearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(LucideIcons.settings, size: 15, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

/// Footer "Settings" ghost button on each project card.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 14,
                color: AppColors.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                context.t('projects.settings'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
      ],
    );
  }
}

/// "New project" creation modal, rendered on the app's Liquid Glass material
/// (same as the sprint/team modals) and matching the design: glyph + name/key,
/// description, lead, accent color and the default-workflow note.
class _CreateProjectBody extends StatefulWidget {
  const _CreateProjectBody({required this.meId, this.takenKeys = const {}});

  final String? meId;

  /// Keys already in use, so the suggested one doesn't walk into a conflict the
  /// server would only report after the form is submitted. Best effort — the
  /// server stays the authority (it answers 409 for a key this list missed).
  final Set<String> takenKeys;

  @override
  State<_CreateProjectBody> createState() => _CreateProjectBodyState();
}

class _CreateProjectBodyState extends State<_CreateProjectBody> {
  late final ProjectDraft _draft = ProjectDraft(
    takenKeys: widget.takenKeys,
    meId: widget.meId,
  );

  bool _saving = false;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.folderPlus,
          title: context.t('projects.new'),
          subtitle: context.t('projects.newSubtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProjectCreateFields(draft: _draft),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.create'),
          confirmIcon: LucideIcons.check,
          busy: _saving,
          onConfirm: _draft.valid ? _save : null,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_draft.valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<ProjectRepository>();
      final project = await repo.createProject(
        key: _draft.trimmedKey,
        name: _draft.trimmedName,
        description: _draft.trimmedDescription,
        color: _draft.colorHex,
        leadId: _draft.lead?.id,
      );
      if (mounted) {
        await uploadPendingAvatar(
          context,
          _draft.pendingAvatar,
          EntityAvatarStrings.project,
          (file) => repo.uploadProjectAvatar(project.id, file),
        );
      }
      if (mounted) Navigator.of(context).pop(project);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}

/// The small "template" mark on a project card.
///
/// The section a card sits in already says it, but a card also turns up in a
/// search result and in a picker, where the section does not travel with it.
class _TemplateBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Text(
        context.t('projects.templateBadge'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// A ghost action in a project card's footer, beside the settings button.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The one action a card leads with — "create a project from this" on a
  /// template. Drawn filled so it reads as the thing to do.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.navy : AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: primary ? AppColors.navy : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: primary ? Colors.white : AppColors.inkSoft,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primary ? Colors.white : AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
