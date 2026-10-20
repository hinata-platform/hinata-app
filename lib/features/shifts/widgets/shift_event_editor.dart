import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/models/shift_series.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/field_button.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../../../core/widgets/project_picker.dart';
import '../../account/account_widgets.dart' show SettingRow;
import '../../sprint/modals/glass_modal.dart'
    show
        GlassModalFooter,
        GlassModalHeader,
        GlassToastKind,
        anchorRectOfContext,
        showGlassConfirm,
        showGlassDateTimePicker,
        showGlassModal,
        showGlassToast;
import '../bloc/shift_event_editor_cubit.dart';
import '../shift_texts.dart';
import '../shift_zones.dart';
import 'shift_editor.dart' show ShiftDisclosure;
import 'series_repeat_picker.dart';
import 'series_scope_dialog.dart';
import 'shift_plan_texts.dart';
import 'zone_picker.dart';

/// Opens the event editor (HIN-160): a new event, in [projectId] when the
/// calendar or list is narrowed to one (the field is then fixed), or
/// [existing] to change. [plannable] are the projects the caller may plan,
/// the only ones a new event can go into.
///
/// Resolves to the saved event, or null. A move that leaves people with two
/// places at once is said right after, as a hint.
Future<ShiftEventSaved?> showShiftEventEditor(
  BuildContext context, {
  ShiftEventDetail? existing,
  String? projectId,
  String? projectName,
  Set<String> plannable = const {},
  DateTime? day,
}) async {
  final repository = context.read<ShiftRepository>();
  final zone = await ShiftZones.deviceZone();
  if (!context.mounted) return null;
  final saved = await showGlassModal<ShiftEventSaved>(
    context,
    width: 560,
    builder: (_) => BlocProvider(
      create: (_) => ShiftEventEditorCubit(
        repository,
        existing: existing,
        projectId: projectId,
        projectName: projectName,
        deviceZone: zone,
        day: day,
      )..loadSeries(),
      child: ShiftEventEditorBody(
        projectLocked: existing != null || projectId != null,
        plannable: plannable,
      ),
    ),
  );
  if (saved != null && context.mounted) {
    final overlaps = overlapNotice(context, saved.warnings);
    final series = saved.series;
    showGlassToast(
      context,
      overlaps ??
          (series != null
              ? context.t(
                  'shifts.series.done.created',
                  count: series.occurrencesCreated ?? 0,
                )
              : context.t(
                  existing == null
                      ? 'shifts.plan.done.eventCreated'
                      : 'shifts.plan.done.eventSaved',
                )),
      kind: overlaps == null ? GlassToastKind.success : GlassToastKind.warning,
    );
  }
  return saved;
}

/// The event editor's form, for a cubit provided from outside (and in tests).
class ShiftEventEditorBody extends StatefulWidget {
  const ShiftEventEditorBody({
    super.key,
    this.projectLocked = false,
    this.plannable = const {},
  });

  final bool projectLocked;
  final Set<String> plannable;

  @override
  State<ShiftEventEditorBody> createState() => _ShiftEventEditorBodyState();
}

class _ShiftEventEditorBodyState extends State<ShiftEventEditorBody> {
  ShiftEventEditorCubit get _cubit => context.read<ShiftEventEditorCubit>();

  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _description;
  bool _moreOpen = false;

