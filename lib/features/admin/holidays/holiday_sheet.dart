import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/availability_models.dart';
import '../../../core/repositories/availability_repository.dart';
import '../../../core/widgets/field_button.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../../account/account_widgets.dart';
import '../../sprint/modals/glass_modal.dart';

/// Opens the form for a new holiday of the calendar [calendarId] in [year], or
/// for [existing]. Resolves to true once it was saved.
Future<bool?> showHolidaySheet(
  BuildContext context, {
  required String calendarId,
  required int year,
  Holiday? existing,
}) {
  final repository = context.read<AvailabilityRepository>();
  return showGlassModal<bool>(
    context,
    adaptive: true,
    width: 420,
    builder: (sheetContext) => RepositoryProvider.value(
      value: repository,
      child: _HolidayForm(
        calendarId: calendarId,
        year: year,
        existing: existing,
      ),
    ),
  );
}

class _HolidayForm extends StatefulWidget {
  const _HolidayForm({
    required this.calendarId,
    required this.year,
    this.existing,
  });

  final String calendarId;
  final int year;
  final Holiday? existing;

  @override
  State<_HolidayForm> createState() => _HolidayFormState();
}

class _HolidayFormState extends State<_HolidayForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late DateTime _date = widget.existing?.date ?? _firstDayOfYearOrToday();
  late bool _halfDay = widget.existing?.halfDay ?? false;
  bool _saving = false;

  DateTime _firstDayOfYearOrToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    return today.year == widget.year ? today : DateTime(widget.year);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showGlassDatePicker(
      context,
      initialDate: _date,
      firstDate: DateTime(widget.year - 1),
      lastDate: DateTime(widget.year + 1, 12, 31),
      title: context.t('availability.admin.date'),
    );
    if (picked != null && mounted) {
      setState(() => _date = DateUtils.dateOnly(picked));
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showGlassErrorToast(
        context,
        context.t('availability.admin.nameRequired'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = context.read<AvailabilityRepository>();
      final existing = widget.existing;
      if (existing == null) {
        await repository.addHoliday(
          calendarId: widget.calendarId,
          date: _date,
          name: _name.text.trim(),
          halfDay: _halfDay,
        );
      } else {
        await repository.updateHoliday(
          existing.id,
          date: _date,
          name: _name.text.trim(),
          halfDay: _halfDay,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.calendarHeart,
        title: context.t(
          widget.existing == null
              ? 'availability.admin.addHoliday'
              : 'availability.admin.editHoliday',
        ),
        subtitle: context.t('availability.admin.holidayHint'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FieldButton(
              icon: LucideIcons.calendarDays,
              label: context.t('availability.admin.date'),
              value: MaterialLocalizations.of(context).formatFullDate(_date),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              maxLength: Holiday.nameMax,
              decoration: InputDecoration(
                labelText: context.t('availability.admin.name'),
              ),
            ),
            SettingRow(
              label: context.t('availability.admin.halfDay'),
              trailing: HiveSwitch(
                value: _halfDay,
                onChanged: (value) => setState(() => _halfDay = value),
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
