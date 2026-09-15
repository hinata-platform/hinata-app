import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/availability_models.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show fmtDuration;
import '../../core/widgets/read_on_trigger.dart';
import '../sprint/modals/glass_modal.dart';
import '../time/day_marks.dart';
import 'account_widgets.dart';
import 'time_off_sheet.dart';

/// Settings → Working hours and absences (HIN-91).
///
/// What a person states about themselves for planning: the hours they plan per
/// weekday, the holidays they follow, and the days they are away. None of it
/// changes what they can record. A holiday or a day off is marked in the
/// calendar and the list, and time on it is recorded like on any other day (R9).
class AvailabilitySection extends StatefulWidget {
  const AvailabilitySection({super.key});

  @override
  State<AvailabilitySection> createState() => _AvailabilitySectionState();
}

class _AvailabilitySectionState extends State<AvailabilitySection> {
  /// Half an hour, the step the weekday hours move in.
  static const int _step = 30;

  WorkingSchedule? _schedule;
  List<HolidayCalendar> _calendars = const [];
  bool _loading = true;
  String? _errorKey;

  /// What the reader changed and has not saved; null for "as stored".
  List<int>? _draftMinutes;
  DateTime? _validFrom;

  /// The calendar the pattern follows, null for the default. Starts as the
  /// stored one, so it differs from it only once the reader picks another.
  String? _calendarId;
  bool _saving = false;

  /// A year back and everything ahead: short enough to stay a list, and every
  /// absence still being planned is in it.
  late final PagedCubit<TimeOff> _absences = PagedCubit<TimeOff>(
    (page, size) => context.read<AvailabilityRepository>().timeOff(
      from: _since,
      page: page,
      size: size,
    ),
    pageSize: 50,
    keyOf: (item) => item.id ?? '',
  );

  DateTime get _since {
    final now = DateTime.now();
    return DateTime(now.year - 1, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_absences.load());
  }

  @override
  void dispose() {
    unawaited(_absences.close());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final repository = context.read<AvailabilityRepository>();
      // Side by side: neither answer waits for the other.
      final schedule = repository.schedule();
      final calendars = repository.calendars(size: 100);
      await Future.wait([schedule, calendars]);
      final stored = await schedule;
      final offered = (await calendars).items;
      if (!mounted) return;
      setState(() {
        _calendars = offered;
        _loading = false;
        _adopt(stored);
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  /// Takes [schedule] as stored and drops whatever was changed over it.
  void _adopt(WorkingSchedule schedule) {
    _schedule = schedule;
    _draftMinutes = null;
    _validFrom = null;
    _calendarId = schedule.current?.holidayCalendarId;
  }

  /// The pattern is only drawn once a schedule is held.
  List<int> get _minutes => _draftMinutes ?? _schedule!.effectiveMinutes;

  bool get _dirty =>
      _draftMinutes != null ||
      _validFrom != null ||
      _calendarId != _schedule?.current?.holidayCalendarId;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repository = context.read<AvailabilityRepository>();
      await repository.saveSchedule(
        validFrom: _validFrom,
        minutesPerWeekday: _minutes,
        holidayCalendarId: _calendarId,
      );
      if (!mounted) return;
      showGlassToast(context, context.t('availability.pattern.saved'));
      // Only the pattern is read again: saving it changes no calendar.
      final schedule = await repository.schedule();
      if (mounted) setState(() => _adopt(schedule));
    } on ApiFailure catch (failure) {
      if (mounted) showGlassErrorToast(context, context.t(failure.message));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickValidFrom() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showGlassDatePicker(
      context,
      initialDate: _validFrom ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2, 12, 31),
      title: context.t('availability.pattern.validFrom'),
    );
    if (picked == null || !mounted) return;
    setState(() => _validFrom = DateUtils.dateOnly(picked));
  }

  /// The calendar row, which the menu of calendars hangs from.
  final _calendarKey = GlobalKey();

  Future<void> _pickCalendar() async {
    final anchor = anchorRectOf(_calendarKey);
    if (anchor == null) return;
    final chosen = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      width: 260,
      value: _calendarId ?? '',
      items: [
        GlassMenuItem(value: '', label: _defaultCalendarLabel(context)),
        for (final calendar in _calendars)
          GlassMenuItem(value: calendar.id, label: calendar.name),
      ],
    );
    if (chosen == null || !mounted) return;
    setState(() => _calendarId = chosen.isEmpty ? null : chosen);
  }

  String _defaultCalendarLabel(BuildContext context) {
    final fallback = _calendars
        .where((calendar) => calendar.defaultCalendar)
        .firstOrNull;
    return fallback == null
        ? context.t('availability.pattern.calendarNone')
        : context.t(
            'availability.pattern.calendarDefault',
            variables: {'name': fallback.name},
          );
  }

  String _calendarLabel(BuildContext context) {
    final id = _calendarId;
    if (id == null) return _defaultCalendarLabel(context);
    return _calendars
            .where((calendar) => calendar.id == id)
            .firstOrNull
            ?.name ??
        _defaultCalendarLabel(context);
  }

  Future<void> _editAbsence(TimeOff? existing) async {
    final saved = await showTimeOffSheet(context, existing: existing);
    if (saved == true && mounted) unawaited(_absences.load());
  }

