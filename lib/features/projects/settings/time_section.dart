import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_policy_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/duration_input.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../sprint/modals/glass_modal.dart';
import 'settings_common.dart';

/// Project settings → Zeiterfassung: budget, default billability, whether this
/// project's timesheets are approved and on what rhythm.
///
/// It saves itself rather than joining the screen's draft and save bar, and that
/// is not an oversight: these live in a collection of their own, behind their
/// own route with their own permission, and a project rename that also silently
/// wrote a budget would be one save doing two things. The bar above stays about
/// the project document.
///
/// Every field can be empty, and empty is an answer: "whatever the instance
/// policy says". So an override is always removable — which is the whole reason
/// the block is nullable on the server too.
///
/// What a period <em>covers</em> is the server's arithmetic (HIN-88). This
/// screen chooses the rhythm and nothing more; no week or month is computed
/// here.
class ProjectTimeSection extends StatefulWidget {
  const ProjectTimeSection({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectTimeSection> createState() => _ProjectTimeSectionState();
}

class _ProjectTimeSectionState extends State<ProjectTimeSection> {
  static const _periods = <String>[
    'WEEKLY',
    'BIWEEKLY',
    'SEMI_MONTHLY',
    'MONTHLY',
    'QUARTERLY',
    'CUSTOM_DAYS',
    'FREE',
  ];

  final _budget = TextEditingController();

  ProjectTimeSettings _saved = const ProjectTimeSettings();
  ProjectTimeSettings _draft = const ProjectTimeSettings();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  bool get _dirty => _draft != _saved || _budgetMinutes != _saved.budgetMinutes;

  /// The budget the text field currently describes, or null when it describes
  /// none. A blank field is "no budget", which is different from a zero.
  int? get _budgetMinutes {
    final text = _budget.text.trim();
    if (text.isEmpty) return null;
    return parseDurationInput(text);
  }

  /// Whether the budget field matched what is stored at the last rebuild.
  bool _budgetWasSaved = true;

  void _budgetChanged(String value) {
    final saved = _budgetMinutes == _saved.budgetMinutes;
    if (saved == _budgetWasSaved) return;
    setState(() => _budgetWasSaved = saved);
  }

  Future<void> _load() async {
    try {
      final settings = await context.read<TimeRepository>().projectSettings(
        widget.projectId,
      );
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _draft = settings;
        _budget.text = settings.budgetMinutes == null
            ? ''
            : formatDurationInput(settings.budgetMinutes!);
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _save() async {
    if (_budget.text.trim().isNotEmpty && _budgetMinutes == null) {
      // parseDurationInput answers null both for "nothing here" and for "I
      // cannot read that". Treating the second as the first would delete the
      // budget over a typo and report success in a green toast.
      setState(() => _error = 'time.error.duration');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = await context.read<TimeRepository>().saveProjectSettings(
        widget.projectId,
        _draft.copyWith(
          budgetMinutes: _budgetMinutes,
          clearBudget: _budgetMinutes == null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _draft = settings;
        _saving = false;
      });
      showGlassToast(context, context.t('common.saved'));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('projectSettings.time.title'),
      note: context.t('projectSettings.time.note'),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: HiveLoader(size: 28)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel(text: context.t('projectSettings.time.budget')),
                const SizedBox(height: 6),
                TextField(
                  controller: _budget,
                  // The save button depends on whether the field differs from
                  // what is stored, which flips two or three times in an entry —
                  // not thirty. Rebuilding the card on every character would
                  // repaint four pickers and a loader to move one boolean.
                  onChanged: _budgetChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.t('projectSettings.time.budgetHint'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _TriChoice(
                  label: context.t('projectSettings.time.billable'),
                  value: _draft.defaultBillable,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      defaultBillable: value,
                      clearDefaultBillable: value == null,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _TriChoice(
                  label: context.t('projectSettings.time.approvalRequired'),
                  value: _draft.approvalRequired,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      approvalRequired: value,
                      clearApprovalRequired: value == null,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _PeriodChoice(
                  label: context.t('projectSettings.time.approvalPeriod'),
                  value: _draft.approvalPeriod,
                  options: _periods,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      approvalPeriod: value,
                      clearApprovalPeriod: value == null,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.t(_error!),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    onPressed: _dirty && !_saving ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: HiveLoader(size: 16),
                          )
                        : Text(context.t('common.save')),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A yes / no / "use the instance policy" row.
///
/// Three states rather than two, for the same reason every policy in the admin
/// area has three: absent is not off. A project that has never had an opinion
/// about billability follows whatever the instance decides — including when the
/// instance changes its mind — and a two-way switch would silently pin it.
class _TriChoice extends StatelessWidget {
  const _TriChoice({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ChoiceRow(
      label: label,
      value: switch (value) {
        null => context.t('projectSettings.time.inherit'),
        true => context.t('common.yes'),
        false => context.t('common.no'),
      },
      onTap: () async {
        final picked = await showGlassOptions<String>(
          context,
          title: label,
          options: [
            (
              value: 'inherit',
              child: Text(context.t('projectSettings.time.inherit')),
            ),
            (value: 'yes', child: Text(context.t('common.yes'))),
            (value: 'no', child: Text(context.t('common.no'))),
          ],
        );
        if (picked == null) return;
        onChanged(switch (picked) {
          'yes' => true,
          'no' => false,
          _ => null,
        });
      },
    );
  }
}

/// The submission rhythm, or the instance's.
class _PeriodChoice extends StatelessWidget {
  const _PeriodChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ChoiceRow(
      label: label,
      value: value == null
          ? context.t('projectSettings.time.inherit')
          : context.t('admin.timeTracking.period.${_key(value!)}'),
      onTap: () async {
        final picked = await showGlassOptions<String>(
          context,
          title: label,
          options: [
            (
              value: 'inherit',
              child: Text(context.t('projectSettings.time.inherit')),
            ),
            for (final option in options)
              (
                value: option,
                child: Text(
                  context.t('admin.timeTracking.period.${_key(option)}'),
                ),
              ),
          ],
        );
        if (picked == null) return;
        onChanged(picked == 'inherit' ? null : picked);
      },
    );
  }

  /// `SEMI_MONTHLY` → `semiMonthly`: the admin section already names these, and
  /// translating the same seven words twice is fourteen strings that have to be
  /// edited in pairs.
  static String _key(String wire) {
    final parts = wire.toLowerCase().split('_');
    return [
      parts.first,
      for (final part in parts.skip(1))
        part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1),
    ].join();
  }
}

/// One "label · value" row that opens a picker — never an inline list.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