  @override
  void initState() {
    super.initState();
    // Made here rather than lazily: the description field is folded away at
    // first, and a lazy one would be created in dispose, after the cubit is
    // out of reach.
    final state = _cubit.state;
    _title = TextEditingController(text: state.title);
    _location = TextEditingController(text: state.location);
    _description = TextEditingController(text: state.description);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickProject(Rect? anchor) async {
    final picked = await showProjectPicker(
      context,
      anchorRect: anchor ?? Rect.zero,
      selected: {?_cubit.state.projectId},
      titleKey: 'shifts.plan.event.project',
      multi: false,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final project = picked.first;
    if (widget.plannable.isNotEmpty && !widget.plannable.contains(project.id)) {
      showGlassToast(
        context,
        context.t('shifts.plan.event.notPlannable'),
        kind: GlassToastKind.warning,
      );
      return;
    }
    _cubit.setProject(project.id, project.name);
  }

  Future<void> _pickTime({required bool start}) async {
    final s = _cubit.state;
    final now = DateTime.now();
    final picked = await showGlassDateTimePicker(
      context,
      initial: start ? s.start : s.end,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      title: context.t(
        start ? 'shifts.plan.event.start' : 'shifts.plan.event.end',
      ),
    );
    if (picked == null) return;
    start ? _cubit.setStart(picked) : _cubit.setEnd(picked);
  }

  Future<void> _pickZone(Rect? anchor) async {
    final zone = await showZonePicker(
      context,
      anchorRect: anchor ?? Rect.zero,
      selected: _cubit.state.timezone,
    );
    if (zone != null) _cubit.setTimezone(zone);
  }

  Future<void> _pickRepeat(Rect? anchor) async {
    final cubit = _cubit;
    final state = cubit.state;
    final picked = await showSeriesRepeatPicker(
      context,
      anchorRect: anchor,
      start: state.start,
      current: state.repeat,
      custom: state.customRule ?? state.rule,
      allowNever: !cubit.inSeries,
    );
    if (picked == null || !mounted) return;
    cubit.setRepeat(picked.repeat, custom: picked.rule);
  }

  Future<void> _save() async {
    final cubit = _cubit;
    ShiftScope? scope;
    if (await cubit.asksScope()) {
      if (!mounted) return;
      final summary = cubit.existing!.summary;
      scope = await askSeriesScope(
        context,
        write: SeriesWrite.save,
        day: summary.startsLocal,
        recurrenceLabel: summary.recurrenceLabel,
        singleLockedKey: cubit.ruleChanged
            ? 'shifts.series.scope.ruleOnlyFuture'
            : null,
      );
      if (scope == null || !mounted) return;
    }
    if (cubit.problem == null && cubit.zoneChangeMovesShifts) {
      final start = await cubit.startOnDevice();
      if (!mounted) return;
      final ok = await showGlassConfirm(
        context,
        icon: LucideIcons.globe,
        title: context.t('shifts.plan.event.zoneConfirmTitle'),
        message: context.t(
          'shifts.plan.event.zoneConfirm',
          count: cubit.existing!.shifts.length,
          variables: {
            'zone': cubit.state.timezone ?? '',
            'start':
                '${dayLabel(context, start)}, ${clockLabel(context, start)}',
          },
        ),
        confirmLabel: context.t('common.save'),
      );
      if (ok != true || !mounted) return;
    }
    final saved = await cubit.save(scope: scope);
    if (saved != null && mounted) Navigator.of(context).pop(saved);
  }

  /// "Wiederholen" in words: the server's, once it has said them.
  String _repeatValue(ShiftEventEditorCubit cubit, ShiftEventEditorState s) {
    if (s.repeat == SeriesRepeat.never) {
      return context.t('shifts.series.repeat.never');
    }
    final known = s.preview?.recurrenceLabel;
    if (known != null && known.isNotEmpty) return known;
    final current = cubit.existing?.summary.recurrenceLabel;
    if (current != null && !cubit.ruleChanged) return current;
    return switch (s.repeat) {
      SeriesRepeat.daily => context.t('shifts.series.repeat.daily'),
      SeriesRepeat.weekly => context.t(
        'shifts.series.repeat.weekly',
        variables: {'day': weekdayLabel(context, s.start)},
      ),
      SeriesRepeat.monthly => context.t(
        'shifts.series.repeat.monthly',
        variables: {'day': s.start.day},
      ),
      _ => context.t('shifts.series.repeat.custom'),
    };
  }

  /// The next dates the preview named, or why there is no preview.
  Widget? _repeatNote(ShiftEventEditorState s) {
    if (s.repeat == SeriesRepeat.never) return null;
    final error = s.previewErrorKey;
    if (error != null) {
      return _RepeatNote(
        icon: LucideIcons.circleAlert,
        text: planErrorText(context, error),
        error: true,
      );
    }
    final next = s.preview?.next ?? const <SeriesOccurrence>[];
    if (next.isEmpty) return null;
    return _RepeatNote(
      icon: LucideIcons.calendarDays,
      text: context.t(
        'shifts.series.next',
        variables: {
          'dates': [
            for (final o in next) dayLabel(context, o.date),
          ].join(' · '),
        },
      ),
    );
  }

  String? _problemText(ShiftEventProblem? problem) => switch (problem) {
    null => null,
    ShiftEventProblem.titleMissing => context.t('error.shifts.titleRequired'),
    ShiftEventProblem.projectMissing => context.t(
      'shifts.plan.event.projectMissing',
    ),
    ShiftEventProblem.endBeforeStart => context.t(
      'error.shifts.endBeforeStart',
    ),
    ShiftEventProblem.tooLong => context.t('error.shifts.eventTooLong'),
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftEventEditorCubit>().state;
    final cubit = context.read<ShiftEventEditorCubit>();
    final problem = state.attempted ? cubit.problem : null;
    final zone = state.timezone;
    final repeatNote = cubit.canRepeat ? _repeatNote(state) : null;
    final label = state.repeat == SeriesRepeat.never
        ? null
        : _repeatValue(cubit, state);
    final moreSummary = [
      ?zone,
      context.t(
        state.selfAssignable
            ? 'shifts.event.selfAssignOpen'
            : 'shifts.event.plannersOnly',
      ),
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: cubit.editing ? LucideIcons.squarePen : LucideIcons.partyPopper,
          title: context.t(
            cubit.editing
                ? 'shifts.plan.event.editTitle'
                : 'shifts.plan.event.newTitle',
          ),
          // A series says its rule in the head, in the server's words.
          subtitle: label ?? context.t('shifts.plan.event.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!cubit.editing) ...[
                  Builder(
                    builder: (anchor) => FieldButton(
                      icon: widget.projectLocked
                          ? LucideIcons.lock
                          : LucideIcons.folder,
                      label: context.t('shifts.plan.event.project'),
                      value:
                          state.projectName ??
                          context.t('shifts.plan.event.pickProject'),
                      empty: state.projectId == null,
                      onTap: widget.projectLocked
                          ? () {}
                          : () => unawaited(
                              _pickProject(anchorRectOfContext(anchor)),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _title,
                  onChanged: cubit.setTitle,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: context.t('shifts.plan.event.title'),
                    hintText: context.t('shifts.plan.event.titleHint'),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final start = FieldButton(
                      icon: LucideIcons.calendarClock,
                      label: context.t('shifts.plan.event.start'),
                      value:
                          '${dayLabel(context, state.start)}, ${clockLabel(context, state.start)}',
                      onTap: () => unawaited(_pickTime(start: true)),
                    );
                    final end = FieldButton(
                      icon: LucideIcons.calendarCheck,
                      label: context.t('shifts.plan.event.end'),
                      value:
                          '${dayLabel(context, state.end)}, ${clockLabel(context, state.end)}',
                      onTap: () => unawaited(_pickTime(start: false)),
                    );
                    if (constraints.maxWidth / scale >= 420) {
                      return Row(
                        children: [
                          Expanded(child: start),
                          const SizedBox(width: 10),
                          Expanded(child: end),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [start, const SizedBox(height: 10), end],
                    );
                  },
                ),
                if (cubit.canRepeat) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (anchor) => FieldButton(
                      icon: LucideIcons.repeat,
                      label: context.t('shifts.series.repeat.label'),
                      value: label ?? _repeatValue(cubit, state),
                      empty: state.repeat == SeriesRepeat.never,
                      onTap: () =>
                          unawaited(_pickRepeat(anchorRectOfContext(anchor))),
                    ),
                  ),
                  if (state.previewing && state.preview == null) ...[
                    const SizedBox(height: 6),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  if (repeatNote != null) ...[
                    const SizedBox(height: 6),
                    repeatNote,
                  ],
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _location,
                  onChanged: cubit.setLocation,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: context.t('shifts.plan.event.location'),
                    hintText: context.t('shifts.plan.event.locationHint'),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                ShiftDisclosure(
                  icon: LucideIcons.slidersHorizontal,
                  label: context.t('shifts.plan.event.more'),
                  summary: moreSummary,
                  open: _moreOpen,
                  onToggle: () => setState(() => _moreOpen = !_moreOpen),
                ),
                if (_moreOpen) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (anchor) => FieldButton(
                      icon: LucideIcons.globe,
                      label: context.t('shifts.plan.event.zone'),
                      value: zone ?? context.t('shifts.plan.event.zoneDevice'),
                      onTap: () =>
                          unawaited(_pickZone(anchorRectOfContext(anchor))),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.t('shifts.plan.event.zoneHint'),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      height: 1.4,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SettingRow(
                    label: context.t('shifts.plan.event.selfAssign'),
                    description: context.t('shifts.plan.event.selfAssignHint'),
                    trailing: HiveSwitch(
                      value: state.selfAssignable,
                      onChanged: cubit.setSelfAssignable,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _description,
                    onChanged: cubit.setDescription,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: context.t('shifts.plan.event.description'),
                    ),
                  ),
                ],
                if (_problemText(problem) ?? state.errorKey case final text?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: ExcludeSemantics(
                              child: Icon(
                                LucideIcons.circleAlert,
                                size: 15,
                                color: AppColors.dangerInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              problem == null
                                  ? planErrorText(context, text)
                                  : text,
                              style: TextStyle(
                                fontSize: AppType.label,
                                color: AppColors.dangerInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t(
            cubit.editing ? 'common.save' : 'shifts.plan.event.create',
          ),
          busy: state.saving,
          onConfirm: state.saving ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}

class _RepeatNote extends StatelessWidget {
  const _RepeatNote({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.dangerInk : AppColors.inkSoft;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(child: Icon(icon, size: 14, color: color)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.caption,
                height: 1.4,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
