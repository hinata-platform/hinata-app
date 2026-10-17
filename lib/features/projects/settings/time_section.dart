import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../time/budget/budget_history_sheet.dart';
import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/models/billing_models.dart';
import '../../../core/repositories/billing_repository.dart';
import '../../billing/billing_format.dart';
import '../../../core/blocs/time_usage_cubit.dart';
import '../../../core/widgets/budget/budget.dart';
import '../../time/budget/project_usage.dart';
import '../../../core/api/api_client.dart';
import '../../../core/blocs/time_policy_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_policy_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/duration_input.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../sprint/modals/glass_modal.dart';
import 'project_time_settings_cubit.dart';
import 'settings_common.dart';
import '../../../core/theme/app_type.dart';

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
class ProjectTimeSection extends StatelessWidget {
  const ProjectTimeSection({super.key, required this.projectId});

  final String projectId;

  // Its own cubit, for the same reason it has its own save: the settings live
  // behind their own route, and the screen's draft knows nothing of them.
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => ProjectTimeSettingsCubit(
      context.read<TimeRepository>(),
      projectId: projectId,
    ),
    child: const _ProjectTimeSectionBody(),
  );
}

class _ProjectTimeSectionBody extends StatefulWidget {
  const _ProjectTimeSectionBody();

  @override
  State<_ProjectTimeSectionBody> createState() =>
      _ProjectTimeSectionBodyState();
}

class _ProjectTimeSectionBodyState extends State<_ProjectTimeSectionBody> {
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

  /// The money budget (HIN-155), in the instance's currency.
  final _money = TextEditingController();

  /// Billing's answer for this reader: the currency and whether they may set
  /// a cost budget. Null while billing is off, and then there is no field.
  BillingAccess? _billing;

