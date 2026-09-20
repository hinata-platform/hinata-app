import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart';

/// What somebody chose in the deadline editor.
///
/// Three outcomes rather than a nullable date, because "no deadline" and "a
/// deadline that follows the event" are different answers and the caller has to
/// send different things for them.
class DeadlineChoice {
  const DeadlineChoice.date(DateTime this.date) : offset = null, cleared = false;

  /// A rule, and the day it worked out to while the editor was open — null only
  /// where the project has no date to count from. The caller shows that day
  /// rather than claiming it is still waiting for one.
  const DeadlineChoice.offset(RelativeDate this.offset, {this.date})
    : cleared = false;

  const DeadlineChoice.cleared() : date = null, offset = null, cleared = true;

  /// A day somebody picked. Setting one clears any rule behind it, which is what
  /// keeps a deliberate decision from being overwritten the next time the event
  /// moves.
  final DateTime? date;

  /// A rule: so many days or weeks before or after the project's event date.
  final RelativeDate? offset;

  /// Neither: the deadline is removed.
  final bool cleared;
}

/// Opens the deadline editor: a popover beside the field on a wide window, a
/// sheet on a phone.
///
/// [resolve] answers what a rule works out to. It is a callback rather than a
/// repository because the arithmetic belongs to the server — weekends are easy,
/// the holidays of whichever calendar the project names are not — and because a
/// widget that takes a function can be tested without one.
Future<DeadlineChoice?> showDeadlineEditor(
  BuildContext context, {
  required String title,
  required DateTime? date,
  required RelativeDate? offset,
  required DateTime? eventDate,
  required Future<DateTime?> Function(RelativeDate offset) resolve,
  Rect? anchorRect,
  VoidCallback? onOpenProjectSettings,
}) {
  Widget body(BuildContext innerContext) => _DeadlineEditor(
    title: title,
    date: date,
    offset: offset,
    eventDate: eventDate,
    resolve: resolve,
    onOpenProjectSettings: onOpenProjectSettings,
  );

  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  if (wide && anchorRect != null) {
    return showGlassAnchoredPopover<DeadlineChoice>(
      context,
      anchorRect: anchorRect,
      width: 330,
      minHeight: 330,
      maxHeight: 480,
      builder: body,
    );
  }
  return showGlassBottomSheet<DeadlineChoice>(context, builder: body);
}

/// The two ways a deadline can be kept.
enum _Mode { date, offset }

class _DeadlineEditor extends StatefulWidget {
  const _DeadlineEditor({
    required this.title,
    required this.date,
    required this.offset,
    required this.eventDate,
    required this.resolve,
    this.onOpenProjectSettings,
  });

  final String title;
  final DateTime? date;
  final RelativeDate? offset;
  final DateTime? eventDate;
  final Future<DateTime?> Function(RelativeDate offset) resolve;
  final VoidCallback? onOpenProjectSettings;

  @override
  State<_DeadlineEditor> createState() => _DeadlineEditorState();
}

class _DeadlineEditorState extends State<_DeadlineEditor> {
  /// How long the field waits after a keystroke before asking the server. Long
  /// enough that typing "28" is one request rather than two, short enough that
  /// the answer arrives while somebody is still looking at the field.
  static const _debounce = Duration(milliseconds: 320);

  late _Mode _mode;
  late TextEditingController _amount;
  late RelativeDateUnit _unit;
  late bool _before;
  late bool _workingDays;
  DateTime? _date;

  Timer? _pending;
  DateTime? _resolved;
  bool _resolving = false;

  /// The rule the line on screen already answers, so the same one is not asked
  /// about twice — toggling working days off and on again, or retyping the same
  /// digit, would otherwise each cost a round trip for a date already shown.
  RelativeDate? _resolvedFor;

  /// Guards against an older answer overwriting a newer one: each request takes
  /// a number, and only the newest is allowed to write.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final offset = widget.offset;
    _mode = offset == null ? _Mode.date : _Mode.offset;
    _date = widget.date;
    _amount = TextEditingController(
      text: '${offset == null ? 4 : offset.magnitude}',
    );
    _unit = offset?.unit ?? RelativeDateUnit.weeks;
    _before = offset == null || offset.isBefore;
    _workingDays = offset?.basis == RelativeDateBasis.working;
    if (offset != null && widget.date != null) {
      // The date the issue carries *is* this rule's answer — the server writes it
      // on every save — so there is nothing to ask until somebody changes
      // something.
      _resolved = widget.date;
      _resolvedFor = offset;
    } else if (offset != null) {
      _scheduleResolve();
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    _amount.dispose();
    super.dispose();
  }

