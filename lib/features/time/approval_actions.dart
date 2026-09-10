import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_approval_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import 'lock_notice.dart';

/// The five things that can happen to a submission, in one place.
///
/// Two screens do all five — the timesheet hands in and takes back, the inbox
/// signs off, sends back and reopens — and each one is the same three steps: ask
/// for what the server requires, call, say what happened. Spread across two
/// screens that would be ten copies of the error handling, and the part that
/// would rot first is the one that matters: a rejection's reason is *required*,
/// and a screen that forgot to ask for it offers a button the server refuses.
class ApprovalActions {
  const ApprovalActions._();

  /// Hands a span in. Answers true when something was actually submitted.
  static Future<bool> submit(
    BuildContext context, {
    required DateTime periodStart,
    required DateTime periodEnd,
    List<String>? projectIds,
  }) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.send,
      title: context.t('time.approval.submitTitle'),
      message: context.t(
        'time.approval.submitConfirm',
        variables: {'period': formatPeriod(context, periodStart, periodEnd)},
      ),
      confirmLabel: context.t('time.approval.submitAction'),
    );
    if (confirmed != true || !context.mounted) return false;
    return _run(
      context,
      () => context.read<TimeRepository>().submitPeriod(
        periodStart: periodStart,
        periodEnd: periodEnd,
        projectIds: projectIds,
      ),
      successKey: 'time.approval.submitted',
    );
  }

  /// Takes a pending submission back.
  static Future<bool> withdraw(BuildContext context, String approvalId) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.undo2,
      title: context.t('time.approval.withdrawTitle'),
      message: context.t('time.approval.withdrawConfirm'),
      confirmLabel: context.t('time.approval.withdrawAction'),
    );
    if (confirmed != true || !context.mounted) return false;
    return _run(
      context,
      () => context.read<TimeRepository>().withdrawApproval(approvalId),
      successKey: 'time.approval.withdrawn',
    );
  }

  /// Signs a period off. A reason is optional here — accepting needs no excuse.
  static Future<bool> approve(BuildContext context, String approvalId) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.check,
      title: context.t('time.approval.approveTitle'),
      message: context.t('time.approval.approveConfirm'),
      confirmLabel: context.t('time.approval.approveAction'),
    );
    if (confirmed != true || !context.mounted) return false;
    return _run(
      context,
      () => context.read<TimeRepository>().approve(approvalId),
      successKey: 'time.approval.approved',
    );
  }

  /// Sends a period back. The reason is required — by the server, and here.
  ///
  /// Asked for before the call rather than after a 400: the person on the other
  /// end has to be able to act on it, and "no" on its own is not something
  /// anybody can act on.
  static Future<bool> reject(BuildContext context, String approvalId) async {
    final note = await showGlassNoteDialog(
      context,
      titleKey: 'time.approval.rejectTitle',
      hintKey: 'time.approval.rejectHint',
      confirmKey: 'time.approval.rejectAction',
    );
    if (note == null || !context.mounted) return false;
    return _run(
      context,
      () => context.read<TimeRepository>().reject(approvalId, note: note),
      successKey: 'time.approval.rejected',
    );
  }

  /// Takes an approved period back so it can be corrected, with a reason.
  static Future<bool> reopen(BuildContext context, String approvalId) async {
    final note = await showGlassNoteDialog(
      context,
      titleKey: 'time.approval.reopenTitle',
      hintKey: 'time.approval.reopenHint',
      confirmKey: 'time.approval.reopenAction',
    );
    if (note == null || !context.mounted) return false;
    return _run(
      context,
      () => context.read<TimeRepository>().reopen(approvalId, note: note),
      successKey: 'time.approval.reopened',
    );
  }

  static Future<bool> _run(
    BuildContext context,
    Future<void> Function() call, {
    required String successKey,
  }) async {
    try {
      await call();
      if (!context.mounted) return true;
      showGlassToast(
        context,
        context.t(successKey),
        kind: GlassToastKind.success,
      );
      return true;
    } on ApiFailure catch (failure) {
      if (!context.mounted) return false;
      // Through context.t: an ApiFailure carries the server's i18n *key*, and
      // printing it raw leaks "error.time.periodNotOnGrid" at somebody.
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
      return false;
    }
  }
}

/// The freeze a refusal names, or null when the refusal is about something else.
///
/// The server answers every frozen write with the reason, who can lift it and the
/// way back, beside the sentence. Reading it is what keeps the app from having to
/// guess: the app's own resolver works from the rules it holds, and the rules can
/// be a moment out of date — somebody else's approval landing between the last
/// policy read and this save. Then the refusal is the authority, and it carries
/// everything the notice needs.
TimeLockInfo? lockFromFailure(ApiFailure failure, {String? entryId}) =>
    TimeLockInfo.fromDetails(failure.details, entryId: entryId);

/// Where one project's period stands, as a chip.
///
/// Four states and a colour each, and the one that carries more than its colour
/// is "sent back": the reason is the whole point of a rejection, so it is on the
/// tooltip rather than a tap away.
class ApprovalStatusChip extends StatelessWidget {
  const ApprovalStatusChip({super.key, required this.status, this.note});

  final ApprovalStatus? status;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final state = status;
    final (tint, glyph) = switch (state) {
      null => (AppColors.inkFaint, LucideIcons.circleDashed),
      ApprovalStatus.submitted => (AppColors.accent, LucideIcons.clock3),
      ApprovalStatus.approved => (AppColors.success, LucideIcons.circleCheck),
      ApprovalStatus.rejected => (AppColors.danger, LucideIcons.circleAlert),
      ApprovalStatus.withdrawn => (AppColors.inkFaint, LucideIcons.undo2),
    };
    final label = context.t(state?.labelKey ?? 'time.approval.status.open');
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(glyph, size: 12, color: tint),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ],
      ),
    );
    final reason = note?.trim();
    if (reason == null || reason.isEmpty) return chip;
    return Tooltip(message: reason, child: chip);
  }
}
