import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/field_button.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        GlassModalFooter,
        GlassModalHeader,
        GlassToastKind,
        showGlassDatePicker,
        showGlassModal,
        showGlassTimePicker,
        showGlassToast;
import '../bloc/shift_editor_cubit.dart';
import '../shift_texts.dart';
import '../shift_zones.dart';
import 'series_scope_dialog.dart';
import 'shift_plan_texts.dart';

/// Opens the shift editor (HIN-160) for a new shift of [event] (on [day], or
/// its first day) or for [shift]. True when something was saved.
Future<bool> showShiftEditor(
  BuildContext context, {
  required ShiftEventSummary event,
  Shift? shift,
  DateTime? day,
}) async {
  final repository = context.read<ShiftRepository>();
  final zone = await ShiftZones.deviceZone();
  if (!context.mounted) return false;
  final saved = await showGlassModal<bool>(
    context,
    width: 540,
    builder: (_) => BlocProvider(
      create: (_) => ShiftEditorCubit(
        repository,
        event: event,
        shift: shift,
        day: day,
        deviceZone: zone,
      ),
      child: const ShiftEditorBody(),
    ),
  );
  if (saved == true && context.mounted) {
    showGlassToast(
      context,
      context.t(
        shift == null
            ? 'shifts.plan.done.shiftCreated'
            : 'shifts.plan.done.shiftSaved',
      ),
      kind: GlassToastKind.success,
    );
  }
  return saved ?? false;
}

/// The editor's form, for a cubit provided from outside (and in tests).
class ShiftEditorBody extends StatefulWidget {
  const ShiftEditorBody({super.key});

  @override
  State<ShiftEditorBody> createState() => _ShiftEditorBodyState();
}

class _ShiftEditorBodyState extends State<ShiftEditorBody> {
  late final TextEditingController _title;
  bool _daysOpen = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: context.read<ShiftEditorCubit>().state.title,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  ShiftEditorCubit get _cubit => context.read<ShiftEditorCubit>();

  Future<void> _pickDay() async {
    final cubit = _cubit;
    final days = cubit.eventDays;
    final picked = await showGlassDatePicker(
      context,
      initialDate: cubit.state.day,
      firstDate: days.first,
      lastDate: days.last,
      title: context.t('shifts.plan.shift.day'),
    );
    if (picked != null) cubit.setDay(picked);
  }

  Future<void> _pickTime({required bool from}) async {
    final cubit = _cubit;
    final minutes = from ? cubit.state.fromMinutes : cubit.state.toMinutes;
    final picked = await showGlassTimePicker(
      context,
      initial: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      title: context.t(
        from ? 'shifts.plan.shift.from' : 'shifts.plan.shift.to',
      ),
    );
    if (picked == null) return;
    final value = picked.hour * 60 + picked.minute;
    from ? cubit.setFrom(value) : cubit.setTo(value);
  }

