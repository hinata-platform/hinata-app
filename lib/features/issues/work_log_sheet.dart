import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import 'work_item_labels.dart';
import '../sprint/modals/glass_modal.dart'
    show glassWoltSurface, showGlassDatePicker;

/// Log work on an issue (YouTrack work item): duration, activity, note.
///
/// With [existing] the same sheet corrects that entry instead: every field is
/// prefilled, the title says so, and saving patches only what changed.
/// Resolves to the patched [WorkItem] when an existing entry was corrected,
/// to `true` when a new one was logged, and to `false`/null when nothing was
/// written. Handing the entry back lets a list update the one row that changed
/// instead of starting its paging over.
Future<Object?> showWorkLogSheet(
  BuildContext context,
  String issueId, {
  WorkItem? existing,
}) {
  final repository = context.read<IssueRepository>();
  return WoltModalSheet.show<Object?>(
    context: context,
    pageContentDecorator: glassWoltSurface,
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        hasTopBarLayer: false,
        child: RepositoryProvider.value(
          value: repository,
          child: WorkLogForm(issueId: issueId, existing: existing),
        ),
      ),
    ],
  );
}

/// The sheet's body — public so it can be pumped without the modal around it.
///
/// Pops with `true` after a successful write. The date is drawn within the
/// server's rules (not in the future, at most a year back); an entry older
/// than that can still be corrected, its date just starts at the edge of the
/// picker rather than outside it.
class WorkLogForm extends StatefulWidget {
  const WorkLogForm({super.key, required this.issueId, this.existing});

  final String issueId;

  /// The entry being corrected; null logs a new one.
  final WorkItem? existing;

  @override
  State<WorkLogForm> createState() => _WorkLogFormState();
}

class _WorkLogFormState extends State<WorkLogForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hours;
  late final TextEditingController _minutes;
  late final TextEditingController _note;
  late String _activity;
  late DateTime _date;

  /// The canonical activities plus, when correcting, whatever the entry has —
  /// an MCP client may have logged one the app does not list, and a dropdown
  /// whose value is not among its items asserts.
  late final List<String> _activities;
  bool _saving = false;
  String? _error;

  WorkItem? get _existing => widget.existing;

  bool get _editing => _existing != null;

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    final minutes = existing?.durationMinutes ?? 60;
    _hours = TextEditingController(text: '${minutes ~/ 60}');
    _minutes = TextEditingController(text: '${minutes % 60}');
    _note = TextEditingController(text: existing?.description ?? '');
    _activity = existing?.activityType ?? workItemActivities.first;
    _date = existing?.date ?? DateTime.now();
    _activities = workItemActivityChoices(_activity);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t(_editing ? 'time.editEntry' : 'issues.logTime'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: context.t('time.hours'),
                    ),
                    validator: _numberValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: context.t('time.minutes'),
                    ),
                    validator: _numberValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _activity,
              decoration: InputDecoration(
                labelText: context.t('time.activityType'),
              ),
              items: [
                for (final activity in _activities)
                  DropdownMenuItem(
                    value: activity,
                    // The value stays the canonical English key sent to the API;
                    // only the visible label is localized.
                    child: Text(activityLabel(context, activity)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _activity = value ?? workItemActivities.first),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.calendarDays, size: 18),
              label: Text(
                MaterialLocalizations.of(context).formatShortDate(_date),
              ),
              onPressed: _pickDate,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: context.t('time.note')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: HiveLoader(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.t('common.save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateUtils.dateOnly(now.subtract(const Duration(days: 365)));
    final last = DateUtils.dateOnly(now);
    // The picker asserts on an initial date outside its range; an entry older
    // than the window (a legacy remainder, say) opens at the edge instead.
    final initial = _date.isBefore(first)
        ? first
        : _date.isAfter(last)
        ? last
        : _date;
    final picked = await showGlassDatePicker(
      context,
      title: context.t('time.date'),
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  String? _numberValidator(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 0) return context.t('errors.invalidNumber');
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final total =
        (int.tryParse(_hours.text) ?? 0) * 60 +
        (int.tryParse(_minutes.text) ?? 0);
    if (total <= 0) {
      setState(() => _error = context.t('errors.invalidNumber'));
      return;
    }
    final note = _note.text.trim();
    final repository = context.read<IssueRepository>();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = _existing;
      if (existing == null) {
        await repository.addWorkItem(
          widget.issueId,
          minutes: total,
          activityType: _activity,
          description: note.isEmpty ? null : note,
          date: _date,
        );
      } else {
        // Only what changed travels: the server leaves an absent field as it
        // is, and the audit entry then names exactly the corrected fields.
        final sameDate =
            existing.date != null && DateUtils.isSameDay(existing.date, _date);
        final sameNote = note == (existing.description ?? '').trim();
        if (total == existing.durationMinutes &&
            _activity == existing.activityType &&
            sameNote &&
            sameDate) {
          if (mounted) Navigator.of(context).pop(false);
          return;
        }
        final patched = await repository.updateWorkItem(
          existing.id,
          minutes: total == existing.durationMinutes ? null : total,
          activityType: _activity == existing.activityType ? null : _activity,
          description: sameNote ? null : note,
          date: sameDate ? null : _date,
        );
        if (mounted) Navigator.of(context).pop(patched);
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Localize like every other error surface here: context.t is idempotent
        // for already-localized backend text but maps a fallback key (e.g.
        // 'errors.unexpected') to real copy instead of leaking the raw key.
        _error = context.t(failure.message);
      });
    }
  }
}
