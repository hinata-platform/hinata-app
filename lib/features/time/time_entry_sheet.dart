import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/duration_input.dart';
import '../../core/widgets/hive_widgets.dart';
import '../issues/work_item_labels.dart';
import '../sprint/modals/glass_modal.dart';
import 'placement_picker.dart';

/// Creates or edits one time entry.
///
/// The sheet is built around the two shapes an entry actually comes in, because
/// they are two different acts. **Duration** is what a person types when they
/// are recording that they worked ninety minutes on something yesterday; the
/// hours it occupied are not known and inventing them would be a lie. **Start
/// and end** is what a stopped timer leaves, and what somebody corrects when
/// the clock was running for the wrong twenty minutes. Offering only the second
/// forces the first to be fabricated, and offering only the first throws away
/// what a timer knew.
///
/// Resolves to the saved entry, or null if dismissed.
Future<SavedTimeEntry?> showTimeEntrySheet(
  BuildContext context, {
  WorkItem? entry,
  ({DateTime start, DateTime end})? span,
}) {
  // The sheet rides the root navigator, outside the app's provider scope, so
  // what it reads has to be carried across. Three repositories by name rather
  // than `domainRepositoryProviders`: that helper exists for modals whose
  // widget tree is open-ended, and this one's is not — naming them keeps the
  // sheet's dependencies visible and lets it be tested without standing up the
  // whole domain layer.
  final providers = [
    RepositoryProvider<TimeRepository>.value(
      value: context.read<TimeRepository>(),
    ),
    RepositoryProvider<ProjectRepository>.value(
      value: context.read<ProjectRepository>(),
    ),
    RepositoryProvider<IssueRepository>.value(
      value: context.read<IssueRepository>(),
    ),
  ];
  return showGlassModal<SavedTimeEntry>(
    context,
    adaptive: true,
    width: 480,
    builder: (_) => MultiRepositoryProvider(
      providers: providers,
      child: _TimeEntryForm(entry: entry, span: span),
    ),
  );
}

/// Which of the two shapes the form is editing.
enum _EntryMode { interval, duration }

class _TimeEntryForm extends StatefulWidget {
  const _TimeEntryForm({this.entry, this.span});

  final WorkItem? entry;

  /// Hours swept out on the calendar, for a new entry. Opens the form on its
  /// interval side with those hours already in it — the drag was the answer to
  /// "when", and asking again would be asking twice.
  final ({DateTime start, DateTime end})? span;

  @override
  State<_TimeEntryForm> createState() => _TimeEntryFormState();
}

class _TimeEntryFormState extends State<_TimeEntryForm> {
  late final TextEditingController _description = TextEditingController(
    text: widget.entry?.description ?? '',
  );
  late final TextEditingController _duration = TextEditingController(
    text: formatDurationInput(widget.entry?.durationMinutes ?? 60),
  );

  late _EntryMode _mode =
      widget.span != null ||
          (widget.entry?.startedAt != null && widget.entry?.endedAt != null)
      ? _EntryMode.interval
      : _EntryMode.duration;

  late DateTime _day = widget.span != null
      ? DateTime(
          widget.span!.start.year,
          widget.span!.start.month,
          widget.span!.start.day,
        )
      : _dayOf(widget.entry);
  late DateTime _start =
      widget.span?.start ?? widget.entry?.startedAt ?? _defaultStart();
  late DateTime _end =
      widget.span?.end ??
      widget.entry?.endedAt ??
      _defaultStart().add(const Duration(hours: 1));

  late TimePlacement _placement = TimePlacement(
    projectId: widget.entry?.projectId,
    issueId: widget.entry?.issueId,
  );

  late String _activity = widget.entry?.activityType ?? 'Development';

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.entry != null;

  static DateTime _dayOf(WorkItem? entry) {
    final date = entry?.date ?? DateTime.now();
    return DateTime(date.year, date.month, date.day);
  }

