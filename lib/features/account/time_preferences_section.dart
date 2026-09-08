import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/time_preferences_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'account_widgets.dart';

/// Settings → Time tracking: the person's own rhythm.
///
/// Five lengths and a switch, and every one of them is theirs. Nothing here is
/// an administrator's to set — an employer prescribing how long somebody's
/// breaks are is precisely what HIN-60's R2/R7 exist to prevent — which is why
/// they live on the account rather than in the server settings.
///
/// Shown only where the module is switched on. There is no point offering to
/// configure a pomodoro on a server that has no pomodoro.
class TimePreferencesSection extends StatelessWidget {
  const TimePreferencesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<TimePreferencesCubit>();
    final prefs = cubit.state;
    final stack = context.isCompact;
    Future<void> save(TimePreferences next) async {
      if (await cubit.save(next)) return;
      if (!context.mounted) return;
      showGlassToast(
        context,
        context.t('account.timeTracking.saveFailed'),
        kind: GlassToastKind.error,
      );
    }

    return AccountSection(
      icon: LucideIcons.timer,
      title: context.t('account.timeTracking.title'),
      subtitle: context.t('account.timeTracking.subtitle'),
      children: [
        _GroupLabel(text: context.t('account.timeTracking.pomodoro')),
        _MinutesRow(
          label: context.t('account.timeTracking.work'),
          value: prefs.pomodoroWork,
          min: TimePreferences.minWork,
          max: TimePreferences.maxWork,
          step: 5,
          stack: stack,
          onChanged: (value) => save(prefs.copyWith(pomodoroWork: value)),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        _MinutesRow(
          label: context.t('account.timeTracking.shortBreak'),
          value: prefs.pomodoroShortBreak,
          min: TimePreferences.minBreak,
          max: TimePreferences.maxBreak,
          stack: stack,
          onChanged: (value) => save(prefs.copyWith(pomodoroShortBreak: value)),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        _MinutesRow(
          label: context.t('account.timeTracking.longBreak'),
          value: prefs.pomodoroLongBreak,
          min: TimePreferences.minLongBreak,
          max: TimePreferences.maxLongBreak,
          step: 5,
          stack: stack,
          onChanged: (value) => save(prefs.copyWith(pomodoroLongBreak: value)),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        _StepperRow(
          label: context.t('account.timeTracking.cycles'),
          value: prefs.pomodoroCycles,
          min: TimePreferences.minCycles,
          max: TimePreferences.maxCycles,
          step: 1,
          stack: stack,
          format: (value) =>
              context.t('account.timeTracking.intervals', count: value),
          onChanged: (value) => save(prefs.copyWith(pomodoroCycles: value)),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        _GroupLabel(text: context.t('account.timeTracking.countdown')),
        _MinutesRow(
          label: context.t('account.timeTracking.countdownLength'),
          value: prefs.countdownMinutes,
          min: TimePreferences.minCountdown,
          max: TimePreferences.maxCountdown,
          step: 5,
          stack: stack,
          onChanged: (value) => save(prefs.copyWith(countdownMinutes: value)),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('account.timeTracking.sound'),
          description: context.t('account.timeTracking.soundHint'),
          icon: LucideIcons.volume2,
          trailing: HiveSwitch(
            value: prefs.sound,
            onChanged: (value) => unawaited(save(prefs.copyWith(sound: value))),
          ),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.inkFaint,
      ),
    ),
  );
}

/// A stepper whose value happens to be minutes.
class _MinutesRow extends StatelessWidget {
  const _MinutesRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.stack,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final bool stack;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _StepperRow(
    label: label,
    value: value,
    min: min,
    max: max,
    step: step,
    stack: stack,
    format: (value) => context.t('account.timeTracking.minutes', count: value),
    onChanged: onChanged,
  );
}

/// Minus, a number, plus.
///
/// A stepper rather than a text field: every one of these is a small whole
/// number with a narrow range, and a field would need a keyboard, a parser and
/// an error state to express what two buttons express by not offering the
/// wrong answer at all. The bounds are the server's, stated in
/// [TimePreferences] — an arrow that offered a number the server refuses would
/// be a 400 the reader cannot make sense of.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.stack,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final bool stack;
  final String Function(int value) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // Clamped to the bounds rather than stepped past them, so holding the arrow
    // at the edge lands on the edge instead of doing nothing one press early.
    final down = (value - step).clamp(min, max);
    final up = (value + step).clamp(min, max);
    return SettingRow(
      label: label,
      stack: stack,
      trailing: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Arrow(
              icon: LucideIcons.minus,
              onTap: down == value ? null : () => onChanged(down),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 74),
              child: Text(
                format(value),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppColors.ink,
                ),
              ),
            ),
            _Arrow(
              icon: LucideIcons.plus,
              onTap: up == value ? null : () => onChanged(up),
            ),
          ],
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(
          icon,
          size: 15,
          color: onTap == null ? AppColors.inkFaint : AppColors.inkSoft,
        ),
      ),
    ),
  );
}