  /// The rule the form currently describes, or null while the number is empty
  /// or outside what the server accepts.
  RelativeDate? get _currentOffset {
    final magnitude = int.tryParse(_amount.text.trim());
    if (magnitude == null || magnitude < 0) return null;
    final offset = RelativeDate(
      amount: _before ? -magnitude : magnitude,
      unit: _unit,
      basis: _workingDays
          ? RelativeDateBasis.working
          : RelativeDateBasis.calendar,
    );
    return offset.withinLimits ? offset : null;
  }

  void _scheduleResolve() {
    _pending?.cancel();
    final offset = _currentOffset;
    if (offset == null || widget.eventDate == null) {
      setState(() {
        _resolved = null;
        _resolvedFor = null;
        _resolving = false;
      });
      return;
    }
    if (offset == _resolvedFor) return;
    setState(() => _resolving = true);
    _pending = Timer(_debounce, () => _resolve(offset));
  }

  Future<void> _resolve(RelativeDate offset) async {
    final ticket = ++_request;
    try {
      final date = await widget.resolve(offset);
      if (!mounted || ticket != _request) return;
      setState(() {
        _resolved = date;
        _resolvedFor = offset;
        _resolving = false;
      });
    } on Object {
      if (!mounted || ticket != _request) return;
      // A failed lookup is a line that stays blank, never an error on top of a
      // form somebody is still filling in. The server re-computes the date on
      // save regardless of what this line said.
      setState(() {
        _resolved = null;
        _resolvedFor = null;
        _resolving = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showGlassDatePicker(
      context,
      title: widget.title,
      initialDate: _date ?? widget.eventDate ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  void _submit() {
    if (_mode == _Mode.date) {
      final date = _date;
      Navigator.of(context).pop(
        date == null
            ? const DeadlineChoice.cleared()
            : DeadlineChoice.date(date),
      );
      return;
    }
    final offset = _currentOffset;
    if (offset == null) return;
    Navigator.of(context).pop(
      DeadlineChoice.offset(offset, date: offset == _resolvedFor ? _resolved : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _mode == _Mode.date || _currentOffset != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Text(
            widget.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassSegmented(
                  labels: [
                    context.t('issues.deadline.modeDate'),
                    context.t('issues.deadline.modeOffset'),
                  ],
                  selected: _mode.index,
                  onChanged: (index) {
                    setState(() => _mode = _Mode.values[index]);
                    if (_mode == _Mode.offset) _scheduleResolve();
                  },
                ),
                const SizedBox(height: 14),
                if (_mode == _Mode.date) _dateMode() else _offsetMode(),
              ],
            ),
          ),
        ),
        Container(height: 1, color: AppColors.hairline2),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          // A Wrap rather than a Row: three buttons carrying translated labels
          // do not fit a 330-pixel popover in every language, and a footer that
          // overflows is worse than one that takes a second line.
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 4,
            children: [
              if (widget.date != null || widget.offset != null)
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const DeadlineChoice.cleared()),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.inkSoft,
                  ),
                  child: Text(context.t('common.clear')),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
                child: Text(context.t('common.cancel')),
              ),
              FilledButton(
                onPressed: canSubmit ? _submit : null,
                child: Text(context.t('common.apply')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateMode() {
    final date = _date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassField(
          label: context.t('issues.deadline.fixedDate'),
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(color: AppColors.hairline2),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.calendar,
                    size: 15,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      date == null
                          ? context.t('issues.noValue')
                          : MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: date == null ? AppColors.inkFaint : AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.offset != null) ...[
          const SizedBox(height: 10),
          _Note(
            icon: LucideIcons.triangleAlert,
            text: context.t('issues.deadline.dateReplacesOffset'),
          ),
        ],
      ],
    );
  }

  Widget _offsetMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 74,
              child: GlassField(
                label: context.t('issues.deadline.amount'),
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: glassInputDecoration(),
                  onChanged: (_) => _scheduleResolve(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassField(
                label: context.t('issues.deadline.unit'),
                child: GlassSegmented(
                  labels: [
                    context.t('issues.deadline.unitDays'),
                    context.t('issues.deadline.unitWeeks'),
                  ],
                  selected: _unit == RelativeDateUnit.weeks ? 1 : 0,
                  onChanged: (index) {
                    setState(
                      () => _unit = index == 1
                          ? RelativeDateUnit.weeks
                          : RelativeDateUnit.days,
                    );
                    _scheduleResolve();
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassField(
          label: context.t('issues.deadline.direction'),
          child: GlassSegmented(
            labels: [
              context.t('issues.deadline.before'),
              context.t('issues.deadline.after'),
            ],
            selected: _before ? 0 : 1,
            onChanged: (index) {
              setState(() => _before = index == 0);
              _scheduleResolve();
            },
          ),
        ),
        const SizedBox(height: 12),
        _WorkingDaysRow(
          value: _workingDays,
          onChanged: (value) {
            setState(() => _workingDays = value);
            _scheduleResolve();
          },
        ),
        const SizedBox(height: 12),
        _result(),
      ],
    );
  }

  /// The date the rule works out to, or the reason there is none.
  Widget _result() {
    if (widget.eventDate == null) {
      return _Note(
        icon: LucideIcons.calendarOff,
        text: context.t('issues.deadline.noEventDate'),
        action: widget.onOpenProjectSettings == null
            ? null
            : context.t('issues.deadline.setEventDate'),
        onAction: widget.onOpenProjectSettings,
      );
    }
    final resolved = _resolved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.calendarCheck, size: 15, color: AppColors.inkSoft),
          const SizedBox(width: 9),
          Expanded(
            // Three states, not two: a date, a lookup in flight, and nothing to
            // say. Collapsing the last into "working it out" left the line
            // promising a date that was never coming — after a failed lookup, or
            // while the number field is empty.
            child: Text(
              resolved != null
                  ? MaterialLocalizations.of(context).formatMediumDate(resolved)
                  : (_resolving ? context.t('issues.deadline.calculating') : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: resolved == null ? AppColors.inkFaint : AppColors.ink,
              ),
            ),
          ),
          if (_resolving)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
        ],
      ),
    );
  }
}

/// The working-day switch and the sentence that says what it skips.
///
/// The sentence is not decoration: without a holiday calendar on the project a
/// working-day offset skips weekends and counts every holiday as an ordinary
/// day, and somebody setting "seven working days before" deserves to know that
/// before the deadline turns out to be a public holiday.
class _WorkingDaysRow extends StatelessWidget {
  const _WorkingDaysRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('issues.deadline.workingDays'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.t('issues.deadline.workingDaysHint'),
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        HiveSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// A short explanatory line with an optional way out of the problem it names.
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: AppColors.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
          if (action != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(action!, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "4 weeks before the event" — one rule, said in words.
///
/// Used under a deadline in the detail sheet and as the tooltip on the small
/// marker a list row carries, so the same rule reads the same way everywhere.
String offsetSentence(BuildContext context, RelativeDate offset) {
  final unit = offset.unit == RelativeDateUnit.weeks
      ? context.t('issues.deadline.weeks', count: offset.magnitude)
      : context.t('issues.deadline.days', count: offset.magnitude);
  final basis = offset.basis == RelativeDateBasis.working
      ? context.t('issues.deadline.workingSuffix')
      : '';
  return context.t(
    offset.isBefore
        ? 'issues.deadline.sentenceBefore'
        : 'issues.deadline.sentenceAfter',
    variables: {'amount': unit, 'basis': basis},
  );
}

/// A deadline that follows the event, shown as the date it lands on with a
/// small marker saying that it does.
///
/// The date stays the headline. Everything else in the product shows a date
/// there, and a row that suddenly read "4 weeks before" would make a list of
/// deadlines impossible to scan. The marker is what says there is a rule behind
/// it, and the tooltip says which.
class DeadlineOffsetLabel extends StatelessWidget {
  const DeadlineOffsetLabel({
    super.key,
    required this.offset,
    required this.date,
    this.compact = false,
  });

  final RelativeDate offset;

  /// The day the rule works out to, or null while the project has no event date
  /// — the rule is kept either way.
  final DateTime? date;

  /// Drops the text down to list-row size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sentence = offsetSentence(context, offset);
    final text = date == null
        ? context.t('issues.deadline.awaitingEventDate')
        : MaterialLocalizations.of(context).formatMediumDate(date!);
    return Tooltip(
      message: sentence,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.calendarClock,
            size: compact ? 12 : 14,
            color: AppColors.inkSoft,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w600,
                color: date == null ? AppColors.inkFaint : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
