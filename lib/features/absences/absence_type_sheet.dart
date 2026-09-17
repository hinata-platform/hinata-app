import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/field_button.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../account/account_widgets.dart';
import '../sprint/modals/glass_modal.dart';
import 'absence_labels.dart';

/// Opens the editor for a new absence type, or for [existing]. Resolves to true
/// once something was saved.
Future<bool?> showAbsenceTypeSheet(
  BuildContext context, {
  AbsenceType? existing,
}) {
  final repository = context.read<AbsenceRepository>();
  return showGlassModal<bool>(
    context,
    width: 520,
    builder: (sheetContext) => RepositoryProvider.value(
      value: repository,
      child: _AbsenceTypeForm(existing: existing),
    ),
  );
}

/// One absence type and every rule that belongs to it.
///
/// **Why the form refuses before the server does.** Four of the server's rules
/// are about combinations rather than values — an unlimited type has no quota
/// to accrue or carry, a type that counts against a quota needs one to count
/// against, a capped carryover needs a cap, and a sick type is never subject to
/// approval. The server refuses each of them outright rather than quietly
/// correcting, so the screen can say why; and this form keeps the fields in step
/// as they are switched, so nobody has to find out by pressing save. The server
/// still decides — this is politeness, not a second opinion.
class _AbsenceTypeForm extends StatefulWidget {
  const _AbsenceTypeForm({this.existing});

  final AbsenceType? existing;

  @override
  State<_AbsenceTypeForm> createState() => _AbsenceTypeFormState();
}

class _AbsenceTypeFormState extends State<_AbsenceTypeForm> {
  /// The longest name the server stores. Mirrors `TimeOffType.NAME_MAX`.
  static const int _nameMax = 60;

  /// Mirrors `TimeOffType.KEY_MAX`.
  static const int _keyMax = 40;

  /// A year of notice. Mirrors `TimeOffTypeService.MIN_NOTICE_DAYS_MAX`.
  static const int _minNoticeMax = 365;

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _key = TextEditingController(text: widget.existing?.key ?? '');

  late AbsenceKind _kind = widget.existing?.kind ?? AbsenceKind.other;
  late String _icon = widget.existing?.icon ?? 'calendar-off';
  late int? _hue = widget.existing?.hue;
  late bool _paid = widget.existing?.paid ?? true;
  late bool _counts = widget.existing?.countsAgainstBalance ?? true;
  late bool _unlimited = widget.existing?.unlimited ?? false;
  late bool _approval = widget.existing?.requiresApproval ?? false;
  late AbsenceApproverRule _approver =
      widget.existing?.approverRule ?? AbsenceApproverRule.teamLead;
  late bool _halfDays = widget.existing?.halfDaysAllowed ?? true;
  late bool _fraction = widget.existing?.fractionAllowed ?? false;
  late int _minNotice = widget.existing?.minNoticeDays ?? 0;
  late int _maxConsecutive = widget.existing?.maxConsecutiveDays ?? 0;
  late bool _negative = widget.existing?.negativeBalanceAllowed ?? false;
  late int _negativeLimit = widget.existing?.negativeLimitMilliDays ?? 0;
  late AbsenceVisibility _visibility =
      widget.existing?.visibility ?? AbsenceVisibility.busyOnly;
  late AbsenceAccrual _accrual =
      widget.existing?.accrual ?? AbsenceAccrual.annual;
  late int _allowance = widget.existing?.allowanceMilliDays ?? 20 * kMilliDay;
  late DateTime _yearStart = _monthDay(
    widget.existing?.yearAnchorMonth ?? 1,
    widget.existing?.yearAnchorDay ?? 1,
  );
  late int _waiting = widget.existing?.waitingPeriodMonths ?? 6;
  late bool _prorateJoin = widget.existing?.prorateOnJoin ?? true;
  late bool _prorateLeave = widget.existing?.prorateOnLeave ?? true;
  late AbsenceCarryover _carryover =
      widget.existing?.carryover ?? AbsenceCarryover.none;
  late int _carryoverCap = widget.existing?.carryoverCapMilliDays ?? 0;
  late DateTime _carryoverExpires = _monthDay(
    widget.existing?.carryoverExpiresMonth ?? 3,
    widget.existing?.carryoverExpiresDay ?? 31,
  );
  late bool _active = widget.existing?.active ?? true;

