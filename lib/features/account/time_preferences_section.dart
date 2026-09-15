import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/blocs/time_preferences_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/file_download.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch, fmtDuration;
import '../sprint/modals/glass_modal.dart'
    show
        GlassToastKind,
        showGlassDurationPicker,
        showGlassOptions,
        showGlassTimePicker,
        showGlassToast;
import '../time/lock_notice.dart' show requestOlderDays;
import '../time/time_privacy_sheet.dart';
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
///
/// It also carries the person's data rights for the module (HIN-89): who sees
/// their time, a copy of their own entries, and how a correction is asked for.
/// Here rather than in the account's data section because they are about this
/// module's data, and somebody looking for them looks where the module is.
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
        Divider(height: 1, color: AppColors.hairline2),
        _Reminders(prefs: prefs, stack: stack, onSave: save),
        _GroupLabel(text: context.t('account.timeTracking.privacy')),
        SettingRow(
          label: context.t('account.timeTracking.privacyPanel'),
          description: context.t('account.timeTracking.privacyPanelHint'),
          icon: LucideIcons.shieldCheck,
          stack: stack,
          trailing: AccountActionButton(
            label: context.t('account.timeTracking.privacyOpen'),
            icon: LucideIcons.eye,
            onPressed: () => unawaited(showTimePrivacySheet(context)),
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('account.timeTracking.exportCsv'),
          description: context.t('account.timeTracking.exportCsvHint'),
          icon: LucideIcons.fileDown,
          stack: stack,
          trailing: AccountActionButton(
            label: context.t('account.timeTracking.exportCsvButton'),
            icon: LucideIcons.download,
            onPressed: () => unawaited(_exportCsv(context)),
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        SettingRow(
          label: context.t('account.timeTracking.correction'),
          description: context.t('account.timeTracking.correctionHint'),
          icon: LucideIcons.messageSquareWarning,
          stack: stack,
          // The one request that has no entry to start from: days the pickers do
          // not offer yet. A correction starts from the entry itself.
          trailing: AccountActionButton(
            label: context.t('account.timeTracking.requestDays'),
            icon: LucideIcons.calendarPlus,
            onPressed: () => unawaited(requestOlderDays(context)),
          ),
        ),
      ],
    );
  }

  /// Downloads the person's own entries as CSV.
  ///
  /// Every entry, not a window: the file is the copy Art. 20 DSGVO speaks of, and
  /// a copy that silently stopped at some date would not be one. The server caps
  /// it far beyond any real career of entries.
  static Future<void> _exportCsv(BuildContext context) async {
    final repository = context.read<TimeRepository>();
    try {
      final DownloadResult result;
      var truncated = false;
      if (kIsWeb) {
        final file = await repository.exportCsv();
        truncated = file.truncated;
        result = await downloadBytes(
          'time-entries.csv',
          file.bytes,
          'text/csv',
        );
      } else {
        // Straight to disk: a long record of entries runs to tens of megabytes,
        // which a phone should not have to hold in memory to save.
        result = await downloadFile('time-entries.csv', 'text/csv', (
          path,
        ) async {
          truncated = await repository.exportCsvTo(path);
        });
      }
      if (!context.mounted || result.outcome == DownloadOutcome.dismissed) {
        return;
      }
      final failed = result.outcome == DownloadOutcome.failed;
      showGlassToast(
        context,
        context.t(
          failed
              ? 'account.timeTracking.exportFailed'
              : truncated
              ? 'account.timeTracking.exportTruncated'
              : 'account.timeTracking.exportDone',
        ),
        kind: failed ? GlassToastKind.error : GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (!context.mounted) return;
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }
}

/// Targets of the person's own, and when to be reminded of them (HIN-92).
///
/// Only while the operator has reminders switched on. The hint says what a
/// person needs to know before setting a target: nobody but them is reminded,
/// and nobody learns whether they reached it. A target starts at what the
/// operator suggests, and the suggestion stays offered when it differs, because
/// taking it over is the person's decision.
class _Reminders extends StatefulWidget {
  const _Reminders({
    required this.prefs,
    required this.stack,
    required this.onSave,
  });

  final TimePreferences prefs;
  final bool stack;
  final Future<void> Function(TimePreferences next) onSave;

  @override
  State<_Reminders> createState() => _RemindersState();
}

class _RemindersState extends State<_Reminders> {
  @override
  void initState() {
    super.initState();
    // Opened straight from a link, nothing may have read the policy yet.
    unawaited(context.read<TimePolicyCubit>().ensureLoaded());
  }

  TimePreferences get _prefs => widget.prefs;

  void _save(TimePreferences next) => unawaited(widget.onSave(next));

  Future<void> _pickTarget(
    int current,
    int maxMinutes,
    TimePreferences Function(int minutes) apply,
  ) async {
    final picked = await showGlassDurationPicker(
      context,
      initialMinutes: current,
      title: context.t('account.timeTracking.target'),
      maxHours: maxMinutes ~/ 60,
    );
    if (picked == null || !mounted) return;
    _save(apply(picked.clamp(1, maxMinutes)));
  }

  Future<void> _pickTime(
    int minuteOfDay,
    TimePreferences Function(int minuteOfDay) apply,
  ) async {
    final picked = await showGlassTimePicker(
      context,
      initial: TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
      title: context.t('account.timeTracking.remindAt'),
    );
    if (picked == null || !mounted) return;
    _save(apply(picked.hour * 60 + picked.minute));
  }

  Future<void> _pickDay() async {
    final picked = await showGlassOptions<int>(
      context,
      title: context.t('account.timeTracking.remindOn'),
      options: [
        for (var day = DateTime.monday; day <= DateTime.sunday; day++)
          (value: day, child: Text(_weekday(context, day))),
      ],
    );
    if (picked == null || !mounted) return;
    _save(_prefs.copyWith(weeklyReminderDay: picked));
  }

  static String _weekday(BuildContext context, int day) => DateFormat.EEEE(
    Localizations.localeOf(context).toString(),
  ).format(DateTime(2024, 1, day)); // 1 January 2024 was a Monday.

  static String _clock(BuildContext context, int minuteOfDay) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  @override
  Widget build(BuildContext context) {
    final policy = context.watch<TimePolicyCubit>().state;
    if (!policy.targetRemindersEnabled) return const SizedBox.shrink();
    final prefs = _prefs;
    final daily = prefs.dailyTargetMinutes;
    final weekly = prefs.weeklyTargetMinutes;
    final divider = Divider(height: 1, color: AppColors.hairline2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupLabel(text: context.t('account.timeTracking.reminders')),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Text(
            context.t('account.timeTracking.remindersHint'),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        SettingRow(
          label: context.t('account.timeTracking.dailyTarget'),
          description: context.t('account.timeTracking.dailyTargetHint'),
          icon: LucideIcons.target,
          trailing: HiveSwitch(
            value: daily != null,
            onChanged: (on) => _save(
              on
                  ? prefs.copyWith(
                      dailyTargetMinutes:
                          policy.suggestedDailyTargetMinutes ??
                          TimePreferences.fallbackDailyTarget,
                    )
                  : prefs.copyWith(clearDailyTarget: true),
            ),
          ),
        ),
        if (daily != null) ...[
          divider,
          _PickRow(
            label: context.t('account.timeTracking.target'),
            value: fmtDuration(context, daily),
            icon: LucideIcons.hourglass,
            stack: widget.stack,
            onTap: () => _pickTarget(
              daily,
              TimePreferences.maxDailyTarget,
              (minutes) => prefs.copyWith(dailyTargetMinutes: minutes),
            ),
          ),
          divider,
          _PickRow(
            label: context.t('account.timeTracking.remindAt'),
            value: _clock(context, prefs.dailyReminderAt),
            icon: LucideIcons.clock,
            stack: widget.stack,
            onTap: () => _pickTime(
              prefs.dailyReminderAt,
              (minute) => prefs.copyWith(dailyReminderAt: minute),
            ),
          ),
          ..._suggestion(
            current: daily,
            suggested: policy.suggestedDailyTargetMinutes,
            take: (minutes) => prefs.copyWith(dailyTargetMinutes: minutes),
            divider: divider,
          ),
        ],
        divider,
        SettingRow(
          label: context.t('account.timeTracking.weeklyTarget'),
          description: context.t('account.timeTracking.weeklyTargetHint'),
          icon: LucideIcons.calendarRange,
          trailing: HiveSwitch(
            value: weekly != null,
            onChanged: (on) => _save(
              on
                  ? prefs.copyWith(
                      weeklyTargetMinutes:
                          policy.suggestedWeeklyTargetMinutes ??
                          TimePreferences.fallbackWeeklyTarget,
                    )
                  : prefs.copyWith(clearWeeklyTarget: true),
            ),
          ),
        ),
        if (weekly != null) ...[
          divider,
          _PickRow(
            label: context.t('account.timeTracking.target'),
            value: fmtDuration(context, weekly),
            icon: LucideIcons.hourglass,
            stack: widget.stack,
            onTap: () => _pickTarget(
              weekly,
              TimePreferences.maxWeeklyTarget,
              (minutes) => prefs.copyWith(weeklyTargetMinutes: minutes),
            ),
          ),
          divider,
          _PickRow(
            label: context.t('account.timeTracking.remindOn'),
            value: _weekday(context, prefs.weeklyReminderDay),
            icon: LucideIcons.calendarDays,
            stack: widget.stack,
            onTap: _pickDay,
          ),
          divider,
          _PickRow(
            label: context.t('account.timeTracking.remindAt'),
            value: _clock(context, prefs.weeklyReminderAt),
            icon: LucideIcons.clock,
            stack: widget.stack,
            onTap: () => _pickTime(
              prefs.weeklyReminderAt,
              (minute) => prefs.copyWith(weeklyReminderAt: minute),
            ),
          ),
          ..._suggestion(
            current: weekly,
            suggested: policy.suggestedWeeklyTargetMinutes,
            take: (minutes) => prefs.copyWith(weeklyTargetMinutes: minutes),
            divider: divider,
          ),
        ],
        divider,
      ],
    );
  }

  /// The operator's suggestion, offered while it differs from the target.
  List<Widget> _suggestion({
    required int current,
    required int? suggested,
    required TimePreferences Function(int minutes) take,
    required Widget divider,
  }) {
    if (suggested == null || suggested == current) return const [];
    return [
      divider,
      SettingRow(
        label: context.t(
          'account.timeTracking.suggested',
          variables: {'duration': fmtDuration(context, suggested)},
        ),
        stack: widget.stack,
        trailing: AccountActionButton(
          label: context.t('account.timeTracking.useSuggestion'),
          icon: LucideIcons.check,
          onPressed: () => _save(take(suggested)),
        ),
      ),
    ];
  }
}

/// A row whose value opens a glass picker: never an inline wheel.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.stack,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool stack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SettingRow(
    label: label,
    stack: stack,
    trailing: AccountActionButton(label: value, icon: icon, onPressed: onTap),
  );
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