  Future<void> _save() async {
    final cubit = _cubit;
    ShiftScope? scope;
    if (await cubit.asksScope()) {
      if (!mounted) return;
      scope = await askSeriesScope(
        context,
        write: cubit.editing ? SeriesWrite.editShift : SeriesWrite.addShift,
        day: cubit.state.day,
        recurrenceLabel: cubit.event.recurrenceLabel,
        futureLockedKey: cubit.state.extraDays.isEmpty
            ? null
            : 'shifts.series.scope.batchOnlyThis',
      );
      if (scope == null || !mounted) return;
    }
    if (await cubit.save(scope: scope) && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftEditorCubit>().state;
    final cubit = context.read<ShiftEditorCubit>();
    final event = cubit.event;
    final problem = state.attempted ? cubit.problem : null;
    final days = cubit.eventDays;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: cubit.editing
              ? LucideIcons.squarePen
              : LucideIcons.calendarPlus,
          title: context.t(
            cubit.editing
                ? 'shifts.plan.shift.editTitle'
                : 'shifts.plan.shift.newTitle',
          ),
          subtitle: event.title,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _title,
                  onChanged: cubit.setTitle,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.t('shifts.plan.shift.title'),
                    hintText: context.t('shifts.plan.shift.titleHint'),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                _TimeFields(
                  day: FieldButton(
                    icon: LucideIcons.calendar,
                    label: context.t('shifts.plan.shift.day'),
                    value: dayLabel(context, state.day),
                    onTap: () => unawaited(_pickDay()),
                  ),
                  from: FieldButton(
                    icon: LucideIcons.clock,
                    label: context.t('shifts.plan.shift.from'),
                    value: clockLabel(context, state.startWall),
                    onTap: () => unawaited(_pickTime(from: true)),
                  ),
                  to: FieldButton(
                    icon: LucideIcons.clock,
                    label: context.t('shifts.plan.shift.to'),
                    value: clockLabel(context, state.endWall),
                    onTap: () => unawaited(_pickTime(from: false)),
                  ),
                ),
                if (state.toMinutes < state.fromMinutes &&
                    state.toMinutes != state.fromMinutes) ...[
                  const SizedBox(height: 6),
                  _Note(
                    icon: LucideIcons.moon,
                    text: context.t('shifts.plan.shift.overnight'),
                  ),
                ],
                if (problem != null) ...[
                  const SizedBox(height: 6),
                  _Note(
                    icon: LucideIcons.triangleAlert,
                    error: true,
                    text: context.t(switch (problem) {
                      ShiftEditorProblem.endBeforeStart =>
                        'error.shifts.endBeforeStart',
                      ShiftEditorProblem.outsideEvent =>
                        'error.shifts.shiftOutsideEvent',
                    }),
                  ),
                ],
                const SizedBox(height: 18),
                Semantics(
                  header: true,
                  child: Text(
                    context.t('shifts.plan.shift.howMany'),
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Steppers(
                  needed: ShiftStepper(
                    label: context.t('shifts.plan.shift.needed'),
                    value: '${state.requiredHelpers}',
                    onMinus: state.requiredHelpers > 1
                        ? () => cubit.stepRequired(-1)
                        : null,
                    onPlus: () => cubit.stepRequired(1),
                  ),
                  max: ShiftStepper(
                    label: context.t('shifts.plan.shift.max'),
                    value: state.maxHelpers?.toString(),
                    placeholder: context.t('shifts.plan.shift.noMax'),
                    onMinus: cubit.canLowerMax ? () => cubit.stepMax(-1) : null,
                    onPlus: () => cubit.stepMax(1),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t('shifts.plan.shift.maxExplained'),
                  style: TextStyle(
                    fontSize: AppType.caption,
                    height: 1.4,
                    color: AppColors.inkSoft,
                  ),
                ),
                if (state.maxHelpers != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: cubit.clearMax,
                      child: Text(context.t('shifts.plan.shift.removeMax')),
                    ),
                  ),
                if (!cubit.editing && days.length > 1) ...[
                  const SizedBox(height: 12),
                  ShiftDisclosure(
                    icon: LucideIcons.copyPlus,
                    label: context.t('shifts.plan.shift.moreDays'),
                    summary: state.extraDays.isEmpty
                        ? context.t('shifts.plan.shift.onlyThisDay')
                        : context.t(
                            'shifts.plan.shift.extraDays',
                            count: state.extraDays.length,
                          ),
                    open: _daysOpen,
                    onToggle: () => setState(() => _daysOpen = !_daysOpen),
                  ),
                  if (_daysOpen || state.dayErrors.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in days)
                          if (d != state.day)
                            DayChip(
                              label: dayLabel(context, d),
                              selected: state.extraDays.contains(d),
                              failed: state.dayErrors.containsKey(d),
                              onTap: () => cubit.toggleExtraDay(d),
                            ),
                      ],
                    ),
                  ],
                ],
                if (state.errorKey != null) ...[
                  const SizedBox(height: 14),
                  _Note(
                    icon: LucideIcons.circleAlert,
                    error: true,
                    text: planErrorText(
                      context,
                      state.errorKey!,
                      state.errorDetails,
                    ),
                  ),
                  for (final entry in state.dayErrors.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 24,
                        top: 4,
                      ),
                      child: Text(
                        context.t(
                          'shifts.plan.shift.dayFailed',
                          variables: {
                            'day': dayLabel(context, entry.key),
                            'reason': context.t(entry.value),
                          },
                        ),
                        style: TextStyle(
                          fontSize: AppType.label,
                          color: AppColors.dangerInk,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.save'),
          busy: state.saving,
          onConfirm: state.saving ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}

/// Day, from and until: three in a row where they fit, else the day above
/// the two times, else one under the other (large text).
class _TimeFields extends StatelessWidget {
  const _TimeFields({required this.day, required this.from, required this.to});

  final Widget day;
  final Widget from;
  final Widget to;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final width = constraints.maxWidth / scale;
      if (width >= 440) {
        return Row(
          children: [
            Expanded(flex: 4, child: day),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: from),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: to),
          ],
        );
      }
      if (width >= 260) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            day,
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: from),
                const SizedBox(width: 10),
                Expanded(child: to),
              ],
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          day,
          const SizedBox(height: 10),
          from,
          const SizedBox(height: 10),
          to,
        ],
      );
    },
  );
}

