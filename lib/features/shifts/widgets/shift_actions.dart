/// The helper's actions in one place (HIN-44, HIN-162): which of them a shift
/// offers, the button that runs it, and what is said afterwards.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_widgets.dart'
    show GhostButton, PrimaryButton;
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import '../bloc/shift_actions_cubit.dart';
import 'shift_status_badge.dart';

/// One thing a helper can do with a shift.
enum ShiftAction {
  join(LucideIcons.plus, 'shifts.action.join'),
  confirm(LucideIcons.check, 'shifts.action.confirm'),
  decline(LucideIcons.x, 'shifts.action.decline'),
  release(LucideIcons.logOut, 'shifts.action.release'),

  /// Onto the waiting list of a full shift (HIN-162).
  waitlistJoin(LucideIcons.listPlus, 'shifts.action.waitlistJoin'),

  /// Off the waiting list again.
  waitlistLeave(LucideIcons.listX, 'shifts.action.waitlistLeave');

  const ShiftAction(this.icon, this.labelKey);

  final IconData icon;
  final String labelKey;
}

/// What a shift offers the person looking at it, after HIN-45's table: at
/// most one [primary] action, a quieter [secondary] one, or a [noteKey] said
/// in words where there is nothing to press.
class ShiftOffer {
  const ShiftOffer({this.primary, this.secondary, this.noteKey});

  final ShiftAction? primary;
  final ShiftAction? secondary;

  /// `shifts.offer.*`: why there is no button (full, closed, cancelled).
  final String? noteKey;

  bool get isEmpty => primary == null && secondary == null && noteKey == null;
}

/// Decides [ShiftOffer] for [shift], held by the caller with [status] (null
/// when it is not theirs), on an event that does or does not take sign-ups.
///
/// [promoted]: the place came off the waiting list (HIN-162), so the quiet
/// way out is giving it up again, not declining a planner's choice. A shift
/// the caller waits for offers leaving the list; a full one, or one somebody
/// already waits for, offers joining the list where sign-ups are open.
ShiftOffer shiftOfferFor(
  Shift shift, {
  ShiftAssignmentStatus? status,
  bool selfAssignable = true,
  bool eventCancelled = false,
  bool promoted = false,
}) {
  final held = status ?? (shift.mine ? shift.myStatus : null);
  if (held == ShiftAssignmentStatus.assigned) {
    return ShiftOffer(
      primary: ShiftAction.confirm,
      secondary: promoted ? ShiftAction.release : ShiftAction.decline,
    );
  }
  if (held == ShiftAssignmentStatus.confirmed) {
    return const ShiftOffer(secondary: ShiftAction.release);
  }
  if (shift.mine) {
    // On it, but the answer did not say how: nothing to press here, the
    // place is in "Meine Schichten".
    return const ShiftOffer();
  }
  if (shift.cancelled || eventCancelled) {
    return const ShiftOffer(noteKey: 'shifts.offer.cancelled');
  }
  if (shift.waiting) {
    return const ShiftOffer(secondary: ShiftAction.waitlistLeave);
  }
  final full = shift.coverage.state == CoverageState.full;
  if (selfAssignable && (full || shift.waitingCount > 0)) {
    return const ShiftOffer(secondary: ShiftAction.waitlistJoin);
  }
  if (full) {
    return const ShiftOffer(noteKey: 'shifts.offer.full');
  }
  if (!selfAssignable) {
    return const ShiftOffer(noteKey: 'shifts.offer.plannersOnly');
  }
  return const ShiftOffer(primary: ShiftAction.join);
}

/// `Warteliste, Platz 2 von 3` for the caller waiting for [shift], or null.
String? waitlistPositionLabel(BuildContext context, Shift shift) {
  final pos = shift.myWaitPosition;
  if (pos == null) return null;
  return context.t(
    'shifts.waitlist.position',
    variables: {
      'pos': pos,
      'total': shift.waitingCount < pos ? pos : shift.waitingCount,
    },
  );
}

/// The text of [ShiftOffer.noteKey] for [shift].
String shiftOfferNote(BuildContext context, String key, Shift shift) =>
    context.t(
      key,
      variables: {
        'assigned': shift.assignedCount,
        'max': shift.maxHelpers ?? shift.assignedCount,
      },
    );

/// Runs [action] on [shift] through [ShiftActionsCubit], asking first where
/// it gives a place away, and says how it went. [assignmentId] is the
/// caller's place for every action but [ShiftAction.join].
///
/// Returns the outcome so the surface can replace its row with the answer;
/// null when the reader changed their mind.
Future<ShiftActionOutcome?> runShiftAction(
  BuildContext context,
  ShiftAction action, {
  required Shift shift,
  String? assignmentId,
}) async {
  final cubit = context.read<ShiftActionsCubit>();
  final ask = switch (action) {
    ShiftAction.release => 'shifts.ask.release',
    ShiftAction.decline => 'shifts.ask.decline',
    ShiftAction.waitlistLeave => 'shifts.ask.waitlistLeave',
    _ => null,
  };
  if (ask != null) {
    final sure = await showGlassConfirm(
      context,
      icon: action.icon,
      title: context.t('${ask}Title'),
      message: context.t('${ask}Message'),
      confirmLabel: context.t(action.labelKey),
      confirmIcon: action.icon,
      destructive: true,
    );
    if (sure != true || !context.mounted) return null;
  }
  final id = action == ShiftAction.waitlistLeave
      ? assignmentId ?? shift.myWaitAssignmentId
      : assignmentId ?? shift.myAssignmentId;
  final outcome = switch (action) {
    ShiftAction.join || ShiftAction.waitlistJoin => await cubit.join(shift),
    ShiftAction.confirm => await cubit.confirm(shift.id, id ?? ''),
    ShiftAction.decline => await cubit.decline(shift.id, id ?? ''),
    ShiftAction.release => await cubit.release(shift.id, id ?? ''),
    ShiftAction.waitlistLeave => await cubit.leaveWaitlist(shift.id, id ?? ''),
  };
  if (!context.mounted) return outcome;
  announceShiftOutcome(context, outcome);
  return outcome;
}

