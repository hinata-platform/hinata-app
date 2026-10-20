import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_series.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/field_button.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassDatePicker,
        showGlassModal;
import '../bloc/shift_event_editor_cubit.dart' show SeriesRepeat;
import '../shift_texts.dart';
import 'shift_editor.dart' show DayChip, ShiftStepper;

/// What the picker came back with: the choice, and the rule behind "Eigene
/// Regel".
typedef SeriesRepeatPick = ({SeriesRepeat repeat, SeriesRule? rule});

/// "Wiederholen" (HIN-161): Nie, Täglich, Wöchentlich am Wochentag des
/// Beginns, Monatlich am Tag des Beginns, Eigene Regel. At the field on a wide
/// window, a sheet on a phone. Only "Eigene Regel" shows the weekdays, the
/// interval and the end, on a second page of the same panel.
///
/// [allowNever] is false for an occurrence of a series: a series is ended by
/// deleting from an occurrence on, not by switching its rule off.
Future<SeriesRepeatPick?> showSeriesRepeatPicker(
  BuildContext context, {
  required Rect? anchorRect,
  required DateTime start,
  required SeriesRepeat current,
  SeriesRule? custom,
  bool allowNever = true,
}) {
  Widget panel(BuildContext _) => SeriesRepeatPanel(
    start: start,
    current: current,
    custom: custom,
    allowNever: allowNever,
  );
  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  if (wide && anchorRect != null) {
    return showGlassAnchoredPopover<SeriesRepeatPick>(
      context,
      anchorRect: anchorRect,
      width: 420,
      minHeight: 340,
      maxHeight: 700,
      builder: panel,
    );
  }
  if (wide) {
    return showGlassModal<SeriesRepeatPick>(
      context,
      adaptive: false,
      width: 400,
      builder: panel,
    );
  }
  return showGlassBottomSheet<SeriesRepeatPick>(
    context,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheet).height * 0.85,
      ),
      child: panel(sheet),
    ),
  );
}

/// The picker's content: the five choices, or the custom rule.
class SeriesRepeatPanel extends StatefulWidget {
  const SeriesRepeatPanel({
    super.key,
    required this.start,
    required this.current,
    this.custom,
    this.allowNever = true,
  });

  final DateTime start;
  final SeriesRepeat current;
  final SeriesRule? custom;
  final bool allowNever;

  @override
  State<SeriesRepeatPanel> createState() => _SeriesRepeatPanelState();
}

class _SeriesRepeatPanelState extends State<SeriesRepeatPanel> {
  bool _custom = false;
  late SeriesRule _rule = widget.custom ?? SeriesRule.weekly(widget.start);

  static const int _defaultCount = 10;

  String get _locale => Localizations.localeOf(context).toLanguageTag();

  void _pick(SeriesRepeat repeat) =>
      Navigator.of(context).pop((repeat: repeat, rule: null));

  @override
  Widget build(BuildContext context) =>
      _custom ? _customPage(context) : _choices(context);