class _Steppers extends StatelessWidget {
  const _Steppers({required this.needed, required this.max});

  final Widget needed;
  final Widget max;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth / scale >= 300) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: needed),
            const SizedBox(width: 10),
            Expanded(child: max),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [needed, const SizedBox(height: 10), max],
      );
    },
  );
}

/// A number with a minus and a plus, the glass field's rim around it. A null
/// [value] shows [placeholder] ("keine Obergrenze").
class ShiftStepper extends StatelessWidget {
  const ShiftStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.placeholder,
  });

  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final shown = value ?? placeholder ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          value: shown,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.fieldRim),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onMinus,
                  tooltip: context.t(
                    'shifts.plan.shift.less',
                    variables: {'label': label},
                  ),
                  icon: const Icon(LucideIcons.minus, size: 18),
                ),
                Expanded(
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        shown,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: value == null ? null : AppTheme.fontBrand,
                          fontSize: value == null
                              ? AppType.label
                              : AppType.heading,
                          fontWeight: FontWeight.w700,
                          color: value == null
                              ? AppColors.inkSoft
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onPlus,
                  tooltip: context.t(
                    'shifts.plan.shift.more',
                    variables: {'label': label},
                  ),
                  icon: const Icon(LucideIcons.plus, size: 18),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A folded section of a form: what it is, its value in words, a chevron.
class ShiftDisclosure extends StatelessWidget {
  const ShiftDisclosure({
    super.key,
    required this.icon,
    required this.label,
    required this.summary,
    required this.open,
    required this.onToggle,
  });

  final IconData icon;
  final String label;
  final String summary;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: open,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.fieldRim),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: 16, color: AppColors.inkSoft),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      summary,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Icon(
                  open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One day to put a shift on: a selectable pill, marked when the server
/// refused that day.
class DayChip extends StatelessWidget {
  const DayChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.failed = false,
  });

  final String label;
  final bool selected;
  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = failed
        ? AppColors.dangerInk
        : selected
        ? AppColors.accentInk
        : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
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
                color: failed
                    ? AppColors.danger
                    : selected
                    ? AppColors.accentLine
                    : AppColors.fieldRim,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    failed
                        ? LucideIcons.triangleAlert
                        : selected
                        ? LucideIcons.check
                        : LucideIcons.plus,
                    size: 15,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 6),
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

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.dangerInk : AppColors.inkSoft;
    return Semantics(
      liveRegion: error,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(child: Icon(icon, size: 15, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppType.label, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