/// The toast after an action: done, done with the absence hint, or the
/// refusal in the app's own words.
void announceShiftOutcome(BuildContext context, ShiftActionOutcome outcome) {
  final error = outcome.errorKey;
  if (error != null) {
    showGlassToast(context, context.t(error), kind: GlassToastKind.error);
    return;
  }
  if (outcome.absent) {
    showGlassToast(
      context,
      '${context.t(outcome.messageKey!)}. ${context.t('shifts.absentHint')}',
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

/// The button for one [action], busy while any action on [shiftId] runs.
///
/// [primary] draws the honey capsule; otherwise a ghost one. [onNavy] lightens
/// the ghost for the hero card.
class ShiftActionButton extends StatelessWidget {
  const ShiftActionButton({
    super.key,
    required this.action,
    required this.shiftId,
    required this.onPressed,
    this.primary = true,
    this.onNavy = false,
  });

  final ShiftAction action;
  final String shiftId;
  final VoidCallback onPressed;
  final bool primary;
  final bool onNavy;

  @override
  Widget build(BuildContext context) {
    final busy = context.select<ShiftActionsCubit, bool>(
      (cubit) => cubit.state.isBusy(shiftId),
    );
    final label = context.t(action.labelKey);
    final press = busy ? null : onPressed;
    if (primary) {
      return PrimaryButton(label: label, icon: action.icon, onPressed: press);
    }
    if (onNavy) {
      return OutlinedButton.icon(
        onPressed: press,
        icon: Icon(action.icon, size: 16),
        label: Text(label),
        // The app's outlined theme lays a light glass gloss under the capsule.
        // On the navy hero that turned the white label into grey on grey, so
        // the capsule stays clear here and only its line shows.
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkOnNavy,
          backgroundColor: Colors.transparent,
          backgroundBuilder: (context, states, child) => child!,
          disabledForegroundColor: AppColors.inkSoftOnNavy,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.inkSoftOnNavy),
        ),
      );
    }
    return GhostButton(label: label, icon: action.icon, onPressed: press);
  }
}

/// [ShiftOffer] drawn: the buttons, or the note in words.
class ShiftOfferView extends StatelessWidget {
  const ShiftOfferView({
    super.key,
    required this.offer,
    required this.shift,
    required this.onAction,
    this.showSecondary = true,
    this.onNavy = false,
  });

  final ShiftOffer offer;
  final Shift shift;
  final ValueChanged<ShiftAction> onAction;

  /// Rows show the primary action only; the sheet and the hero show both.
  /// Where there is no primary, the secondary is shown either way.
  final bool showSecondary;
  final bool onNavy;

  @override
  Widget build(BuildContext context) {
    final note = offer.noteKey;
    if (note != null) {
      return Text(
        shiftOfferNote(context, note, shift),
        style: TextStyle(
          fontSize: AppType.label,
          fontWeight: FontWeight.w600,
          color: onNavy ? AppColors.inkSoftOnNavy : AppColors.inkFaint,
        ),
      );
    }
    final primary = offer.primary;
    // An offer with only a quiet action (the waiting list, withdrawing) shows
    // it everywhere: it is then the one thing to do.
    final secondary = showSecondary || primary == null ? offer.secondary : null;
    final position = secondary == ShiftAction.waitlistLeave
        ? waitlistPositionLabel(context, shift)
        : null;
    final buttons = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Waiting: the rank as a badge, the way out beside it.
        if (position != null)
          ShiftStatusBadge(
            status: ShiftAssignmentStatus.waiting,
            label: position,
          ),
        if (primary != null)
          ShiftActionButton(
            action: primary,
            shiftId: shift.id,
            onPressed: () => onAction(primary),
            onNavy: onNavy,
          ),
        if (secondary != null)
          ShiftActionButton(
            action: secondary,
            shiftId: shift.id,
            primary: false,
            onNavy: onNavy,
            onPressed: () => onAction(secondary),
          ),
      ],
    );
    // Before joining, how many already wait, under the button.
    if (secondary != ShiftAction.waitlistJoin || shift.waitingCount <= 0) {
      return buttons;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buttons,
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            context.t('shifts.waitlist.count', count: shift.waitingCount),
            style: TextStyle(
              fontSize: AppType.caption,
              color: onNavy ? AppColors.inkSoftOnNavy : AppColors.inkFaint,
            ),
          ),
        ),
      ],
    );
  }
}

/// Unawaited [runShiftAction] that hands the outcome to [then].
void startShiftAction(
  BuildContext context,
  ShiftAction action, {
  required Shift shift,
  String? assignmentId,
  void Function(ShiftActionOutcome outcome)? then,
}) {
  unawaited(
    runShiftAction(
      context,
      action,
      shift: shift,
      assignmentId: assignmentId,
    ).then((outcome) {
      if (outcome != null) then?.call(outcome);
    }),
  );
}
