import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart'
    show GhostButton, HiveAvatarStack;
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import 'settings_common.dart';
import 'shift_planners_cubit.dart';

/// Project settings → Schichtplanung (HIN-45): the people who plan this
/// project's shifts besides its leads and team admins, a way to add one from
/// the members, and a way to take the right back.
///
/// Only on the page while `shift_planning` is on; the page itself is for the
/// people who manage the project, the same ones the server lets grant.
class ShiftPlannersSection extends StatelessWidget {
  const ShiftPlannersSection({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.members,
    required this.leadIds,
  });

  final String projectId;
  final String projectName;

  /// The project's members, the people a planner can be chosen from.
  final List<DirectoryUser> members;

  /// Leads plan anyway and are not offered.
  final List<String> leadIds;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        ShiftPlannersCubit(context.read<ShiftRepository>(), projectId)..load(),
    child: _Section(
      projectName: projectName,
      members: members,
      leadIds: leadIds,
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.projectName,
    required this.members,
    required this.leadIds,
  });

  final String projectName;
  final List<DirectoryUser> members;
  final List<String> leadIds;

  Future<void> _add(BuildContext context) async {
    final cubit = context.read<ShiftPlannersCubit>();
    final current = {
      for (final p in cubit.state.planners?.planners ?? const []) p.userId,
    };
    final candidates = [
      for (final m in members)
        if (!current.contains(m.id) && !leadIds.contains(m.id)) m,
    ];
    if (candidates.isEmpty) {
      showGlassToast(context, context.t('projectSettings.shifts.noCandidates'));
      return;
    }
    final picked = await showMemberPicker(
      context,
      candidates: candidates,
      projectName: projectName,
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    final error = await cubit.add(picked);
    if (!context.mounted) return;
    _say(context, error, 'projectSettings.shifts.added');
  }

  Future<void> _remove(BuildContext context, String userId, String name) async {
    final cubit = context.read<ShiftPlannersCubit>();
    final sure = await showGlassConfirm(
      context,
      icon: LucideIcons.userMinus,
      title: context.t('projectSettings.shifts.removeTitle'),
      message: context.t(
        'projectSettings.shifts.removeMessage',
        variables: {'name': name},
      ),
      confirmLabel: context.t('projectSettings.shifts.remove'),
      confirmIcon: LucideIcons.userMinus,
      destructive: true,
    );
    if (sure != true || !context.mounted) return;
    final error = await cubit.remove(userId);
    if (!context.mounted) return;
    _say(context, error, 'projectSettings.shifts.removed');
  }

  void _say(BuildContext context, String? error, String done) {
    if (error != null) {
      showGlassToast(context, context.t(error), kind: GlassToastKind.error);
    } else {
      showGlassToast(context, context.t(done), kind: GlassToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftPlannersCubit>().state;
    final planners = state.planners;
    final byId = {for (final m in members) m.id: m};
    return SettingsSection(
      title: context.t('projectSettings.shifts.title'),
      note: context.t('projectSettings.shifts.note'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (planners == null && state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: HiveLoader(size: 28)),
            )
          else if (planners == null)
            Text(
              context.t(state.errorKey ?? 'errors.unexpected'),
              style: TextStyle(
                fontSize: AppType.label,
                color: AppColors.inkSoft,
              ),
            )
          else if (planners.planners.isEmpty)
            Text(
              context.t('projectSettings.shifts.empty'),
              style: TextStyle(
                fontSize: AppType.label,
                color: AppColors.inkSoft,
              ),
            )
          else
            for (final planner in planners.planners)
              _PlannerRow(
                name:
                    planners.users[planner.userId]?.name ??
                    byId[planner.userId]?.displayName ??
                    context.t('time.deletedUser'),
                avatarUrl:
                    planners.users[planner.userId]?.avatarUrl ??
                    byId[planner.userId]?.avatarUrl,
                busy: state.busy,
                onRemove: (name) =>
                    unawaited(_remove(context, planner.userId, name)),
              ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GhostButton(
              icon: LucideIcons.userPlus,
              label: context.t('projectSettings.shifts.add'),
              onPressed: state.busy || planners == null
                  ? null
                  : () => unawaited(_add(context)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.t('projectSettings.shifts.leadsAlways'),
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannerRow extends StatelessWidget {
  const _PlannerRow({
    required this.name,
    required this.avatarUrl,
    required this.busy,
    required this.onRemove,
  });

  final String name;
  final String? avatarUrl;
  final bool busy;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        ExcludeSemantics(
          child: HiveAvatarStack(
            names: [name],
            imageUrls: [avatarUrl],
            size: 30,
            max: 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
          ),
        ),
        IconButton(
          tooltip: context.t(
            'projectSettings.shifts.removeNamed',
            variables: {'name': name},
          ),
          icon: Icon(LucideIcons.userMinus, size: 18, color: AppColors.inkSoft),
          onPressed: busy ? null : () => onRemove(name),
        ),
      ],
    ),
  );
}
