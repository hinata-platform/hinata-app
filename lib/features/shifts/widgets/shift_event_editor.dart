import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
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
      ),
      child: ShiftEventEditorBody(
        projectLocked: existing != null || projectId != null,
        plannable: plannable,
      ),
    ),
  );
  if (saved != null && context.mounted) {
    final overlaps = overlapNotice(context, saved.warnings);
    showGlassToast(
      context,
      overlaps ??
          context.t(
            existing == null
                ? 'shifts.plan.done.eventCreated'
                : 'shifts.plan.done.eventSaved',
          ),
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

  late final _title = TextEditingController(text: _cubit.state.title);
  late final _location = TextEditingController(text: _cubit.state.location);
  late final _description = TextEditingController(
    text: _cubit.state.description,
  );
  bool _moreOpen = false;

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

  Future<void> _save() async {
    final cubit = _cubit;
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
    final saved = await cubit.save();
    if (saved != null && mounted) Navigator.of(context).pop(saved);
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
          subtitle: context.t('shifts.plan.event.subtitle'),
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
