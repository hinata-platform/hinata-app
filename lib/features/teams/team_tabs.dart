import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hinata_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import 'team_detail_screen.dart' show TeamDetailData;
import 'team_modals.dart';
import 'team_widgets.dart';

// ─────────────────────────── modal launchers ──────────────────────────────
// Shared by the header actions and the per-tab buttons. Each reloads on success.

Future<void> openAddMembers(
  BuildContext context,
  TeamDetailData data,
  Future<void> Function() reload,
) async {
  final inTeam = data.team.members.map((m) => m.userId).toSet();
  final candidates =
      data.usersById.values.where((u) => !inTeam.contains(u.id)).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
  final changed = await showAddMembersModal(
    context,
    team: data.team,
    candidates: candidates,
    projectsById: data.projectsById,
  );
  if (changed == true) await reload();
}

Future<void> openAddProject(
  BuildContext context,
  TeamDetailData data,
  Future<void> Function() reload,
) async {
  final available =
      data.projectsById.values
          .where((p) => !data.team.projectIds.contains(p.id))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  // Team members first, then everyone else — matches the reference lead pool.
  final memberIds = data.team.members.map((m) => m.userId).toList();
  final leadPool = <DirectoryUser>[
    for (final id in memberIds)
      if (data.usersById[id] != null) data.usersById[id]!,
    for (final u in data.usersById.values)
      if (!memberIds.contains(u.id)) u,
  ];
  final me = context.read<AuthBloc>().state.user;
  final changed = await showAddProjectModal(
    context,
    team: data.team,
    available: available,
    leadCandidates: leadPool,
    currentUserId: me?.id ?? (memberIds.isNotEmpty ? memberIds.first : ''),
  );
  if (changed == true) await reload();
}

Future<void> _openManageMember(
  BuildContext context,
  TeamDetailData data,
  TeamMembership membership,
  Future<void> Function() reload,
) async {
  final user =
      data.usersById[membership.userId] ??
      DirectoryUser(
        id: membership.userId,
        username: '',
        displayName: membership.userId,
      );
  final me = context.read<AuthBloc>().state.user;
  final changed = await showManageMemberModal(
    context,
    team: data.team,
    membership: membership,
    user: user,
    projectsById: data.projectsById,
    isSelf: me?.id == membership.userId,
  );
  if (changed == true) await reload();
}

// Progress proxy from the project's resolved/workflow ratio (no extra query).
double _progress(Project p) {
  if (p.workflowStates.isEmpty) return 0;
  return (p.resolvedStates.length / p.workflowStates.length).clamp(0.0, 1.0);
}

// ═══════════════════════════════ Overview ═════════════════════════════════

class TeamOverviewTab extends StatelessWidget {
  const TeamOverviewTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
    required this.onGotoProjects,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;
  final VoidCallback onGotoProjects;

  @override
  Widget build(BuildContext context) {
    final team = data.team;
    final projects = team.projectIds
        .map((id) => data.projectsById[id])
        .whereType<Project>()
        .toList();
    final kpis = [
      TeamKpi(
        icon: LucideIcons.users,
        value: '${team.members.length}',
        label: context.t('teams.kpiMembers'),
        hue: 250,
      ),
      TeamKpi(
        icon: LucideIcons.shieldCheck,
        value: '${team.adminCount}',
        label: context.t('teams.kpiAdmins'),
        hue: 70,
      ),
      TeamKpi(
        icon: LucideIcons.folder,
        value: '${team.projectIds.length}',
        label: context.t('teams.kpiProjects'),
        hue: 200,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            // Let each card size to its own content so text/scale changes never
            // clip — a fixed grid aspect ratio overflowed on phones.
            if (c.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < kpis.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    kpis[i],
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < kpis.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(child: kpis[i]),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 720;
            final projectsCard = _ProjectsMiniCard(
              data: data,
              projects: projects,
              manage: manage,
              onReload: onReload,
              onViewAll: onGotoProjects,
            );
            final activityCard = _ActivityCard(data: data);
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  projectsCard,
                  const SizedBox(height: 16),
                  activityCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: projectsCard),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: activityCard),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProjectsMiniCard extends StatelessWidget {
  const _ProjectsMiniCard({
    required this.data,
    required this.projects,
    required this.manage,
    required this.onReload,
    required this.onViewAll,
  });

  final TeamDetailData data;
  final List<Project> projects;
  final bool manage;
  final Future<void> Function() onReload;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: context.t('teams.tabProjects'),
            actionLabel: projects.isEmpty ? null : context.t('teams.viewAll'),
            onAction: projects.isEmpty ? null : onViewAll,
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                context.t('teams.noProjectsYet'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
              ),
            )
          else
            for (var i = 0; i < projects.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _MiniProjectRow(project: projects[i]),
            ],
        ],
      ),
    );
  }
}