  Widget _choices(BuildContext context) {
    final start = widget.start;
    final weekday = DateFormat.EEEE(_locale).format(start);
    final rows = <(SeriesRepeat, IconData, String)>[
      if (widget.allowNever)
        (
          SeriesRepeat.never,
          LucideIcons.circleSlash,
          context.t('shifts.series.repeat.never'),
        ),
      (
        SeriesRepeat.daily,
        LucideIcons.repeat,
        context.t('shifts.series.repeat.daily'),
      ),
      (
        SeriesRepeat.weekly,
        LucideIcons.repeat,
        context.t('shifts.series.repeat.weekly', variables: {'day': weekday}),
      ),
      (
        SeriesRepeat.monthly,
        LucideIcons.repeat,
        context.t(
          'shifts.series.repeat.monthly',
          variables: {'day': start.day},
        ),
      ),
      (
        SeriesRepeat.custom,
        LucideIcons.slidersHorizontal,
        context.t('shifts.series.repeat.custom'),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(text: context.t('shifts.series.repeat.label')),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              for (final (repeat, icon, label) in rows)
                _ChoiceRow(
                  icon: icon,
                  label: label,
                  selected: repeat == widget.current,
                  trailing: repeat == SeriesRepeat.custom
                      ? LucideIcons.chevronRight
                      : null,
                  onTap: repeat == SeriesRepeat.custom
                      ? () => setState(() => _custom = true)
                      : () => _pick(repeat),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _weekdayShort(int weekday) =>
      // 1 January 2024 was a Monday.
      DateFormat.E(_locale).format(DateTime(2024, 1, weekday));

  String _intervalText(BuildContext context) => context.t(
    'shifts.series.custom.interval.${_rule.frequency.name}',
    count: _rule.interval,
  );

  Future<void> _pickUntil() async {
    final start = widget.start;
    final first = DateTime(start.year, start.month, start.day);
    final picked = await showGlassDatePicker(
      context,
      initialDate:
          _rule.until ?? DateTime(first.year, first.month + 3, first.day),
      firstDate: first,
      lastDate: DateTime(first.year + 3, first.month, first.day),
      title: context.t('shifts.series.custom.endUntil'),
    );
    if (picked != null && mounted) {
      setState(() => _rule = _rule.withEnd(until: picked));
    }
  }

  Widget _customPage(BuildContext context) {
    final rule = _rule;
    final weekly = rule.frequency == SeriesFrequency.weekly;
    final monthly = rule.frequency == SeriesFrequency.monthly;
    final days = rule.weekdays.isEmpty ? {widget.start.weekday} : rule.weekdays;
    final endKind = rule.count != null
        ? 1
        : rule.until != null
        ? 2
        : 0;
    final caption = TextStyle(
      fontSize: AppType.label,
      fontWeight: FontWeight.w700,
      color: AppColors.inkSoft,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: context.t('shifts.series.custom.back'),
                icon: const Icon(LucideIcons.chevronLeft, size: 20),
                onPressed: () => setState(() => _custom = false),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    context.t('shifts.series.repeat.custom'),
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in SeriesFrequency.values)
                      _ChoicePill(
                        label: context.t('shifts.series.custom.unit.${f.name}'),
                        selected: rule.frequency == f,
                        onTap: () => setState(
                          () => _rule = SeriesRule(
                            frequency: f,
                            interval: rule.interval,
                            weekdays: f == SeriesFrequency.weekly
                                ? days
                                : const {},
                            monthDay: f == SeriesFrequency.monthly
                                ? widget.start.day
                                : null,
                            count: rule.count,
                            until: rule.until,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ShiftStepper(
                  label: context.t('shifts.series.custom.every'),
                  value: _intervalText(context),
                  onMinus: rule.interval > 1
                      ? () => setState(
                          () => _rule = rule.copyWith(
                            interval: rule.interval - 1,
                          ),
                        )
                      : null,
                  onPlus: rule.interval < SeriesRule.maxInterval
                      ? () => setState(
                          () => _rule = rule.copyWith(
                            interval: rule.interval + 1,
                          ),
                        )
                      : null,
                ),
                if (weekly) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    header: true,
                    child: Text(
                      context.t('shifts.series.custom.days'),
                      style: caption,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                        DayChip(
                          label: _weekdayShort(d),
                          selected: days.contains(d),
                          onTap: () {
                            final next = {...days};
                            // The last day stays: a week without one is no rule.
                            if (next.length > 1 || !next.contains(d)) {
                              next.contains(d) ? next.remove(d) : next.add(d);
                            }
                            setState(
                              () => _rule = rule.copyWith(weekdays: next),
                            );
                          },
                        ),
                    ],
                  ),
                ],
                if (monthly) ...[
                  const SizedBox(height: 10),
                  Text(
                    context.t(
                      'shifts.series.custom.monthDay',
                      variables: {'day': rule.monthDay ?? widget.start.day},
                    ),
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    context.t('shifts.series.custom.end'),
                    style: caption,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ChoicePill(
                      label: context.t('shifts.series.custom.endNever'),
                      selected: endKind == 0,
                      onTap: () => setState(() => _rule = rule.withEnd()),
                    ),
                    _ChoicePill(
                      label: context.t('shifts.series.custom.endCount'),
                      selected: endKind == 1,
                      onTap: () => setState(
                        () => _rule = rule.withEnd(
                          count: rule.count ?? _defaultCount,
                        ),
                      ),
                    ),
                    _ChoicePill(
                      label: context.t('shifts.series.custom.endUntil'),
                      selected: endKind == 2,
                      onTap: () => _pickUntil(),
                    ),
                  ],
                ),
                if (rule.count case final count?) ...[
                  const SizedBox(height: 12),
                  ShiftStepper(
                    label: context.t('shifts.series.custom.endCount'),
                    value: context.t(
                      'shifts.series.custom.times',
                      count: count,
                    ),
                    onMinus: count > 1
                        ? () => setState(
                            () => _rule = rule.withEnd(count: count - 1),
                          )
                        : null,
                    onPlus: count < SeriesRule.maxCount
                        ? () => setState(
                            () => _rule = rule.withEnd(count: count + 1),
                          )
                        : null,
                  ),
                ],
                if (rule.until case final until?) ...[
                  const SizedBox(height: 12),
                  FieldButton(
                    icon: LucideIcons.calendarX,
                    label: context.t('shifts.series.custom.endUntil'),
                    value: dayLabel(context, until),
                    onTap: () => _pickUntil(),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop((
                repeat: SeriesRepeat.custom,
                rule: rule.frequency == SeriesFrequency.weekly
                    ? rule.copyWith(weekdays: days)
                    : rule,
              )),
              icon: const Icon(LucideIcons.check, size: 15),
              label: Text(context.t('shifts.series.custom.apply')),
            ),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppType.body,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                selected ? LucideIcons.circleCheck : icon,
                size: 17,
                color: selected ? AppColors.accentInk : AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppType.body,
                  color: AppColors.ink,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (trailing != null)
              ExcludeSemantics(
                child: Icon(trailing, size: 16, color: AppColors.inkSoft),
              ),
          ],
        ),
      ),
    ),
  );
}

/// One of several that exclude each other (how often, how it ends): a pill
/// with a check once chosen, unlike [DayChip], whose plus adds a day.
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? AppColors.accentInk : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.accentLine : AppColors.fieldRim,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  ExcludeSemantics(
                    child: Icon(LucideIcons.check, size: 15, color: ink),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
