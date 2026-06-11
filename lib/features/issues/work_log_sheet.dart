import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';

/// Log work on an issue (YouTrack work item): duration, activity, note.
Future<bool?> showWorkLogSheet(BuildContext context, String issueId) {
  final repository = context.read<HivoraRepository>();
  return WoltModalSheet.show<bool?>(
    context: context,
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: AppColors.surface,
        hasTopBarLayer: false,
        child: RepositoryProvider.value(
          value: repository,
          child: _WorkLogBody(issueId: issueId),
        ),
      ),
    ],
  );
}

class _WorkLogBody extends StatefulWidget {
  const _WorkLogBody({required this.issueId});

  final String issueId;

  @override
  State<_WorkLogBody> createState() => _WorkLogBodyState();
}

class _WorkLogBodyState extends State<_WorkLogBody> {
  final _formKey = GlobalKey<FormState>();
  final _hours = TextEditingController(text: '1');
  final _minutes = TextEditingController(text: '0');
  final _note = TextEditingController();
  String _activity = 'Development';
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  static const _activities = [
    'Development',
    'Testing',
    'Documentation',
    'Design',
    'Meeting',
    'Support',
  ];

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
              context.t('issues.logTime'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: context.t('time.hours')),
                    validator: _numberValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: context.t('time.minutes')),
                    validator: _numberValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _activity,
              decoration:
                  InputDecoration(labelText: context.t('time.activityType')),
              items: [
                for (final activity in _activities)
                  DropdownMenuItem(value: activity, child: Text(activity)),
              ],
              onChanged: (value) =>
                  setState(() => _activity = value ?? 'Development'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(MaterialLocalizations.of(context).formatShortDate(_date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(labelText: context.t('time.note')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.t('common.save')),
            ),
          ],
        ),
      ),
    );
  }

  String? _numberValidator(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 0) return context.t('errors.invalidNumber');
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final total = (int.tryParse(_hours.text) ?? 0) * 60 +
        (int.tryParse(_minutes.text) ?? 0);
    if (total <= 0) {
      setState(() => _error = context.t('errors.invalidNumber'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<HivoraRepository>().addWorkItem(
            widget.issueId,
            minutes: total,
            activityType: _activity,
            description: _note.text.trim().isEmpty ? null : _note.text.trim(),
            date: _date,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}