  bool _saving = false;

  bool get _isNew => widget.existing == null;
  bool get _isSystem => widget.existing?.isSystem ?? false;

  /// § 5 EFZG: sickness is reported, not applied for. The switch is not merely
  /// off for this category, it is not a question (R11).
  bool get _approvalPossible => _kind != AbsenceKind.sick;

  /// A year that is not a leap year, so 29 February cannot be picked as an
  /// anchor that exists in three years out of four.
  static DateTime _monthDay(int month, int day) => DateTime(2026, month, day);

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  // --- keeping the combinations coherent --------------------------------------

  void _setUnlimited(bool value) => setState(() {
    _unlimited = value;
    if (value) {
      // An unlimited type has no quota to count against, accrue to or carry.
      _counts = false;
      _allowance = 0;
      _accrual = AbsenceAccrual.none;
      _carryover = AbsenceCarryover.none;
    }
  });

  void _setCounts(bool value) => setState(() {
    _counts = value;
    if (value) {
      _unlimited = false;
      // Counting against nothing is the one combination the server refuses
      // without being able to guess what was meant.
      if (_accrual == AbsenceAccrual.none && _allowance == 0) {
        _accrual = AbsenceAccrual.annual;
        _allowance = 20 * kMilliDay;
      }
    }
  });

  void _setKind(AbsenceKind value) => setState(() {
    _kind = value;
    if (value == AbsenceKind.sick) _approval = false;
  });

  // --- pickers ------------------------------------------------------------------

  Future<void> _pick<T>({
    required BuildContext anchor,
    required String title,
    required List<(T, String)> options,
    required ValueChanged<T> onPicked,
  }) async {
    final rect = anchorRectOfContext(anchor);
    final picked = await showGlassOptions<T>(
      context,
      title: title,
      anchorRect: rect,
      options: [
        for (final option in options)
          (value: option.$1, child: Text(option.$2)),
      ],
    );
    if (picked != null && mounted) onPicked(picked);
  }

  Future<void> _pickMonthDay(
    DateTime current,
    ValueChanged<DateTime> onPicked,
    String title,
  ) async {
    final picked = await showGlassDatePicker(
      context,
      initialDate: current,
      firstDate: DateTime(2026),
      lastDate: DateTime(2026, 12, 31),
      title: title,
    );
    if (picked != null && mounted) onPicked(DateUtils.dateOnly(picked));
  }

  // --- saving ---------------------------------------------------------------------

  Map<String, dynamic> get _body => {
    if (_isNew) 'key': _key.text.trim(),
    'name': _name.text.trim(),
    'icon': _icon,
    'hue': ?_hue,
    'kind': _kind.wire,
    'paid': _paid,
    'countsAgainstBalance': _counts,
    'unlimited': _unlimited,
    'approvalRequired': _approvalPossible && _approval,
    'approverRule': _approver.wire,
    'halfDaysAllowed': _halfDays,
    'fractionAllowed': _fraction,
    'minNoticeDays': _minNotice,
    // Absent rather than zero: the server reads null as "no limit", and zero as
    // a limit of zero days it then refuses.
    'maxConsecutiveDays': _maxConsecutive > 0 ? _maxConsecutive : null,
    'negativeBalanceAllowed': _negative,
    'negativeLimitMilliDays': _negative ? _negativeLimit : null,
    'visibility': _visibility.wire,
    'accrual': _accrual.wire,
    'allowanceMilliDays': _allowance,
    'yearAnchorMonth': _yearStart.month,
    'yearAnchorDay': _yearStart.day,
    'waitingPeriodMonths': _waiting,
    'prorateOnJoin': _prorateJoin,
    'prorateOnLeave': _prorateLeave,
    'carryover': _carryover.wire,
    'carryoverCapMilliDays': _carryover == AbsenceCarryover.capped
        ? _carryoverCap
        : null,
    'carryoverExpiresMonth': _carryoverExpires.month,
    'carryoverExpiresDay': _carryoverExpires.day,
    'active': _active,
  };

