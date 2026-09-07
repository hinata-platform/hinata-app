import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../admin_form_helpers.dart';
import '../policy_controls.dart';

/// Admin → Zeiterfassung.
///
/// Two things live here. The master switch for the extended time-tracking
/// module — which is what `/api/v1/meta` reports as the platform flag
/// `advanced_time_tracking`, and therefore what decides whether the module's
/// routes exist for the apps at all. And the module's policies, every one of
/// them nullable: absent means the operator's environment decides, which is why
/// each control offers a way back to that state.
///
/// The policies with a co-determination note are not decoration either. A
/// setting that makes one person's working time legible to another is subject
/// to § 87 Abs. 1 Nr. 6 BetrVG (LPVG in the public sector) — objective
/// suitability for monitoring is enough — so the note sits at the switch, where
/// somebody is about to reach for it. They all default to off; the functions
/// behind them arrive in the later stages of HIN-60.
class AdminTimeTrackingSection extends StatefulWidget {
  const AdminTimeTrackingSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminTimeTrackingSection> createState() =>
      _AdminTimeTrackingSectionState();
}

class _AdminTimeTrackingSectionState extends State<AdminTimeTrackingSection> {
  Map<String, dynamic> get _tt =>
      (widget.settings['timeTracking'] ??= <String, dynamic>{})
          as Map<String, dynamic>;

  T? _value<T>(String key) => _tt[key] as T?;

  void _set(String key, Object? value) => setState(() => _tt[key] = value);

  /// Nested policy groups are read without being created: a group the operator
  /// never touched stays exactly as the server sent it — including absent —
  /// rather than being replaced by an empty object that means something else.
  Map<String, dynamic>? _group(String group) =>
      _tt[group] is Map<String, dynamic>
      ? _tt[group] as Map<String, dynamic>
      : null;

  T? _nested<T>(String group, String key) => _group(group)?[key] as T?;

