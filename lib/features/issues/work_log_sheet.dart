import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../sprint/modals/glass_modal.dart'
    show glassWoltSurface, showGlassDatePicker;

/// Log work on an issue (YouTrack work item): duration, activity, note.
Future<bool?> showWorkLogSheet(BuildContext context, String issueId) {
  final repository = context.read<IssueRepository>();
  return WoltModalSheet.show<bool?>(
    context: context,
    pageContentDecorator: glassWoltSurface,
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
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
                    child: Text(
                      context.t('time.activity.${activity.toLowerCase()}'),
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _activity = value ?? 'Development'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.calendarDays, size: 18),
              label: Text(
                MaterialLocalizations.of(context).formatShortDate(_date),
              ),
              onPressed: () async {
                final picked = await showGlassDatePicker(
                  context,
                  title: context.t('time.date'),
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<IssueRepository>().addWorkItem(
        widget.issueId,
        minutes: total,
        activityType: _activity,
        description: _note.text.trim().isEmpty ? null : _note.text.trim(),
        date: _date,
      );
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
