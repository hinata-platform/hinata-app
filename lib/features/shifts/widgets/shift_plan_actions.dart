/// The planner's actions as the screens start them (HIN-160): put somebody on
/// a shift, take somebody off, delete a shift, call an event off or delete
/// it. Each asks first where it cannot be undone and says how it went.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/auth_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart' show DirectoryUser;
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/project_repository.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../../core/widgets/person_picker.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import '../bloc/shift_assignees.dart';
import '../bloc/shift_planning_cubit.dart';
import 'series_scope_dialog.dart';
import 'shift_plan_texts.dart';

/// Says how a planner action went.
void announcePlanOutcome(BuildContext context, ShiftPlanOutcome outcome) {
  final error = outcome.errorKey;
  if (error != null) {
    showGlassToast(
      context,
      planErrorText(context, error, outcome.errorDetails),
      kind: GlassToastKind.error,
    );
    return;
  }
  final overlaps = overlapNotice(context, outcome.warnings);
  if (outcome.absent || overlaps != null) {
    showGlassToast(
      context,
      [
        context.t(outcome.messageKey!),
        if (outcome.absent) context.t('shifts.plan.absentHint'),
        ?overlaps,
      ].join('. '),
      kind: GlassToastKind.warning,
    );
    return;
  }
  showGlassToast(
    context,
    context.t(outcome.messageKey!),
    kind: GlassToastKind.success,
  );
}

/// Opens the people of [shift]'s project at [anchor] ("Mich eintragen" first,
/// those on it already greyed out) and puts the one picked on the shift.
Future<ShiftPlanOutcome?> assignToShift(
  BuildContext context,
  Shift shift, {
  required Rect anchor,
}) async {
  final planning = context.read<ShiftPlanningCubit>();
  final me = context.read<AuthBloc>().state.user;
  final search = ShiftAssignees(
    context.read<ProjectRepository>(),
    context.read<UserRepository>(),
    shift.projectId,
  );
  final picked = await showPersonPicker(
    context,
    anchorRect: anchor,
    meId: me?.id,
    search: search.search,
    first: me == null || shift.assigneeIds.contains(me.id)
        ? null
        : (
            user: DirectoryUser(
              id: me.id,
              username: me.username,
              displayName: me.displayName,
            ),
            label: context.t('shifts.plan.assignMe'),
          ),
    disabledIds: {...shift.assigneeIds, if (shift.mine) ?me?.id},
    disabledLabel: context.t('shifts.plan.alreadyOn'),
  );
  if (picked == null || !context.mounted) return null;
  final outcome = await planning.assign(shift, picked.id);
  if (context.mounted) announcePlanOutcome(context, outcome);
  return outcome;
}

/// Takes [name] (holding [place]) off [shift], after asking.
Future<ShiftPlanOutcome?> removeFromShift(
  BuildContext context,
  Shift shift,
  ShiftPlace place,
  String name,
) async {
  final planning = context.read<ShiftPlanningCubit>();
  final sure = await showGlassConfirm(
    context,
    icon: LucideIcons.userMinus,
    title: context.t('shifts.plan.removeTitle'),
    message: context.t(
      'shifts.plan.removeMessage',
      variables: {'name': name, 'shift': shift.title},
    ),
    confirmLabel: context.t('shifts.plan.remove'),
    confirmIcon: LucideIcons.userMinus,
    destructive: true,
  );
  if (sure != true || !context.mounted) return null;
  final outcome = await planning.remove(shift, place);
  if (context.mounted) announcePlanOutcome(context, outcome);
  return outcome;
}

/// Deletes [shift], after asking. True when it is gone. On an occurrence of
/// a series ([event]) the question is which occurrences it goes from.
Future<bool> deleteShiftAsking(
  BuildContext context,
  Shift shift, {
  ShiftEventHead? event,
}) async {
  final planning = context.read<ShiftPlanningCubit>();
  if (event != null && event.inSeries) {
    final scope = await askSeriesScope(
      context,
      write: SeriesWrite.deleteShift,
      day: shift.startsLocal,
      recurrenceLabel: event.recurrenceLabel,
      note: shift.assignedCount > 0
          ? context.t(
              'shifts.plan.deleteShiftPeople',
              count: shift.assignedCount,
              variables: {'shift': shift.title},
            )
          : null,
    );
    if (scope == null || !context.mounted) return false;
    final outcome = await planning.deleteShift(shift, scope: scope);
    if (context.mounted) announcePlanOutcome(context, outcome);
    return outcome.ok;
  }
  final sure = await showGlassConfirm(
    context,
    icon: LucideIcons.trash2,
    title: context.t('shifts.plan.deleteShiftTitle'),
    message: context.t(
      shift.assignedCount > 0
          ? 'shifts.plan.deleteShiftPeople'
          : 'shifts.plan.deleteShiftMessage',
      count: shift.assignedCount,
      variables: {'shift': shift.title},
    ),
    confirmLabel: context.t('shifts.plan.delete'),
    confirmIcon: LucideIcons.trash2,
    destructive: true,
  );
  if (sure != true || !context.mounted) return false;
  final outcome = await planning.deleteShift(shift);
  if (context.mounted) announcePlanOutcome(context, outcome);
  return outcome.ok;
}

/// The planner's one button on a shift row: "Zuteilen".
class AssignButton extends StatelessWidget {
  const AssignButton({super.key, required this.shift, this.onDone});

  final Shift shift;
  final void Function(ShiftPlanOutcome outcome)? onDone;

  @override
  Widget build(BuildContext context) {
    final busy = context.select<ShiftPlanningCubit, bool>(
      (cubit) => cubit.state.isBusy(shift.id),
    );
    return Builder(
      builder: (anchorContext) => GhostButton(
        label: context.t('shifts.plan.assign'),
        icon: LucideIcons.userPlus,
        onPressed: busy
            ? null
            : () {
                final box = anchorContext.findRenderObject() as RenderBox?;
                final anchor = box == null || !box.hasSize
                    ? Rect.zero
                    : box.localToGlobal(Offset.zero) & box.size;
                unawaited(
                  assignToShift(context, shift, anchor: anchor).then((o) {
                    if (o != null && o.ok) onDone?.call(o);
                  }),
                );
              },
      ),
    );
  }
}