  void _setNested(String group, String key, Object? value) {
    setState(() {
      final map = (_tt[group] ??= <String, dynamic>{}) as Map<String, dynamic>;
      map[key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminNote(text: context.t('admin.timeTracking.hint')),
        const SizedBox(height: 16),
        _module(context),
        const SizedBox(height: 16),
        _capture(context),
        const SizedBox(height: 16),
        _visibility(context),
        const SizedBox(height: 16),
        _reports(context),
        const SizedBox(height: 16),
        _billing(context),
        const SizedBox(height: 16),
        _privacy(context),
      ],
    );
  }

  // ── The module itself ──────────────────────────────────────────────────
  Widget _module(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.timer,
    title: context.t('admin.timeTracking.moduleTitle'),
    subtitle: context.t('admin.timeTracking.moduleHint'),
    children: [
      PolicySwitch(
        title: context.t('admin.timeTracking.advancedTitle'),
        description: context.t('admin.timeTracking.advancedHint'),
        value: _value<bool>('advancedEnabled'),
        onChanged: (v) => _set('advancedEnabled', v),
      ),
    ],
  );

  // ── What an entry must carry, and when it stops being editable ─────────
  Widget _capture(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.clipboardList,
    title: context.t('admin.timeTracking.captureTitle'),
    subtitle: context.t('admin.timeTracking.captureHint'),
    children: [
      for (final field in const [
        ('project', 'admin.timeTracking.requiredProject'),
        ('issue', 'admin.timeTracking.requiredIssue'),
        ('description', 'admin.timeTracking.requiredDescription'),
        ('tag', 'admin.timeTracking.requiredTag'),
      ])
        PolicySwitch(
          title: context.t('${field.$2}Title'),
          description: context.t('${field.$2}Hint'),
          value: _nested<bool>('requiredFields', field.$1),
          onChanged: (v) => _setNested('requiredFields', field.$1, v),
        ),
      const SizedBox(height: 8),
      PolicyDate(
        label: context.t('admin.timeTracking.lockBeforeLabel'),
        helper: context.t('admin.timeTracking.lockBeforeHint'),
        value: _value<String>('lockBefore'),
        onChanged: (v) => _set('lockBefore', v),
      ),
      PolicyChoice(
        label: context.t('admin.timeTracking.roundingModeLabel'),
        helper: context.t('admin.timeTracking.roundingModeHint'),
        value: _nested<String>('rounding', 'mode'),
        options: const {
          'UP': 'admin.timeTracking.roundingMode.up',
          'DOWN': 'admin.timeTracking.roundingMode.down',
          'NEAREST': 'admin.timeTracking.roundingMode.nearest',
        },
        onChanged: (v) => _setNested('rounding', 'mode', v),
      ),
      PolicyChoice(
        label: context.t('admin.timeTracking.roundingIncrementLabel'),
        helper: context.t('admin.timeTracking.roundingIncrementHint'),
        // The increment is a number on the wire but a fixed set of choices in
        // the UI — a free number field would invite 7-minute rounding.
        value: _nested<num>('rounding', 'increment')?.toInt().toString(),
        options: {
          for (final minutes in const [5, 10, 15, 30, 60])
            '$minutes': 'admin.timeTracking.increment.m$minutes',
        },
        onChanged: (v) =>
            _setNested('rounding', 'increment', v == null ? null : int.parse(v)),
      ),
      PolicySwitch(
        title: context.t('admin.timeTracking.limitTagAccessTitle'),
        description: context.t('admin.timeTracking.limitTagAccessHint'),
        value: _value<bool>('limitTagAccess'),
        onChanged: (v) => _set('limitTagAccess', v),
      ),
      PolicySwitch(
        title: context.t('admin.timeTracking.defaultBillableTitle'),
        description: context.t('admin.timeTracking.defaultBillableHint'),
        value: _value<bool>('defaultBillable'),
        onChanged: (v) => _set('defaultBillable', v),
      ),
      PolicySwitch(
        title: context.t('admin.timeTracking.icsImportTitle'),
        description: context.t('admin.timeTracking.icsImportHint'),
        value: _value<bool>('icsImportEnabled'),
        onChanged: (v) => _set('icsImportEnabled', v),
      ),
    ],
  );

  // ── Who sees whose time, and who signs it off ──────────────────────────
  Widget _visibility(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.eye,
    title: context.t('admin.timeTracking.visibilityTitle'),
    subtitle: context.t('admin.timeTracking.visibilityHint'),
    children: [
      PolicySwitch(
        title: context.t('admin.timeTracking.leadsSeeMemberEntriesTitle'),
        description: context.t('admin.timeTracking.leadsSeeMemberEntriesHint'),
        value: _value<bool>('leadsSeeMemberEntries'),
        onChanged: (v) => _set('leadsSeeMemberEntries', v),
        monitoring: true,
      ),
      PolicySwitch(
        title: context.t('admin.timeTracking.approvalsTitle'),
        description: context.t('admin.timeTracking.approvalsHint'),
        value: _value<bool>('approvalsEnabled'),
        onChanged: (v) => _set('approvalsEnabled', v),
        monitoring: true,
      ),
      const SizedBox(height: 8),
      // How often timesheets are handed in is an operator decision, never a
      // constant in the code: a monthly rhythm suits one organisation and a
      // free-chosen period another. The semantics and the period arithmetic
      // live on the server (HIN-88); this is where the choice is made.
      PolicyChoice(
        label: context.t('admin.timeTracking.approvalPeriodLabel'),
        helper: context.t('admin.timeTracking.approvalPeriodHint'),
        value: _nested<String>('approvalPeriod', 'type'),
        options: const {
          'WEEKLY': 'admin.timeTracking.period.weekly',
          'BIWEEKLY': 'admin.timeTracking.period.biweekly',
          'SEMI_MONTHLY': 'admin.timeTracking.period.semiMonthly',
          'MONTHLY': 'admin.timeTracking.period.monthly',
          'QUARTERLY': 'admin.timeTracking.period.quarterly',
          'CUSTOM_DAYS': 'admin.timeTracking.period.customDays',
          'FREE': 'admin.timeTracking.period.free',
        },
        onChanged: (v) => _setNested('approvalPeriod', 'type', v),
      ),
      PolicyChoice(
        label: context.t('admin.timeTracking.weekStartsOnLabel'),
        helper: context.t('admin.timeTracking.weekStartsOnHint'),
        value: _nested<String>('approvalPeriod', 'weekStartsOn'),
        options: const {
          'MONDAY': 'admin.timeTracking.weekday.monday',
          'TUESDAY': 'admin.timeTracking.weekday.tuesday',
          'WEDNESDAY': 'admin.timeTracking.weekday.wednesday',
          'THURSDAY': 'admin.timeTracking.weekday.thursday',
          'FRIDAY': 'admin.timeTracking.weekday.friday',
          'SATURDAY': 'admin.timeTracking.weekday.saturday',
          'SUNDAY': 'admin.timeTracking.weekday.sunday',
        },
        onChanged: (v) => _setNested('approvalPeriod', 'weekStartsOn', v),
      ),
      PolicyDate(
        label: context.t('admin.timeTracking.anchorDateLabel'),
        helper: context.t('admin.timeTracking.anchorDateHint'),
        value: _nested<String>('approvalPeriod', 'anchorDate'),
        onChanged: (v) => _setNested('approvalPeriod', 'anchorDate', v),
      ),
      PolicyNumber(
        label: context.t('admin.timeTracking.periodDaysLabel'),
        helper: context.t('admin.timeTracking.periodDaysHint'),
        suffix: context.t('admin.timeTracking.daysSuffix'),
        value: _nested<num>('approvalPeriod', 'days')?.toInt(),
        onChanged: (v) => _setNested('approvalPeriod', 'days', v),
      ),
    ],
  );

  // ── Everything that turns entries into an evaluation ───────────────────
  Widget _reports(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.chartLine,
    title: context.t('admin.timeTracking.reportsTitle'),
    subtitle: context.t('admin.timeTracking.reportsHint'),
    children: [
      PolicySwitch(
        title: context.t('admin.timeTracking.workloadReportsTitle'),
        description: context.t('admin.timeTracking.workloadReportsHint'),
        value: _value<bool>('workloadReportsEnabled'),
        onChanged: (v) => _set('workloadReportsEnabled', v),
        monitoring: true,
      ),
      PolicySwitch(
        title: context.t('admin.timeTracking.alertsTitle'),
        description: context.t('admin.timeTracking.alertsHint'),
        value: _value<bool>('alertsEnabled'),
        onChanged: (v) => _set('alertsEnabled', v),
        monitoring: true,
      ),
      PolicySwitch(
        title: context.t('admin.timeTracking.targetRemindersTitle'),
        description: context.t('admin.timeTracking.targetRemindersHint'),
        value: _value<bool>('targetRemindersEnabled'),
        onChanged: (v) => _set('targetRemindersEnabled', v),
        monitoring: true,
      ),
      PolicySwitch(
        title: context.t('admin.timeTracking.arbzgHintsTitle'),
        description: context.t('admin.timeTracking.arbzgHintsHint'),
        value: _value<bool>('arbzgHintsEnabled'),
        onChanged: (v) => _set('arbzgHintsEnabled', v),
        monitoring: true,
      ),
    ],
  );

  // ── Rates, costs and invoices ──────────────────────────────────────────
  Widget _billing(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.receiptText,
    title: context.t('admin.timeTracking.billingTitle'),
    subtitle: context.t('admin.timeTracking.billingHint'),
    children: [
      PolicySwitch(
        title: context.t('admin.timeTracking.billingEnabledTitle'),
        description: context.t('admin.timeTracking.billingEnabledHint'),
        value: _value<bool>('billingEnabled'),
        onChanged: (v) => _set('billingEnabled', v),
        // Profitability per person is a performance figure, whatever it is
        // called on the report.
        monitoring: true,
      ),
      const SizedBox(height: 8),
      PolicyText(
        label: context.t('admin.timeTracking.currencyLabel'),
        helper: context.t('admin.timeTracking.currencyHint'),
        hint: 'EUR',
        maxLength: 3,
        value: _value<String>('currency'),
        onChanged: (v) => _set('currency', v?.toUpperCase()),
      ),
    ],
  );

  // ── What is kept, and what people are told ─────────────────────────────
  Widget _privacy(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.shieldCheck,
    title: context.t('admin.timeTracking.privacyTitle'),
    subtitle: context.t('admin.timeTracking.privacyHint'),
    children: [
      PolicyNumber(
        label: context.t('admin.timeTracking.descriptionPurgeLabel'),
        helper: context.t('admin.timeTracking.descriptionPurgeHint'),
        suffix: context.t('admin.timeTracking.monthsSuffix'),
        value: _nested<num>('retention', 'descriptionPurgeMonths')?.toInt(),
        onChanged: (v) => _setNested('retention', 'descriptionPurgeMonths', v),
      ),
      PolicyNumber(
        label: context.t('admin.timeTracking.entryPurgeLabel'),
        helper: context.t('admin.timeTracking.entryPurgeHint'),
        suffix: context.t('admin.timeTracking.monthsSuffix'),
        value: _nested<num>('retention', 'entryPurgeMonths')?.toInt(),
        onChanged: (v) => _setNested('retention', 'entryPurgeMonths', v),
      ),
      PolicyText(
        label: context.t('admin.timeTracking.privacyNoticeLabel'),
        helper: context.t('admin.timeTracking.privacyNoticeHint'),
        maxLines: 5,
        value: _value<String>('privacyNotice'),
        onChanged: (v) => _set('privacyNotice', v),
      ),
    ],
  );
}
