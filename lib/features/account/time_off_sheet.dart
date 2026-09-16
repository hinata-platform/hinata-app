import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/availability_models.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/field_button.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../sprint/modals/glass_modal.dart';
import '../time/day_marks.dart';
import 'account_widgets.dart';

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
  /// Around the type field, so its menu hangs off the field.
  final _typeKey = GlobalKey();
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

  Future<void> _pickType() async {
    final anchor = anchorRectOf(_typeKey);
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
              KeyedSubtree(
                key: _typeKey,
                child: FieldButton(
                  icon: timeOffIcon(_type),
                  label: context.t('availability.timeOff.type'),
                  value: context.t(_type.labelKey),
                  onTap: _pickType,
                ),
              ),
              const SizedBox(height: 10),
              FieldButton(
                icon: LucideIcons.calendarRange,
                label: context.t('availability.timeOff.days'),
                value: formatDaySpan(context, _range.start, _range.end),
                onTap: _pickRange,
              ),
              SettingRow(
                label: context.t('availability.timeOff.halfDay'),
                description: context.t('availability.timeOff.halfDayHint'),
                trailing: HiveSwitch(
                  value: _halfDay && _singleDay,
                  onChanged: _singleDay
                      ? (value) => setState(() => _halfDay = value)
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _note,
                maxLength: TimeOff.noteMax,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.t('availability.timeOff.note'),
                  helperText: context.t(
                    'availability.timeOff.noteHint',
                    variables: {'max': '${TimeOff.noteMax}'},
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
