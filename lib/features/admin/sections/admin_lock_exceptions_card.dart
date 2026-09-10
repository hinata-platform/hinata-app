import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/time_policy_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_approval_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        GlassToastKind,
        showGlassConfirm,
        showGlassDateRangePicker,
        showGlassToast;
import '../../time/lock_notice.dart';
import '../admin_form_helpers.dart';

/// The way back out of the lock date.
///
/// Before this, the only way to correct one day inside a closed period was to
/// clear the lock date altogether — which reopens *everything* after it, for
/// everyone, to fix one entry. That is not a proportionate remedy, and a freeze
/// with no proportionate remedy collides with Art. 16 DSGVO: working time is
/// personal data, and inaccurate personal data has to be correctable without
/// undue delay.
///
/// So an exception opens exactly its own span, carries a reason, names its author
/// and is recorded — the same shape as reopening an approved period, which is the
/// other freeze this stage builds a way back from. One vocabulary for both was the
/// point of doing them together.
///
/// Saved immediately rather than with the rest of the form, and that is not an
/// inconsistency with the policies above it: an exception is an *event* with an
/// author and a timestamp, not a setting, and a draft that vanished when somebody
/// navigated away would lose a reason they had typed.
class AdminLockExceptionsCard extends StatefulWidget {
  const AdminLockExceptionsCard({super.key});

  @override
  State<AdminLockExceptionsCard> createState() =>
      _AdminLockExceptionsCardState();
}

class _AdminLockExceptionsCardState extends State<AdminLockExceptionsCard> {
  /// What the instance currently has open. Null until the policy has answered —
  /// different from "answered, and there are none", which is an empty list.
  List<TimeLockException>? _exceptions;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      context.read<TimePolicyCubit>().ensureLoaded().then((_) {
        if (mounted) {
          setState(
            () => _exceptions = context
                .read<TimePolicyCubit>()
                .state
                .lockExceptions,
          );
        }
      }),
    );
  }

  Future<void> _add() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final span = await showGlassDateRangePicker(
      context,
      title: context.t('admin.timeTracking.lockExceptionSpan'),
      // Never into the future: an exception opens a *closed* span, and there is
      // nothing closed about tomorrow.
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      initialRange: DateTimeRange(start: today, end: today),
    );
    if (span == null || !mounted) return;
    final note = await showGlassNoteDialog(
      context,
      titleKey: 'admin.timeTracking.lockExceptionReason',
      hintKey: 'admin.timeTracking.lockExceptionReasonHint',
      confirmKey: 'admin.timeTracking.lockExceptionAdd',
    );
    if (note == null || !mounted) return;
    await _run(
      () => context.read<TimeRepository>().addLockException(
        from: span.start,
        to: span.end,
        note: note,
      ),
    );
  }

  Future<void> _remove(TimeLockException exception) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.lock,
      title: context.t('admin.timeTracking.lockExceptionRemove'),
      message: context.t(
        'admin.timeTracking.lockExceptionRemoveConfirm',
        variables: {
          'period': formatPeriod(context, exception.from, exception.to),
        },
      ),
      confirmLabel: context.t('common.delete'),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => context.read<TimeRepository>().removeLockException(exception.id),
    );
  }

  Future<void> _run(Future<List<TimeLockException>> Function() call) async {
    setState(() => _busy = true);
    try {
      final updated = await call();
      if (!mounted) return;
      setState(() {
        _exceptions = updated;
        _busy = false;
      });
      // The policy is what every member's app reads the open spans from, so a
      // change here has to reach it — otherwise the day stays drawn as frozen on
      // the very screen the exception was made for.
      unawaited(context.read<TimePolicyCubit>().refresh());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exceptions = _exceptions;
    return AdminSectionCard(
      icon: LucideIcons.lockOpen,
      title: context.t('admin.timeTracking.lockExceptionsTitle'),
      subtitle: context.t('admin.timeTracking.lockExceptionsHint'),
      children: [
        AdminNote(
          icon: LucideIcons.scale,
          text: context.t('admin.timeTracking.lockExceptionsLegal'),
        ),
        const SizedBox(height: 12),
        if (exceptions == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: HiveLoader()),
          )
        else if (exceptions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              context.t('admin.timeTracking.lockExceptionsEmpty'),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          for (final exception in exceptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatPeriod(context, exception.from, exception.to),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        if ((exception.note ?? '').isNotEmpty)
                          Text(
                            exception.note!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.t(
                      'admin.timeTracking.lockExceptionRemove',
                    ),
                    onPressed: _busy
                        ? null
                        : () => unawaited(_remove(exception)),
                    icon: const Icon(
                      LucideIcons.trash2,
                      size: 16,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GhostButton(
            icon: LucideIcons.plus,
            label: context.t('admin.timeTracking.lockExceptionAdd'),
            onPressed: _busy ? null : () => unawaited(_add()),
          ),
        ),
      ],
    );
  }
}