  Future<void> _save() async {
    final name = _name.text.trim();
    // A built-in may go back to its translated label; anything else needs a name
    // somebody chose, because nothing else would print.
    if (name.isEmpty && !_isSystem) {
      showGlassErrorToast(context, context.t('error.timeOff.typeNameRequired'));
      return;
    }
    if (_isNew && _key.text.trim().isEmpty) {
      showGlassErrorToast(context, context.t('error.timeOff.typeKeyInvalid'));
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = context.read<AbsenceRepository>();
      final existing = widget.existing;
      if (existing == null) {
        await repository.createType(_body);
      } else {
        await repository.updateType(existing.id, _body);
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
        icon: absenceIcon(_icon),
        title: context.t(_isNew ? 'absence.types.new' : 'absence.types.edit'),
        subtitle: context.t(
          _isSystem ? 'absence.types.system' : 'absence.types.cardHint',
        ),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._basics(context),
              ..._rules(context),
              ..._quota(context),
            ],
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('common.save'),
        busy: _saving,
        onConfirm: _saving ? null : _save,
      ),
    ],
  );

  // --- the three groups ------------------------------------------------------------

  List<Widget> _basics(BuildContext context) => [
    _Heading(context.t('absence.types.basics')),
    TextField(
      controller: _name,
      autofocus: _isNew,
      maxLength: _nameMax,
      decoration: InputDecoration(
        labelText: context.t('absence.types.name'),
        helperText: _isSystem ? context.t('absence.types.nameHint') : null,
        helperMaxLines: 3,
      ),
    ),
    if (_isNew) ...[
      const SizedBox(height: 4),
      TextField(
        controller: _key,
        maxLength: _keyMax,
        inputFormatters: [
          // The server's own shape for a key, applied while typing rather than
          // explained after a refused save.
          FilteringTextInputFormatter.allow(RegExp('[a-z0-9_-]')),
        ],
        decoration: InputDecoration(
          labelText: context.t('absence.types.key'),
          helperText: context.t('absence.types.keyHint'),
          helperMaxLines: 3,
        ),
      ),
    ],
    const SizedBox(height: 4),
    Builder(
      builder: (anchor) => FieldButton(
        icon: LucideIcons.shapes,
        label: context.t('absence.types.kind'),
        value: context.t(_kind.labelKey),
        onTap: _isSystem
            // The kind is what the module knows about a built-in: changing it
            // would make "sickness" something that can be applied for.
            ? () => showGlassErrorToast(
                context,
                context.t('error.timeOff.typeSystemKind'),
              )
            : () => _pick<AbsenceKind>(
                anchor: anchor,
                title: context.t('absence.types.kind'),
                options: [
                  for (final kind in AbsenceKind.values)
                    (kind, context.t(kind.labelKey)),
                ],
                onPicked: _setKind,
              ),
      ),
    ),
    const SizedBox(height: 10),
    _iconRow(context),
    const SizedBox(height: 10),
    _hueRow(context),
    SettingRow(
      label: context.t('absence.types.paid'),
      description: context.t('absence.types.paidHint'),
      trailing: HiveSwitch(
        value: _paid,
        onChanged: (value) => setState(() => _paid = value),
      ),
    ),
    SettingRow(
      label: context.t('absence.types.active'),
      description: context.t('absence.types.activeHint'),
      trailing: HiveSwitch(
        value: _active,
        onChanged: (value) => setState(() => _active = value),
      ),
    ),
  ];

  List<Widget> _rules(BuildContext context) => [
    _Heading(context.t('absence.types.rules')),
    SettingRow(
      label: context.t('absence.types.approval'),
      description: context.t(
        _approvalPossible
            ? 'absence.types.approvalHint'
            : 'absence.types.approvalSick',
      ),
      trailing: HiveSwitch(
        value: _approvalPossible && _approval,
        // Null rather than a switch that springs back: it is not a setting for
        // this category, and a control that moves and undoes itself reads as a
        // bug rather than as a rule.
        onChanged: _approvalPossible
            ? (value) => setState(() => _approval = value)
            : null,
      ),
    ),
    if (_approvalPossible && _approval) ...[
      const SizedBox(height: 6),
      Builder(
        builder: (anchor) => FieldButton(
          icon: LucideIcons.userCheck,
          label: context.t('absence.types.approver'),
          value: context.t(_approver.labelKey),
          onTap: () => _pick<AbsenceApproverRule>(
            anchor: anchor,
            title: context.t('absence.types.approver'),
            options: [
              for (final rule in AbsenceApproverRule.values)
                (rule, context.t(rule.labelKey)),
            ],
            onPicked: (value) => setState(() => _approver = value),
          ),
        ),
      ),
      const SizedBox(height: 4),
    ],
    SettingRow(
      label: context.t('absence.types.halfDays'),
      trailing: HiveSwitch(
        value: _halfDays,
        onChanged: (value) => setState(() => _halfDays = value),
      ),
    ),
    SettingRow(
      label: context.t('absence.types.fraction'),
      trailing: HiveSwitch(
        value: _fraction,
        onChanged: (value) => setState(() => _fraction = value),
      ),
    ),
    _NumberRow(
      label: context.t('absence.types.minNotice'),
      description: context.t('absence.types.minNoticeHint'),
      value: _minNotice,
      suffix: context.t('absence.types.daysUnit'),
      max: _minNoticeMax,
      onChanged: (value) => setState(() => _minNotice = value),
    ),
    _NumberRow(
      label: context.t('absence.types.maxConsecutive'),
      description: context.t('absence.types.maxConsecutiveHint'),
      value: _maxConsecutive,
      suffix: context.t('absence.types.daysUnit'),
      max: 366,
      onChanged: (value) => setState(() => _maxConsecutive = value),
    ),
    const SizedBox(height: 6),
    Builder(
      builder: (anchor) => FieldButton(
        icon: LucideIcons.eye,
        label: context.t('absence.types.visibility'),
        value: context.t(_visibility.labelKey),
        onTap: () => _pick<AbsenceVisibility>(
          anchor: anchor,
          title: context.t('absence.types.visibility'),
          options: [
            for (final visibility in AbsenceVisibility.values)
              (visibility, context.t(visibility.labelKey)),
          ],
          onPicked: (value) => setState(() => _visibility = value),
        ),
      ),
    ),
    const SizedBox(height: 6),
    _Hint(context.t('absence.types.visibilityHint')),
  ];

  List<Widget> _quota(BuildContext context) => [
    _Heading(context.t('absence.types.quota')),
    SettingRow(
      label: context.t('absence.types.unlimited'),
      description: context.t('absence.types.unlimitedHint'),
      trailing: HiveSwitch(value: _unlimited, onChanged: _setUnlimited),
    ),
    SettingRow(
      label: context.t('absence.types.counts'),
      description: context.t('absence.types.countsHint'),
      trailing: HiveSwitch(
        value: _counts,
        onChanged: _unlimited ? null : _setCounts,
      ),
    ),
    if (!_unlimited) ...[
      _DaysRow(
        label: context.t('absence.types.allowance'),
        description: context.t('absence.types.allowanceHint'),
        milliDays: _allowance,
        onChanged: (value) => setState(() => _allowance = value),
      ),
      if (_counts) _legalFloor(context),
      const SizedBox(height: 6),
      Builder(
        builder: (anchor) => FieldButton(
          icon: LucideIcons.trendingUp,
          label: context.t('absence.types.accrual'),
          value: context.t(_accrual.labelKey),
          onTap: () => _pick<AbsenceAccrual>(
            anchor: anchor,
            title: context.t('absence.types.accrual'),
            options: [
              for (final accrual in AbsenceAccrual.values)
                (accrual, context.t(accrual.labelKey)),
            ],
            onPicked: (value) => setState(() => _accrual = value),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Builder(
        builder: (_) => FieldButton(
          icon: LucideIcons.calendarRange,
          label: context.t('absence.types.yearStart'),
          value: _monthDayLabel(context, _yearStart),
          onTap: () => _pickMonthDay(
            _yearStart,
            (value) => setState(() => _yearStart = value),
            context.t('absence.types.yearStart'),
          ),
        ),
      ),
      _NumberRow(
        label: context.t('absence.types.waitingPeriod'),
        description: context.t('absence.types.waitingPeriodHint'),
        value: _waiting,
        suffix: context.t('absence.types.months'),
        max: 12,
        onChanged: (value) => setState(() => _waiting = value),
      ),
      SettingRow(
        label: context.t('absence.types.prorateOnJoin'),
        trailing: HiveSwitch(
          value: _prorateJoin,
          onChanged: (value) => setState(() => _prorateJoin = value),
        ),
      ),
      SettingRow(
        label: context.t('absence.types.prorateOnLeave'),
        trailing: HiveSwitch(
          value: _prorateLeave,
          onChanged: (value) => setState(() => _prorateLeave = value),
        ),
      ),
      SettingRow(
        label: context.t('absence.types.negative'),
        description: context.t('absence.types.negativeHint'),
        trailing: HiveSwitch(
          value: _negative,
          onChanged: (value) => setState(() => _negative = value),
        ),
      ),
      if (_negative)
        _DaysRow(
          label: context.t('absence.types.negativeLimit'),
          milliDays: _negativeLimit,
          onChanged: (value) => setState(() => _negativeLimit = value),
        ),
      const SizedBox(height: 6),
      Builder(
        builder: (anchor) => FieldButton(
          icon: LucideIcons.arrowRightLeft,
          label: context.t('absence.types.carryover'),
          value: context.t(_carryover.labelKey),
          onTap: () => _pick<AbsenceCarryover>(
            anchor: anchor,
            title: context.t('absence.types.carryover'),
            options: [
              for (final carryover in AbsenceCarryover.values)
                (carryover, context.t(carryover.labelKey)),
            ],
            onPicked: (value) => setState(() => _carryover = value),
          ),
        ),
      ),
      if (_carryover == AbsenceCarryover.capped)
        _DaysRow(
          label: context.t('absence.types.carryoverCap'),
          milliDays: _carryoverCap,
          onChanged: (value) => setState(() => _carryoverCap = value),
        ),
      if (_carryover != AbsenceCarryover.none) ...[
        const SizedBox(height: 10),
        FieldButton(
          icon: LucideIcons.calendarX2,
          label: context.t('absence.types.carryoverExpires'),
          value: _monthDayLabel(context, _carryoverExpires),
          onTap: () => _pickMonthDay(
            _carryoverExpires,
            (value) => setState(() => _carryoverExpires = value),
            context.t('absence.types.carryoverExpires'),
          ),
        ),
        const SizedBox(height: 6),
        _Hint(context.t('absence.types.carryoverHint')),
      ],
    ],
  ];

  /// § 3 Abs. 1 BUrlG: four weeks of the person's own working week.
  ///
  /// Said to the operator where the number is set, and as a calculation rather
  /// than a verdict: hinata does not know each person's week here, and an
  /// instance of four-day weeks is legitimately under twenty. It warns when the
  /// quota is under the five-day floor, which is the common case, and never
  /// refuses — the server does not either.
  Widget _legalFloor(BuildContext context) {
    const fiveDayFloor = 20 * kMilliDay;
    final short = _allowance < fiveDayFloor;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text(
        context.t(
          'absence.types.legalFloor',
          variables: {
            'five': formatDays(fiveDayFloor),
            'six': formatDays(24 * kMilliDay),
          },
        ),
        style: TextStyle(
          fontSize: 11.5,
          height: 1.4,
          color: short ? AppColors.danger : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _iconRow(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.t('absence.types.icon'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.inkFaint,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in kAbsenceIcons.entries)
            Tooltip(
              message: context.t('absence.icon.${entry.key}'),
              child: InkWell(
                onTap: () => setState(() => _icon = entry.key),
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _icon == entry.key
                        ? absenceColor(context, _hue).withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(
                      color: _icon == entry.key
                          ? absenceColor(context, _hue)
                          : AppColors.hairline,
                    ),
                  ),
                  child: Icon(
                    entry.value,
                    size: 17,
                    color: _icon == entry.key
                        ? absenceColor(context, _hue)
                        : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _hueRow(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.t('absence.types.hue'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.inkFaint,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final hue in const [
            null,
            5,
            30,
            45,
            95,
            160,
            195,
            225,
            265,
            320,
          ])
            InkWell(
              onTap: () => setState(() => _hue = hue),
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: absenceColor(context, hue),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _hue == hue ? AppColors.ink : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: hue == null
                    ? Icon(
                        LucideIcons.minus,
                        size: 14,
                        color: AppColors.surface,
                      )
                    : null,
              ),
            ),
        ],
      ),
    ],
  );

  /// A day of the year without the year: an anchor repeats every January.
  String _monthDayLabel(BuildContext context, DateTime day) =>
      MaterialLocalizations.of(context).formatShortMonthDay(day);
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: AppColors.inkSoft,
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.4,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

/// A whole number on a settings row, with the unit beside it.
class _NumberRow extends StatefulWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.max,
    this.description,
    this.suffix,
  });

  final String label;
  final String? description;
  final int value;
  final int max;
  final String? suffix;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberRow> createState() => _NumberRowState();
}

class _NumberRowState extends State<_NumberRow> {
  late final _controller = TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingRow(
    label: widget.label,
    description: widget.description,
    trailing: SizedBox(
      width: 108,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.end,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          suffixText: widget.suffix,
          suffixStyle: TextStyle(fontSize: 11, color: AppColors.inkFaint),
        ),
        onChanged: (text) {
          final parsed = int.tryParse(text) ?? 0;
          widget.onChanged(parsed.clamp(0, widget.max));
        },
      ),
    ),
  );
}

/// A number of days on a settings row, held in thousandths.
///
/// Typed as days and stored as thousandths, so "2,5" arrives as 2500 rather
/// than as a decimal somebody has to round later. Both separators are accepted:
/// a German keyboard puts a comma on the number row.
class _DaysRow extends StatefulWidget {
  const _DaysRow({
    required this.label,
    required this.milliDays,
    required this.onChanged,
    this.description,
  });

  final String label;
  final String? description;
  final int milliDays;
  final ValueChanged<int> onChanged;

  @override
  State<_DaysRow> createState() => _DaysRowState();
}

class _DaysRowState extends State<_DaysRow> {
  late final _controller = TextEditingController(
    text: formatDays(widget.milliDays),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingRow(
    label: widget.label,
    description: widget.description,
    trailing: SizedBox(
      width: 108,
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.end,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          isDense: true,
          suffixText: context.t('absence.types.daysUnit'),
          suffixStyle: TextStyle(fontSize: 11, color: AppColors.inkFaint),
        ),
        onChanged: (text) => widget.onChanged(parseDays(text)),
      ),
    ),
  );
}