  ProjectTimeSettings _saved = const ProjectTimeSettings();
  ProjectTimeSettings _draft = const ProjectTimeSettings();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // The thresholds are shown only while alerts exist on this instance.
    unawaited(context.read<TimePolicyCubit>().ensureLoaded());
  }

  @override
  void dispose() {
    _budget.dispose();
    _money.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _draft != _saved ||
      _budgetMinutes != _saved.budgetMinutes ||
      (_billing != null && _moneyCents != _saved.budgetCents);

  /// The money budget the field describes, or null for none.
  int? get _moneyCents => parseCents(_money.text);

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
    final saved =
        _budgetMinutes == _saved.budgetMinutes &&
        (_billing == null || _moneyCents == _saved.budgetCents);
    if (saved == _budgetWasSaved) return;
    setState(() => _budgetWasSaved = saved);
  }

  Future<void> _load() async {
    try {
      // Read before the first await, so no context crosses a gap.
      final cubit = context.read<ProjectTimeSettingsCubit>();
      // A money budget exists only while billing is on (HIN-155).
      final billingOn =
          context.read<AppConfigBloc>().state.meta?.billing ?? false;
      final billingRepository = context.read<BillingRepository>();
      final settings = await cubit.load();
      BillingAccess? billing;
      if (billingOn) {
        try {
          billing = await billingRepository.access();
        } on ApiFailure {
          billing = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _draft = settings;
        _billing = billing;
        _budget.text = settings.budgetMinutes == null
            ? ''
            : formatDurationInput(settings.budgetMinutes!);
        _money.text = billing == null || settings.budgetCents == null
            ? ''
            : basisPointsText(context, settings.budgetCents!);
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
    if (_billing != null &&
        _money.text.trim().isNotEmpty &&
        _moneyCents == null) {
      // The same rule for money: a typo never deletes a budget.
      setState(() => _error = 'budget.money.invalid');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = await context.read<ProjectTimeSettingsCubit>().save(
        _draft.copyWith(
          budgetMinutes: _budgetMinutes,
          clearBudget: _budgetMinutes == null,
          // Without billing the stored figure travels back untouched, so a
          // save here never removes a budget set while billing was on.
          budgetCents: _billing == null ? _saved.budgetCents : _moneyCents,
          clearBudgetCents: _billing != null && _moneyCents == null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _draft = settings;
        _saving = false;
      });
      showGlassToast(context, context.t('common.saved'));
      // A new budget or warning share changes what the bars say everywhere.
      unawaited(
        context.read<TimeUsageCubit>().refresh(
          context.read<ProjectTimeSettingsCubit>().projectId,
        ),
      );
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
                // The label above is plain text; this ties it to the field for
                // screen readers.
                Semantics(
                  label: context.t('projectSettings.time.budget'),
                  textField: true,
                  child: TextField(
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
                ),
                // A money budget beside it while billing is on (HIN-155).
                if (_billing case final billing?) ...[
                  const SizedBox(height: 14),
                  FieldLabel(text: context.t('budget.money.label')),
                  const SizedBox(height: 6),
                  Semantics(
                    label: context.t('budget.money.label'),
                    textField: true,
                    child: TextField(
                      controller: _money,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: _budgetChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText:
                            '${currencySymbol(context, billing.currency)} ',
                        hintText: context.t('budget.money.hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusControl,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Revenue or cost: the second only for an administrator,
                  // because cost rates can reveal a salary.
                  if (billing.costs) ...[
                    const SizedBox(height: 10),
                    _RateKindChoice(
                      label: context.t('budget.money.kind'),
                      value: _draft.budgetRateKind,
                      onChanged: (value) => setState(
                        () => _draft = _draft.copyWith(
                          budgetRateKind: value,
                          clearBudgetRateKind: value == null,
                        ),
                      ),
                    ),
                  ],
                ],
                // What the project has used against it, under the field that
                // sets it (HIN-152). Nothing while there is no budget and no
                // estimate to measure against.
                ProjectUsage(
                  projectId: context.read<ProjectTimeSettingsCubit>().projectId,
                  builder: (context, usage) {
                    final budget = usage?.budget;
                    final estimates = usage?.estimates;
                    final money = usage?.money;
                    if (budget == null && estimates == null && money == null) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (budget != null)
                            BudgetMeter(
                              label: context.t('budget.timeBudget'),
                              gauge: budget,
                              // When it runs out at the present pace, and the
                              // way to the burn-down (HIN-156).
                              footer: ProjectForecast(
                                projectId: usage!.projectId,
                                builder: (context, forecast) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (forecast != null)
                                      ForecastLine(forecast: forecast),
                                    TextButton.icon(
                                      onPressed: () => showBudgetHistorySheet(
                                        context,
                                        projectId: usage.projectId,
                                        projectName: context.t(
                                          'budget.subject.project',
                                        ),
                                      ),
                                      icon: const Icon(
                                        LucideIcons.chartArea,
                                        size: 16,
                                      ),
                                      label: Text(
                                        context.t('budget.history.open'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (budget != null && estimates != null)
                            const SizedBox(height: 18),
                          if (estimates != null)
                            BudgetMeter(
                              label: context.t('budget.estimates'),
                              gauge: estimates,
                            ),
                          if (money != null) ...[
                            const SizedBox(height: 18),
                            BudgetMeter(
                              label: context.t(
                                usage!.costBudget
                                    ? 'budget.money.cost'
                                    : 'budget.money.revenue',
                              ),
                              gauge: money,
                              format: (context, cents) =>
                                  formatMoney(context, cents, usage.currency!),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _ModeChoice(
                  label: context.t('projectSettings.time.budgetMode'),
                  value: _draft.budgetLimitMode,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      budgetLimitMode: value,
                      clearBudgetLimitMode: value == null,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _ModeChoice(
                  label: context.t('projectSettings.time.estimateMode'),
                  value: _draft.estimateLimitMode,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      estimateLimitMode: value,
                      clearEstimateLimitMode: value == null,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t(
                    context.select<TimePolicyCubit, bool>(
                          (cubit) => cubit.state.alertsEnabled,
                        )
                        ? 'projectSettings.time.modeHint'
                        : 'projectSettings.time.modeHintNoAlerts',
                  ),
                  style: TextStyle(
                    fontSize: AppType.caption,
                    height: 1.45,
                    color: AppColors.inkSoft,
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
                const SizedBox(height: 10),
                _LockBeforeRow(
                  label: context.t('projectSettings.time.lockBefore'),
                  helper: context.t('projectSettings.time.lockBeforeHint'),
                  value: _draft.lockBefore,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      lockBefore: value,
                      clearLockBefore: value == null,
                    ),
                  ),
                ),
                if (context.select<TimePolicyCubit, bool>(
                  (cubit) => cubit.state.alertsEnabled,
                )) ...[
                  const SizedBox(height: 10),
                  _PercentChoice(
                    label: context.t('projectSettings.time.budgetAlert'),
                    helper: context.t('projectSettings.time.budgetAlertHint'),
                    value: _draft.budgetAlertPercent,
                    fallback: ProjectTimeSettings.defaultBudgetAlertPercent,
                    options: const [50, 60, 70, 75, 80, 90],
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(
                        budgetAlertPercent: value,
                        clearBudgetAlert: value == null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PercentChoice(
                    label: context.t('projectSettings.time.estimateAlert'),
                    helper: context.t('projectSettings.time.estimateAlertHint'),
                    value: _draft.estimateAlertPercent,
                    fallback: ProjectTimeSettings.defaultEstimateAlertPercent,
                    options: const [80, 90, 100, 110, 125, 150],
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(
                        estimateAlertPercent: value,
                        clearEstimateAlert: value == null,
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.t(_error!),
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.dangerInk,
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

/// A freeze for this project alone, or the instance's.
///
/// Capped at today, like the instance-wide one and for the same reason: a freeze
/// that reached into the present would stop the recording of working time that is
/// happening right now, and the server answers 400 for it. And it only ever
/// closes *more* than the instance — the server takes the later of the two — so a
/// lead can close their own customer's books early but cannot reopen the month an
/// administrator archived.
class _LockBeforeRow extends StatelessWidget {
  const _LockBeforeRow({
    required this.label,
    required this.helper,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String helper;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final set = value;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: AppType.label, color: AppColors.ink),
              ),
              Text(
                helper,
                style: TextStyle(
                  fontSize: AppType.caption,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GhostButton(
          icon: LucideIcons.calendarOff,
          label: set == null
              ? context.t('projectSettings.time.instanceDefault')
              : localizations.formatMediumDate(set),
          onPressed: () => unawaited(_pick(context)),
        ),
        if (set != null)
          IconButton(
            tooltip: context.t('common.clear'),
            onPressed: () => onChanged(null),
            icon: Icon(LucideIcons.x, size: 15, color: AppColors.inkSoft),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showGlassDatePicker(
      context,
      initialDate: value != null && !value!.isAfter(today) ? value! : today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      title: label,
      onClear: () => onChanged(null),
    );
    if (picked != null) onChanged(picked);
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

/// Which rates value the money budget (HIN-155): revenue, or labour cost.
class _RateKindChoice extends StatelessWidget {
  const _RateKindChoice({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value ?? 'BILLABLE';
    return _ChoiceRow(
      label: label,
      value: context.t('budget.money.kinds.$current'),
      onTap: () async {
        final picked = await showGlassOptions<String>(
          context,
          title: label,
          options: [
            for (final kind in ProjectTimeSettings.rateKinds)
              (value: kind, child: Text(context.t('budget.money.kinds.$kind'))),
          ],
        );
        if (picked == null) return;
        onChanged(picked == 'BILLABLE' ? null : picked);
      },
    );
  }
}

/// What reaching a limit does (HIN-153), or the server's default. Never a
/// refusal: both modes let every entry through.
class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  String _name(BuildContext context, String mode) =>
      context.t('projectSettings.time.mode.$mode');

  @override
  Widget build(BuildContext context) {
    final current = value;
    return _ChoiceRow(
      label: label,
      value: current == null
          ? context.t(
              'projectSettings.time.modeDefault',
              variables: {
                'mode': _name(context, ProjectTimeSettings.defaultLimitMode),
              },
            )
          : _name(context, current),
      onTap: () async {
        final picked = await showGlassOptions<String>(
          context,
          title: label,
          options: [
            for (final mode in ProjectTimeSettings.limitModes)
              (value: mode, child: Text(_name(context, mode))),
          ],
        );
        if (picked == null) return;
        // The default is stored as no override, so it follows the server's.
        onChanged(
          picked == ProjectTimeSettings.defaultLimitMode ? null : picked,
        );
      },
    );
  }
}

/// A threshold in percent, or the default the server applies without one.
class _PercentChoice extends StatelessWidget {
  const _PercentChoice({
    required this.label,
    required this.helper,
    required this.value,
    required this.fallback,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String helper;
  final int? value;

  /// What the server applies while nothing is set.
  final int fallback;
  final List<int> options;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    String percent(int value) => context.t(
      'projectSettings.time.percent',
      variables: {'percent': value},
    );
    final defaultLabel = context.t(
      'projectSettings.time.alertDefault',
      variables: {'percent': fallback},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChoiceRow(
          label: label,
          value: value == null ? defaultLabel : percent(value!),
          onTap: () async {
            final picked = await showGlassOptions<int>(
              context,
              title: label,
              options: [
                (value: 0, child: Text(defaultLabel)),
                for (final option in options)
                  (value: option, child: Text(percent(option))),
              ],
            );
            if (picked == null) return;
            onChanged(picked == 0 ? null : picked);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            helper,
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
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
    // Opens a picker: a button, named by the label and value inside.
    return Semantics(
      button: true,
      child: InkWell(
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
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: AppType.label,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