class _MiniProjectRow extends StatelessWidget {
  const _MiniProjectRow({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final color = projectHexColor(project.color);
    return Row(
      children: [
        ProjectKeyGlyph(label: project.key, color: color, size: 36, radius: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              HiveProgress(value: _progress(project), color: color),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.data});
  final TeamDetailData data;

  @override
  Widget build(BuildContext context) {
    final acts = data.activity;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: context.t('teams.recentActivity')),
          const SizedBox(height: 12),
          if (acts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                context.t('teams.noActivity'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
              ),
            )
          else
            for (var i = 0; i < acts.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _ActivityRow(activity: acts[i], data: data),
            ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, required this.data});
  final TeamActivity activity;
  final TeamDetailData data;

  @override
  Widget build(BuildContext context) {
    final actorName =
        data.usersById[activity.actorId]?.displayName.split(' ').first ?? '—';
    // For member verbs the objectLabel is a userId; resolve it to a name.
    final memberVerb = const {
      'ADDED_MEMBER',
      'PROMOTED',
      'DEMOTED',
      'REMOVED_MEMBER',
    }.contains(activity.verb);
    final object = memberVerb
        ? (data.usersById[activity.objectLabel]?.displayName ??
              activity.objectLabel ??
              '')
        : (activity.objectLabel ?? '');
    final verbText = context.t('teams.activity.${_verbKey(activity.verb)}');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HiveAvatar(name: actorName, size: 28),
        const SizedBox(width: 11),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.inkSoft,
              ),
              children: [
                TextSpan(
                  text: actorName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                TextSpan(text: ' $verbText '),
                TextSpan(
                  text: object,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
                if ((activity.extra ?? '').isNotEmpty)
                  TextSpan(text: ' ${activity.extra}'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _ago(activity.createdAt),
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11,
            color: AppColors.inkFaint,
          ),
        ),
      ],
    );
  }

  String _verbKey(String verb) => switch (verb) {
    'CREATED' => 'created',
    'UPDATED' => 'updated',
    'ADDED_MEMBER' => 'addedMember',
    'PROMOTED' => 'promoted',
    'DEMOTED' => 'demoted',
    'REMOVED_MEMBER' => 'removedMember',
    'ATTACHED_PROJECT' => 'attachedProject',
    'CREATED_PROJECT' => 'createdProject',
    'DETACHED_PROJECT' => 'detachedProject',
    _ => 'updated',
  };

  String _ago(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}

// ═══════════════════════════════ Members ══════════════════════════════════

class TeamMembersTab extends StatelessWidget {
  const TeamMembersTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AuthBloc>().state.user?.id;
    final members = [...data.team.members]
      ..sort((a, b) {
        if (a.isAdmin == b.isAdmin) return 0;
        return a.isAdmin ? -1 : 1;
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(
                  'teams.membersSummary',
                  variables: {
                    'members': '${data.team.members.length}',
                    'admins': '${data.team.adminCount}',
                  },
                ),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            if (manage)
              GhostButton(
                label: context.t('teams.addMembers'),
                icon: LucideIcons.userPlus,
                onPressed: () => openAddMembers(context, data, onReload),
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < members.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _MemberRow(
            data: data,
            membership: members[i],
            isSelf: members[i].userId == myId,
            manage: manage,
            onManage: () =>
                _openManageMember(context, data, members[i], onReload),
          ),
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.data,
    required this.membership,
    required this.isSelf,
    required this.manage,
    required this.onManage,
  });

  final TeamDetailData data;
  final TeamMembership membership;
  final bool isSelf;
  final bool manage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final user = data.usersById[membership.userId];
    final name = user?.displayName ?? membership.userId;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 460;
          final identity = Row(
            children: [
              HiveAvatar(name: name, size: 38),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              context.t('teams.you'),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: AppColors.accentStrong,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((user?.title ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user!.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final tags = Wrap(
            spacing: 9,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RoleBadge(role: membership.role),
              AccessChip(team: data.team, membership: membership),
            ],
          );

          final kebab = manage
              ? IconButton(
                  onPressed: onManage,
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t('teams.manage'),
                  icon: Icon(
                    LucideIcons.slidersHorizontal,
                    size: 18,
                    color: AppColors.inkSoft,
                  ),
                )
              : const SizedBox(width: 8);

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: identity),
                    kebab,
                  ],
                ),
                const SizedBox(height: 10),
                tags,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              tags,
              const SizedBox(width: 6),
              kebab,
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════ Projects ═════════════════════════════════

class TeamProjectsTab extends StatelessWidget {
  const TeamProjectsTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  Future<void> _detach(BuildContext context, Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t('teams.detachTitle')),
        content: Text(
          context.t('teams.detachConfirm', variables: {'name': project.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('teams.detach')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repo = context.read<HinataRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final errText = context.t('errors.unexpected');
    try {
      await repo.detachTeamProject(data.team.id, project.id);
      await onReload();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(errText)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = data.team.projectIds
        .map((id) => data.projectsById[id])
        .whereType<Project>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(
                  'teams.projectsSummary',
                  variables: {'count': '${data.team.projectIds.length}'},
                  count: data.team.projectIds.length,
                ),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            if (manage)
              GhostButton(
                label: context.t('teams.addProject'),
                icon: LucideIcons.folderPlus,
                onPressed: () => openAddProject(context, data, onReload),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (projects.isEmpty)
          SoftCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.t('teams.noProjectsYet'),
                  style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < projects.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ProjectRow(
              data: data,
              project: projects[i],
              manage: manage,
              onDetach: () => _detach(context, projects[i]),
            ),
          ],
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.data,
    required this.project,
    required this.manage,
    required this.onDetach,
  });

  final TeamDetailData data;
  final Project project;
  final bool manage;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    final color = projectHexColor(project.color);
    final lead = project.leadId != null
        ? data.usersById[project.leadId!]
        : null;
    // Members whose access covers this project.
    final withAccess = data.team.members
        .where((m) {
          final a = m.access;
          if (m.isAdmin || a.scope == AccessScope.all) return true;
          if (a.scope == AccessScope.some) {
            return a.projectIds.contains(project.id);
          }
          return false;
        })
        .map((m) => data.usersById[m.userId]?.displayName ?? m.userId)
        .toList();

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 540;
          final identity = Row(
            children: [
              ProjectKeyGlyph(
                label: project.key,
                color: color,
                size: 40,
                radius: 11,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (lead != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.t(
                          'teams.leadName',
                          variables: {
                            'name': lead.displayName.split(' ').first,
                          },
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (withAccess.isNotEmpty)
                HiveAvatarStack(names: withAccess, size: 24, max: 3),
              if (manage) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onDetach,
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t('teams.detach'),
                  icon: Icon(
                    LucideIcons.unlink,
                    size: 18,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 10),
                HiveProgress(value: _progress(project), color: color),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 14),
              SizedBox(
                width: 120,
                child: HiveProgress(value: _progress(project), color: color),
              ),
              const SizedBox(width: 14),
              trailing,
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════ Settings ═════════════════════════════════

class TeamSettingsTab extends StatelessWidget {
  const TeamSettingsTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  Future<void> _edit(BuildContext context) async {
    final saved = await showEditTeamModal(context, data.team);
    if (saved == true) await onReload();
  }

  Future<void> _delete(BuildContext context) async {
    final deleted = await showDeleteTeamModal(context, data.team);
    // Go to a fresh teams overview so the deleted team is gone from the list.
    if (deleted == true && context.mounted) context.go('/teams');
  }

  @override
  Widget build(BuildContext context) {
    if (!manage) {
      return SoftCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(LucideIcons.lock, size: 26, color: AppColors.inkSoft),
              const SizedBox(height: 10),
              Text(
                context.t('teams.adminsOnly'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.t('teams.adminsOnlyHint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      );
    }
    final team = data.team;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: context.t('teams.identity'),
                actionLabel: context.t('common.edit'),
                onAction: () => _edit(context),
              ),
              const SizedBox(height: 8),
              _SettingRow(k: context.t('teams.name'), v: team.name),
              _SettingRow(k: context.t('teams.key'), v: team.key, mono: true),
              _SettingRow(
                k: context.t('teams.description'),
                v: (team.description ?? '').isEmpty ? '—' : team.description!,
              ),
              _SettingRow(
                k: context.t('teams.colorLabel'),
                vWidget: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: teamHueColor(team.colorHue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hueName(context, team.colorHue),
                      style: TextStyle(fontSize: 13, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: context.t('teams.rolesPermissions')),
              const SizedBox(height: 6),
              _PermRow(
                icon: LucideIcons.shieldCheck,
                title: context.t('teams.role.admin'),
                body: context.t(
                  'teams.permAdmin',
                  variables: {'name': team.name},
                ),
              ),
              const SizedBox(height: 12),
              _PermRow(
                icon: LucideIcons.user,
                title: context.t('teams.role.member'),
                body: context.t('teams.permMember'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('teams.dangerZone'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 460;
                  final text = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.t('teams.deleteThis'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.t('teams.deleteThisHint'),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  );
                  final btn = FilledButton.icon(
                    onPressed: () => _delete(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
                      ),
                    ),
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: Text(context.t('teams.deleteCta')),
                  );
                  return narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [text, const SizedBox(height: 12), btn],
                        )
                      : Row(
                          children: [
                            Expanded(child: text),
                            const SizedBox(width: 16),
                            btn,
                          ],
                        );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _hueName(BuildContext context, int hue) {
    for (final s in teamSwatches) {
      if (s.hue == hue) return context.t(s.nameKey);
    }
    return context.t('teams.color.custom');
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.k, this.v, this.vWidget, this.mono = false});
  final String k;
  final String? v;
  final Widget? vWidget;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child:
                vWidget ??
                Text(
                  v ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: mono ? AppTheme.fontMono : null,
                    color: AppColors.ink,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.accentStrong),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