  /// An hour ago, on the hour — the start somebody correcting a forgotten entry
  /// is most likely to be adjusting from.
  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour);
  }

  @override
  void dispose() {
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  /// The minutes the form currently describes, or null when it describes none.
  int? get _minutes => switch (_mode) {
    _EntryMode.duration => parseDurationInput(_duration.text),
    _EntryMode.interval =>
      _end.isAfter(_start) ? _end.difference(_start).inMinutes : null,
  };

  Future<void> _save() async {
    final minutes = _minutes;
    if (minutes == null || minutes < 1) {
      setState(
        () => _error = _mode == _EntryMode.duration
            ? 'time.error.duration'
            : 'time.error.interval',
      );
      return;
    }
    if (minutes > 24 * 60) {
      setState(() => _error = 'time.error.tooLong');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = context.read<TimeRepository>();
    final interval = _mode == _EntryMode.interval;
    final draft = TimeEntryDraft(
      // Only a create places an entry; see the field above.
      projectId: _isEdit ? null : _placement.projectId,
      issueId: _isEdit ? null : _placement.issueId,
      // One of the two, never both: sending a duration alongside an interval
      // would leave the server to pick a winner, and the pair already defines
      // the length.
      durationMinutes: interval ? null : minutes,
      date: interval ? null : _day,
      startedAt: interval ? _start : null,
      endedAt: interval ? _end : null,
      activityType: _activity,
      description: _description.text.trim(),
    );
    try {
      final saved = _isEdit
          ? await repository.update(widget.entry!.id, draft)
          : await repository.create(draft);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.clock,
          title: context.t(_isEdit ? 'time.entry.edit' : 'time.entry.new'),
          subtitle: context.t('time.entry.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _description,
                  autofocus: !_isEdit,
                  maxLength: 2000,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: context.t('time.entry.description'),
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                ),
                // Creating only. `PATCH /time/entries/{id}` carries no project
                // or issue — the patch shape is shared with the 1.x route, where
                // moving an entry between projects is a different act with
                // different rules (it moves hours out of one project's reports
                // and into another's). Showing the field here would be a control
                // that closes the sheet, reports success, and changes nothing.
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  _FieldButton(
                    icon: _placement.isUnfiled
                        ? LucideIcons.circleSlash
                        : LucideIcons.folder,
                    label: context.t('time.entry.placement'),
                    value:
                        _placement.label ??
                        (_placement.isUnfiled
                            ? context.t('time.placement.none')
                            : context.t('time.placement.assigned')),
                    onTap: _pickPlacement,
                  ),
                ],
                const SizedBox(height: 14),
                _ModeToggle(
                  mode: _mode,
                  onChanged: (mode) => setState(() {
                    _mode = mode;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 12),
                if (_mode == _EntryMode.duration) ...[
                  _FieldButton(
                    icon: LucideIcons.calendar,
                    label: context.t('time.entry.day'),
                    value: localizations.formatFullDate(_day),
                    onTap: _pickDay,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _duration,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() => _error = null),
                          decoration: InputDecoration(
                            labelText: context.t('time.entry.duration'),
                            // The parser accepts far more than this, but a hint
                            // has to fit: these three are the notations people
                            // reach for first.
                            hintText: '1h 30m · 90m · 1:30',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusControl,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: context.t('time.entry.pickDuration'),
                        onPressed: _pickDuration,
                        icon: const Icon(LucideIcons.hourglass, size: 18),
                      ),
                    ],
                  ),
                ] else ...[
                  _FieldButton(
                    icon: LucideIcons.play,
                    label: context.t('time.entry.start'),
                    value: _formatMoment(context, _start),
                    onTap: () => _pickMoment(isStart: true),
                  ),
                  const SizedBox(height: 12),
                  _FieldButton(
                    icon: LucideIcons.square,
                    label: context.t('time.entry.end'),
                    value: _formatMoment(context, _end),
                    onTap: () => _pickMoment(isStart: false),
                  ),
                ],
                const SizedBox(height: 12),
                _ActivityRow(
                  value: _activity,
                  onChanged: (value) => setState(() => _activity = value),
                ),
                const SizedBox(height: 12),
                _Summary(minutes: _minutes, error: _error),
              ],
            ),
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

  String _formatMoment(BuildContext context, DateTime moment) {
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(moment)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(moment), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  Future<void> _pickPlacement() async {
    final picked = await showTimePlacementPicker(context, current: _placement);
    if (picked == null || !mounted) return;
    setState(() => _placement = picked);
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showGlassDatePicker(
      context,
      initialDate: _day,
      // The same window the server enforces, so the picker cannot offer a day
      // the save would refuse.
      firstDate: DateTime(now.year, now.month, now.day - 365),
      lastDate: DateTime(now.year, now.month, now.day),
      title: context.t('time.entry.day'),
    );
    if (picked == null || !mounted) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickDuration() async {
    final picked = await showGlassDurationPicker(
      context,
      initialMinutes: _minutes ?? 60,
      title: context.t('time.entry.duration'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _duration.text = formatDurationInput(picked);
      _error = null;
    });
  }

  Future<void> _pickMoment({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showGlassDateTimePicker(
      context,
      initial: isStart ? _start : _end,
      firstDate: DateTime(now.year, now.month, now.day - 365),
      // A day either side of today: an entry may not be in the future, but an
      // end at 00:30 belongs to a start on the previous evening.
      lastDate: DateTime(now.year, now.month, now.day + 1),
      title: context.t(isStart ? 'time.entry.start' : 'time.entry.end'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        // Moving the start drags the end with it rather than silently making
        // the entry invalid — the length is what the person was keeping.
        final length = _end.difference(_start);
        _start = picked;
        if (!_end.isAfter(_start)) _end = _start.add(length);
      } else {
        _end = picked;
      }
      _error = null;
    });
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _EntryMode mode;
  final ValueChanged<_EntryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeButton(
            icon: LucideIcons.hourglass,
            label: context.t('time.entry.modeDuration'),
            selected: mode == _EntryMode.duration,
            onTap: () => onChanged(_EntryMode.duration),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeButton(
            icon: LucideIcons.clock,
            label: context.t('time.entry.modeInterval'),
            selected: mode == _EntryMode.interval,
            onTap: () => onChanged(_EntryMode.interval),
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: selected ? AppColors.accentLine : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? AppColors.accentStrong : AppColors.inkSoft,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.accentStrong : AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The activity types, as chips. A fixed list rather than free text: it is what
/// the "time per activity" report groups by, and a typo would silently open a
/// seventh column. The list is shared with the 1.x work-log sheet, and it keeps
/// a value it does not recognise so an entry logged through MCP still shows
/// what it says.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('time.entry.activity'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final activity in workItemActivityChoices(value))
              _ActivityChip(
                label: activityLabel(context, activity),
                selected: activity == value,
                onTap: () => onChanged(activity),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : AppColors.hairline.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accentLine : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accentStrong : AppColors.inkSoft,
          ),
        ),
      ),
    ),
  );
}

/// What the form currently adds up to, or why it does not add up.
class _Summary extends StatelessWidget {
  const _Summary({required this.minutes, this.error});

  final int? minutes;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Row(
        children: [
          const Icon(
            LucideIcons.triangleAlert,
            size: 15,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.t(error!),
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(LucideIcons.equal, size: 15, color: AppColors.inkFaint),
        const SizedBox(width: 8),
        Text(
          fmtDuration(context, minutes),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// A one-line field that opens a picker — the app's rule against inline
/// selection lists, applied to the four fields this form has.
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 15, color: AppColors.inkFaint),
          ],
        ),
      ),
    ),
  );
}
