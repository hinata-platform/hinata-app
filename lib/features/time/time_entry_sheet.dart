import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/time_policy_cubit.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/models/time_policy_models.dart';
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
import 'tag_picker.dart';

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
/// A third act shares the form: **finishing a running timer**. Pass [timer]
/// with the [span] it measured and the sheet collects what the operator's policy
/// asks for that the timer does not carry, then stops it with the answers — one
/// request, so the entry is still the one the timer files under its own id. The
/// interval is shown and not edited: it came off the clock, which is the whole
/// point of having run one.
///
/// Resolves to the saved entry, or null if dismissed.
Future<SavedTimeEntry?> showTimeEntrySheet(
  BuildContext context, {
  WorkItem? entry,
  ({DateTime start, DateTime end})? span,
  RunningTimer? timer,
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
  // The policy travels the same way and for the same reason: the sheet marks
  // required fields and greys out a frozen day, and it is above the navigator
  // this modal rides on.
  final policy = context.read<TimePolicyCubit>();
  unawaited(policy.ensureLoaded());
  // And the timer cubit where there is a timer to finish, for the same reason:
  // the stop is the sheet's save, and the cubit is what owns that transition —
  // going around it would leave a bar counting a timer the server has ended.
  final timerCubit = timer == null ? null : context.read<TimerCubit>();
  return showGlassModal<SavedTimeEntry>(
    context,
    adaptive: true,
    width: 480,
    builder: (_) {
      final form = _TimeEntryForm(entry: entry, span: span, timer: timer);
      return MultiRepositoryProvider(
        providers: providers,
        child: BlocProvider<TimePolicyCubit>.value(
          value: policy,
          child: timerCubit == null
              ? form
              : BlocProvider<TimerCubit>.value(value: timerCubit, child: form),
        ),
      );
    },
  );
}

/// Which of the two shapes the form is editing.
enum _EntryMode { interval, duration }

class _TimeEntryForm extends StatefulWidget {
  const _TimeEntryForm({this.entry, this.span, this.timer});

  final WorkItem? entry;

  /// Hours swept out on the calendar, for a new entry. Opens the form on its
  /// interval side with those hours already in it — the drag was the answer to
  /// "when", and asking again would be asking twice.
  final ({DateTime start, DateTime end})? span;

  /// The running timer this sheet is finishing. See [showTimeEntrySheet].
  final RunningTimer? timer;

  @override
  State<_TimeEntryForm> createState() => _TimeEntryFormState();
}

class _TimeEntryFormState extends State<_TimeEntryForm> {
  /// The placement row, so the picker it opens can be anchored to it.
  final _placementKey = GlobalKey();

  /// The same, for the tag row.
  final _tagsKey = GlobalKey();

  late final TextEditingController _description = TextEditingController(
    text: widget.entry?.description ?? widget.timer?.description ?? '',
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
    projectId: widget.entry?.projectId ?? widget.timer?.projectId,
    issueId: widget.entry?.issueId ?? widget.timer?.issueId,
  );

  late String _activity =
      widget.entry?.activityType ?? widget.timer?.activityType ?? 'Development';

  late List<String> _tags = List.of(
    widget.entry?.tags ?? widget.timer?.tags ?? const <String>[],
  );

  /// Whether the tag field was opened and confirmed.
  ///
  /// A patch that mentions tags is an instruction to replace them, so an edit
  /// that only changes the duration must not mention them. Re-sending what was
  /// loaded looks harmless and is not: on an instance where only administrators
  /// may coin a word, an entry carrying a label from before the catalogue
  /// existed would be refused — its owner told to fix a tag they never touched,
  /// with no way through but to delete the label off their own record.
  bool _tagsTouched = false;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.entry != null;

  /// Whether this sheet is the last step of a stop rather than a form of its
  /// own. What differs: the interval is shown and not edited, the save is the
  /// stop, and cancelling leaves the timer running.
  bool get _isTimer => widget.timer != null;

  TimePolicySnapshot get _policy => context.watch<TimePolicyCubit>().state;

  /// The day this entry will be filed on — the interval's start day when there
  /// is one, the picked day otherwise. The same rule the save applies, so the
  /// lock is judged against the day the server will judge.
  DateTime get _filedOn => _mode == _EntryMode.interval
      ? DateTime(_start.year, _start.month, _start.day)
      : _day;

  /// The i18n key of the first rule this form does not satisfy, or null.
  ///
  /// Shown before the save rather than after it. A required field the server
  /// alone knows about is a save that fails on a form that looked complete, and
  /// the person has to guess which of six fields the sentence is about.
  String? _unmet(TimePolicySnapshot policy) {
    // The lock first: it is the one that cannot be fixed by typing.
    if (policy.isLocked(_filedOn) ||
        (_isEdit && policy.isLocked(widget.entry!.date))) {
      return 'time.policy.locked';
    }
    return policy.unmetBy(
      projectId: _placement.projectId,
      issueId: _placement.issueId,
      description: _description.text,
      tags: _tags,
      // Only a create settles the placement; see [TimePolicySnapshot.unmetBy].
      placement: !_isEdit,
    );
  }

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

  /// The same number as the summary line says it out loud.
  ///
  /// A timer stopped inside the minute it started measured no whole minute, and
  /// the summary would read "0 min" for an entry the server is about to file as
  /// one: it floors at one, because an entry may not be worth nothing. Showing
  /// the figure that will be stored is the honest half of a form whose length
  /// is not its own to decide.
  int? get _minutesShown => _isTimer && (_minutes ?? 0) < 1 ? 1 : _minutes;

  Future<void> _save() async {
    final minutes = _minutes;
    // Not for a timer: its length is the server's arithmetic, and the server
    // floors it at one minute. Judged here, a timer started and stopped inside
    // the same minute would be refused by a form that cannot change what it is
    // refusing — with the clock still running behind it.
    if (!_isTimer) {
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
      // The reporting day, always — including for an interval, where it is the
      // day the interval starts on.
      //
      // It used to be omitted here, and the server leaves a field a patch does
      // not mention alone. So moving an entry's hours from the 10th to the 20th
      // left it *filed* on the 10th: the month cell and the timesheet went on
      // counting it there, while the hour canvas — which places a block where
      // its hours are — drew it on neither day. Hours that exist, invisible in
      // the view people check their week in.
      //
      // The start's own day, read off the local wall clock the picker returned,
      // so an interval that crosses midnight files where it began — which is
      // what the running timer does too.
      date: interval ? DateTime(_start.year, _start.month, _start.day) : _day,
      startedAt: interval ? _start : null,
      endedAt: interval ? _end : null,
      activityType: _activity,
      description: _description.text.trim(),
      // Only what this sheet was asked to change: see [_tagsTouched]. On a
      // create every field is mentioned anyway.
      tags: _isEdit && !_tagsTouched ? null : _tags,
    );
    try {
      final saved = _isTimer
          ? await _stopTimer()
          : _isEdit
          ? await repository.update(widget.entry!.id, draft)
          : await repository.create(draft);
      if (!mounted) return;
      // A stop that the server refused answered null and said why in the cubit;
      // the sheet stays open with the sentence rather than closing on nothing.
      if (saved == null) return;
      Navigator.of(context).pop(saved);
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.toString();
      });
    }
  }

  /// Ends the running timer with what this form collected.
  ///
  /// One request, not a create followed by a discard: the entry a timer files
  /// carries the timer's own id, which is what makes a retried stop answer with
  /// the entry the first attempt made instead of writing a second one. Filing it
  /// by hand and then throwing the timer away would give that up — and would
  /// leave a duplicate behind whenever the second of the two calls failed.
  ///
  /// Billable is not sent, so the timer's own flag survives; there is no control
  /// for it on this form.
  Future<SavedTimeEntry?> _stopTimer() async {
    final cubit = context.read<TimerCubit>();
    final saved = await cubit.stop(
      // The end this form is showing, which is when stop was pressed — not when
      // the last required field was finally typed.
      endedAt: _end,
      projectId: _placement.projectId,
      issueId: _placement.issueId,
      description: _description.text.trim(),
      activityType: _activity,
      // Only what this sheet was asked to change, as on an edit. Sent, the
      // timer's own tags go back through the catalogue on the way out — and
      // that is the one thing that can refuse a stop: a tag deleted from the
      // catalogue mid-run, or an instance that limits who may use one. The
      // timer resolved them when it started; re-resolving them buys nothing
      // and puts a clock at risk.
      tags: _tagsTouched ? _tags : null,
    );
    if (saved == null && mounted) {
      // Inline, although [TimerSignals] toasts the same sentence app-wide. A
      // modal that stays open owes an answer inside itself: the toast lands
      // behind the sheet's own blur, and a refusal has to be readable next to
      // the field it is about.
      setState(() {
        _saving = false;
        _error = cubit.state.errorMessage ?? 'errors.unexpected';
      });
    }
    return saved;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final policy = _policy;
    final unmet = _unmet(policy);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: _isTimer ? LucideIcons.square : LucideIcons.clock,
          title: context.t(
            _isTimer
                ? 'time.timer.finish'
                : _isEdit
                ? 'time.entry.edit'
                : 'time.entry.new',
          ),
          subtitle: context.t(
            _isTimer ? 'time.timer.finishHint' : 'time.entry.subtitle',
          ),
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
                  // The save gate depends on whether this is empty — not on
                  // what it says — so the form is rebuilt when that flips and
                  // not once per keystroke.
                  onChanged: policy.requiredDescription
                      ? _descriptionChanged
                      : null,
                  decoration: InputDecoration(
                    labelText: _required(
                      context.t('time.entry.description'),
                      policy.requiredDescription,
                    ),
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
                  KeyedSubtree(
                    key: _placementKey,
                    child: _FieldButton(
                      icon: _placement.isUnfiled
                          ? LucideIcons.circleSlash
                          : LucideIcons.folder,
                      label: _required(
                        context.t('time.entry.placement'),
                        policy.requiresPlacement,
                      ),
                      value:
                          _placement.label ??
                          (_placement.isUnfiled
                              ? context.t('time.placement.none')
                              : context.t('time.placement.assigned')),
                      onTap: _pickPlacement,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // A timer's interval is not a field. It came off the clock, and
                // the two shapes below are the choice between typing a length
                // and typing hours — neither of which is what just happened.
                // Correcting it afterwards is what the entry's own editor is
                // for, where the times can move without the stop having to.
                if (_isTimer) ...[
                  _MeasuredInterval(start: _start, end: _end),
                ] else ...[
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
                ],
                const SizedBox(height: 12),
                _ActivityRow(
                  value: _activity,
                  onChanged: (value) => setState(() => _activity = value),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _tagsKey,
                  child: _FieldButton(
                    icon: LucideIcons.tag,
                    label: _required(
                      context.t('time.entry.tags'),
                      policy.requiredTag,
                    ),
                    value: _tags.isEmpty
                        ? context.t('time.tags.none')
                        : _tags.join(' · '),
                    onTap: () => _pickTags(policy),
                  ),
                ),
                const SizedBox(height: 12),
                _Summary(minutes: _minutesShown, error: _error),
                if (unmet != null) ...[
                  const SizedBox(height: 8),
                  // Under the total, not instead of it: the sheet is asking for a
                  // tag, and the ninety minutes somebody was checking should not
                  // leave the screen to say so.
                  _PolicyNote(text: context.t(unmet)),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t(_isTimer ? 'time.timer.stop' : 'common.save'),
          busy: _saving,
          onConfirm: _saving || unmet != null ? null : _save,
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
    final picked = await showTimePlacementPicker(
      context,
      // The row's own rectangle: on a wide window the picker hangs off the
      // field being edited. Without it every caller fell through to the bottom
      // sheet, so a desktop reader changing one field of a dialog got a panel
      // rising out of the bottom of the display.
      anchorRect: anchorRectOf(_placementKey),
      current: _placement,
    );
    if (picked == null || !mounted) return;
    setState(() => _placement = picked);
  }

  Future<void> _pickTags(TimePolicySnapshot policy) async {
    final picked = await showTimeTagPicker(
      context,
      anchorRect: anchorRectOf(_tagsKey),
      selected: _tags,
      // Whether a new word may be coined here is the operator's decision. The
      // row is absent rather than shown and refused.
      canCreate: !policy.limitTagAccess,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _tags = picked;
      _tagsTouched = true;
    });
  }

  /// A label with the marker that says the operator requires this field.
  static String _required(String label, bool required) =>
      required ? '$label *' : label;

  /// Whether the description was empty at the last rebuild.
  bool _descriptionWasEmpty = true;

  void _descriptionChanged(String value) {
    final empty = value.trim().isEmpty;
    if (empty == _descriptionWasEmpty) return;
    setState(() => _descriptionWasEmpty = empty);
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
/// The rule this sheet cannot satisfy yet, said under the total rather than in
/// place of it.
///
/// A different tone from [_Summary]'s error, deliberately: an unparseable
/// duration is a mistake in what was typed, an unmet policy is the operator's
/// rule arriving at somebody who has done nothing wrong.
class _PolicyNote extends StatelessWidget {
  const _PolicyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(LucideIcons.info, size: 15, color: AppColors.inkSoft),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
        ),
      ),
    ],
  );
}

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

/// The interval a timer measured: shown, not offered for editing.
///
/// A row rather than the two [_FieldButton]s the interval mode uses, because
/// those are controls and this is a fact. Nothing here can be changed by the
/// person reading it — the stop carries the timer's own start, so a picker would
/// be a control that closes and changes nothing.
class _MeasuredInterval extends StatelessWidget {
  const _MeasuredInterval({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    String at(DateTime moment) => localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(moment),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.timer, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.t('time.entry.measured'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${localizations.formatMediumDate(start)} · '
                  '${at(start)} – ${at(end)}',
                  // Not const: AppColors' neutrals are theme-aware getters.
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