  @override
  Widget build(BuildContext context) {
    return AccountSection(
      icon: LucideIcons.calendarClock,
      title: context.t('availability.section.title'),
      subtitle: context.t('availability.section.subtitle'),
      children: [
        if (_loading && _schedule == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: HiveLoader(size: 32)),
          )
        else if (_errorKey != null && _schedule == null)
          _failed(context, _errorKey!, _load)
        else
          ..._pattern(context),
        Divider(height: 1, color: AppColors.hairline2),
        BlocProvider.value(value: _absences, child: _absenceList(context)),
      ],
    );
  }

  /// What stands where something could not be read: why, and the way to try
  /// again, as on the holidays page.
  Widget _failed(
    BuildContext context,
    String errorKey,
    Future<void> Function() retry,
  ) => HiveEmptyState(
    title: context.t(errorKey),
    card: false,
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
    action: OutlinedButton(
      onPressed: () => unawaited(retry()),
      child: Text(context.t('common.retry')),
    ),
  );

  List<Widget> _pattern(BuildContext context) {
    final minutes = _minutes;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final total = minutes.fold<int>(0, (sum, day) => sum + day);
    final usingDefault = _schedule?.current == null && _draftMinutes == null;
    return [
      _Label(
        text: context.t('availability.pattern.title'),
        trailing: context.t(
          'availability.pattern.weekTotal',
          variables: {'duration': fmtDuration(context, total)},
        ),
      ),
      if (usingDefault)
        _Hint(text: context.t('availability.pattern.usingDefault')),
      for (var day = 0; day < 7; day++)
        _HoursRow(
          // 1 January 2024 was a Monday; the pattern starts on Monday too.
          label: DateFormat.EEEE(locale).format(DateTime(2024, 1, 1 + day)),
          minutes: minutes[day],
          free: context.t('availability.pattern.free'),
          onChanged: (value) =>
              setState(() => _draftMinutes = [...minutes]..[day] = value),
          step: _step,
        ),
      Divider(height: 1, color: AppColors.hairline2),
      SettingRow(
        icon: LucideIcons.calendarCheck2,
        label: context.t('availability.pattern.validFrom'),
        trailing: _PickedValue(
          _validFrom == null
              ? context.t('availability.pattern.today')
              : MaterialLocalizations.of(context).formatMediumDate(_validFrom!),
        ),
        onTap: _pickValidFrom,
      ),
      KeyedSubtree(
        key: _calendarKey,
        child: SettingRow(
          icon: LucideIcons.calendarHeart,
          label: context.t('availability.pattern.calendar'),
          trailing: _PickedValue(_calendarLabel(context)),
          onTap: _pickCalendar,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.t('availability.pattern.validFromHint'),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _dirty && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: HiveLoader(size: 14),
                    )
                  : const Icon(LucideIcons.check, size: 15),
              label: Text(context.t('availability.pattern.save')),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _absenceList(BuildContext context) =>
      BlocBuilder<PagedCubit<TimeOff>, PagedState<TimeOff>>(
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(
              text: context.t('availability.timeOff.title'),
              action: TextButton.icon(
                onPressed: () => _editAbsence(null),
                icon: const Icon(LucideIcons.plus, size: 15),
                label: Text(context.t('availability.timeOff.add')),
              ),
            ),
            _Hint(text: context.t('availability.timeOff.hint')),
            if (state.isLoading && !state.hasData)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: HiveLoader(size: 28)),
              )
            else if (state.errorKey != null && !state.hasData)
              _failed(context, state.errorKey!, _absences.load)
            else if (state.items.isEmpty)
              HiveEmptyState(
                title: context.t('availability.timeOff.empty'),
                message: context.t('availability.timeOff.emptyMessage'),
                card: false,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              )
            else ...[
              for (final item in state.items)
                _AbsenceRow(item: item, onTap: () => _editAbsence(item)),
              if (state.hasMore)
                ReadOnTrigger(
                  count: state.items.length,
                  loading: state.isLoadingMore,
                  onReadOn: () => unawaited(_absences.loadMore()),
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label({required this.text, this.trailing, this.action});

  final String text;
  final String? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 14, action == null ? 16 : 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.inkSoft,
            ),
          ),
        ?action,
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.4,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

/// One weekday and its planned hours, stepped by half an hour: a number with a
/// narrow range needs two buttons, not a keyboard and an error state.
class _HoursRow extends StatelessWidget {
  const _HoursRow({
    required this.label,
    required this.minutes,
    required this.free,
    required this.onChanged,
    required this.step,
  });

  final String label;
  final int minutes;
  final String free;
  final ValueChanged<int> onChanged;
  final int step;

  @override
  Widget build(BuildContext context) {
    final down = (minutes - step).clamp(0, 24 * 60);
    final up = (minutes + step).clamp(0, 24 * 60);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: AppColors.ink),
            ),
          ),
          Container(
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
                  tooltip: label,
                  onTap: down == minutes ? null : () => onChanged(down),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 70),
                  child: Text(
                    minutes == 0 ? free : fmtDuration(context, minutes),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: minutes == 0
                          ? AppColors.textSecondary
                          : AppColors.ink,
                    ),
                  ),
                ),
                _Arrow(
                  icon: LucideIcons.plus,
                  tooltip: label,
                  onTap: up == minutes ? null : () => onChanged(up),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 15,
          semanticLabel: tooltip,
          color: onTap == null ? AppColors.inkFaint : AppColors.inkSoft,
        ),
      ),
    ),
  );
}

/// What a picker row currently holds, beside the chevron that says it opens.
class _PickedValue extends StatelessWidget {
  const _PickedValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 220),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(LucideIcons.chevronDown, size: 14, color: AppColors.inkFaint),
      ],
    ),
  );
}

class _AbsenceRow extends StatelessWidget {
  const _AbsenceRow({required this.item, required this.onTap});

  final TimeOff item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final span = formatDaySpan(context, item.from, item.to);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.recess,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                timeOffIcon(item.type),
                size: 15,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(item.type.labelKey),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    item.halfDay
                        ? context.t(
                            'availability.timeOff.halfDaySpan',
                            variables: {'days': span},
                          )
                        : span,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (item.note != null && item.note!.isNotEmpty)
                    Text(
                      item.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 15, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
