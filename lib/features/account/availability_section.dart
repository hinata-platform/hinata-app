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
import '../../core/widgets/hive_widgets.dart' show HiveSwitch, fmtDuration;
import '../sprint/modals/glass_modal.dart';
import '../time/day_marks.dart';
import 'account_widgets.dart';

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
  bool _calendarChanged = false;
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
      final schedule = await repository.schedule();
      final calendars = await repository.calendars(size: 100);
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _calendars = calendars.items;
        _draftMinutes = null;
        _validFrom = null;
        _calendarChanged = false;
        _calendarId = schedule.current?.holidayCalendarId;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  List<int> get _minutes =>
      _draftMinutes ??
      _schedule?.effectiveMinutes ??
      const [480, 480, 480, 480, 480, 0, 0];

  bool get _dirty =>
      _draftMinutes != null || _validFrom != null || _calendarChanged;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AvailabilityRepository>().saveSchedule(
        validFrom: _validFrom,
        minutesPerWeekday: _minutes,
        holidayCalendarId: _calendarChanged
            ? _calendarId
            : _schedule?.current?.holidayCalendarId,
      );
      if (!mounted) return;
      showGlassToast(context, context.t('availability.pattern.saved'));
      await _load();
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

  Future<void> _pickCalendar(Rect? anchor) async {
    if (anchor == null) return;
    final current = _calendarChanged
        ? _calendarId
        : _schedule?.current?.holidayCalendarId;
    final chosen = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      width: 260,
      value: current ?? '',
      items: [
        GlassMenuItem(value: '', label: _defaultCalendarLabel(context)),
        for (final calendar in _calendars)
          GlassMenuItem(value: calendar.id, label: calendar.name),
      ],
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _calendarChanged = true;
      _calendarId = chosen.isEmpty ? null : chosen;
    });
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
    final id = _calendarChanged
        ? _calendarId
        : _schedule?.current?.holidayCalendarId;
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
          _Retry(message: context.t(_errorKey!), onRetry: _load)
        else
          ..._pattern(context),
        Divider(height: 1, color: AppColors.hairline2),
        BlocProvider.value(value: _absences, child: _absenceList(context)),
      ],
    );
  }

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
      _PickerRow(
        icon: LucideIcons.calendarCheck2,
        label: context.t('availability.pattern.validFrom'),
        value: _validFrom == null
            ? context.t('availability.pattern.today')
            : MaterialLocalizations.of(context).formatMediumDate(_validFrom!),
        onTap: (_) => _pickValidFrom(),
      ),
      _PickerRow(
        icon: LucideIcons.calendarHeart,
        label: context.t('availability.pattern.calendar'),
        value: _calendarLabel(context),
        onTap: _pickCalendar,
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
              _Retry(
                message: context.t(state.errorKey!),
                onRetry: _absences.load,
              )
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
                _ReadOn(
                  loading: state.isLoadingMore,
                  onReached: _absences.loadMore,
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
}

/// Opens the form for a new absence, or for [existing]. Resolves to true once
/// something was saved or deleted.
Future<bool?> showTimeOffSheet(BuildContext context, {TimeOff? existing}) {
  final repository = context.read<AvailabilityRepository>();
  return showGlassModal<bool>(
    context,
    adaptive: true,
    width: 440,
    builder: (sheetContext) => RepositoryProvider.value(
      value: repository,
      child: _TimeOffForm(existing: existing),
    ),
  );
}

class _TimeOffForm extends StatefulWidget {
  const _TimeOffForm({this.existing});

  final TimeOff? existing;

  @override
  State<_TimeOffForm> createState() => _TimeOffFormState();
}

class _TimeOffFormState extends State<_TimeOffForm> {
  late TimeOffType _type = widget.existing?.type ?? TimeOffType.vacation;
  late DateTimeRange _range = _initialRange();
  late bool _halfDay = widget.existing?.halfDay ?? false;
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  bool _saving = false;

  DateTimeRange _initialRange() {
    final existing = widget.existing;
    if (existing != null) {
      return DateTimeRange(start: existing.from, end: existing.to);
    }
    final today = DateUtils.dateOnly(DateTime.now());
    return DateTimeRange(start: today, end: today);
  }

  bool get _singleDay => DateUtils.isSameDay(_range.start, _range.end);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickType(Rect? anchor) async {
    if (anchor == null) return;
    final chosen = await showGlassMenu<TimeOffType>(
      context: context,
      anchorRect: anchor,
      width: 220,
      value: _type,
      items: [
        for (final type in TimeOffType.values)
          GlassMenuItem(
            value: type,
            label: context.t(type.labelKey),
            leading: Icon(
              timeOffIcon(type),
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
      ],
    );
    if (chosen != null && mounted) setState(() => _type = chosen);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showGlassDateRangePicker(
      context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialRange: _range,
      title: context.t('availability.timeOff.days'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = DateTimeRange(
        start: DateUtils.dateOnly(picked.start),
        end: DateUtils.dateOnly(picked.end),
      );
      if (!_singleDay) _halfDay = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final draft = TimeOffDraft(
      type: _type,
      from: _range.start,
      to: _range.end,
      halfDay: _halfDay && _singleDay,
      note: _note.text,
    );
    try {
      final repository = context.read<AvailabilityRepository>();
      final existing = widget.existing;
      if (existing?.id == null) {
        await repository.createTimeOff(draft);
      } else {
        await repository.updateTimeOff(existing!.id!, draft);
      }
      if (!mounted) return;
      showGlassToast(context, context.t('availability.timeOff.saved'));
      Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('availability.timeOff.delete'),
      message: context.t('availability.timeOff.deleteConfirm'),
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AvailabilityRepository>().deleteTimeOff(id);
      if (!mounted) return;
      showGlassToast(context, context.t('availability.timeOff.deleted'));
      Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (mounted) showGlassErrorToast(context, context.t(failure.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: timeOffIcon(_type),
          title: context.t(
            widget.existing == null
                ? 'availability.timeOff.add'
                : 'availability.timeOff.edit',
          ),
          subtitle: context.t('availability.timeOff.hint'),
          actions: [
            if (widget.existing?.id != null)
              IconButton(
                tooltip: context.t('availability.timeOff.delete'),
                onPressed: _saving ? null : _delete,
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FieldButton(
                icon: timeOffIcon(_type),
                label: context.t('availability.timeOff.type'),
                value: context.t(_type.labelKey),
                onTap: _pickType,
              ),
              const SizedBox(height: 10),
              _FieldButton(
                icon: LucideIcons.calendarRange,
                label: context.t('availability.timeOff.days'),
                value: formatDaySpan(context, _range.start, _range.end),
                onTap: (_) => _pickRange(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('availability.timeOff.halfDay'),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          context.t('availability.timeOff.halfDayHint'),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  HiveSwitch(
                    value: _halfDay && _singleDay,
                    onChanged: _singleDay
                        ? (value) => setState(() => _halfDay = value)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.t('availability.timeOff.note'),
                  helperText: context.t('availability.timeOff.noteHint'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                ),
              ),
            ],
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.save'),
          busy: _saving,
          onConfirm: _saving ? null : _save,
        ),
      ],
    );
  }
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

/// A row that opens a picker, handing it its own rectangle to hang from.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onTap(anchorRectOfContext(context)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 8),
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
    ),
  );
}

/// A form field that is a button: a picker opens from it, never a list inline.
class _FieldButton extends StatelessWidget {
  const _FieldButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      onTap: () => onTap(anchorRectOfContext(context)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkFaint),
          ],
        ),
      ),
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

/// Asks for the next page once it is built, the way a board reads on.
class _ReadOn extends StatefulWidget {
  const _ReadOn({required this.loading, required this.onReached});

  final bool loading;
  final Future<void> Function() onReached;

  @override
  State<_ReadOn> createState() => _ReadOnState();
}

class _ReadOnState extends State<_ReadOn> {
  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(_ReadOn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading && !widget.loading) _ask();
  }

  void _ask() {
    if (widget.loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.onReached());
    });
  }

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(12),
    child: Center(child: HiveLoader(size: 22)),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => unawaited(onRetry()),
          child: Text(context.t('common.retry')),
        ),
      ],
    ),
  );
}
