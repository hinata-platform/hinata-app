/// Asking for time off, and reporting sickness — which is not asking.
///
/// Two sheets in one file because they share a type picker and a date range and
/// nothing else. Keeping them apart on screen is the point: a form with an
/// approver, a notice period and a balance behind it would say, every time
/// somebody fell ill, that being ill is something one applies for. § 5 EFZG
/// knows a notification and not a permission (R11).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_request_models.dart';
import '../../core/models/core_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/field_button.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar, HiveSwitch;
import '../../core/widgets/person_picker.dart';
import '../account/account_widgets.dart' show SettingRow;
import '../sprint/modals/glass_modal.dart';
import 'absence_labels.dart';

/// Opens the request form. Resolves to the filed request, or null if dismissed.
///
/// [types] and [balances] come from the screen that opened it, so the sheet
/// makes no read of its own before it can draw: the reader's own balance is
/// already on the screen behind it. [initialFrom] and [initialTo] are the days
/// somebody marked in the calendar before asking.
Future<AbsenceRequest?> showAbsenceRequestSheet(
  BuildContext context, {
  required List<AbsenceType> types,
  AbsenceBalances? balances,
  DateTime? initialFrom,
  DateTime? initialTo,
}) {
  final askable = [
    for (final type in types)
      if (type.active && type.kind != AbsenceKind.sick) type,
  ];
  final repository = context.read<AbsenceRepository>();
  final users = context.read<UserRepository>();
  return showGlassModal<AbsenceRequest>(
    context,
    width: 520,
    builder: (sheetContext) => MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AbsenceRepository>.value(value: repository),
        RepositoryProvider<UserRepository>.value(value: users),
      ],
      child: _RequestForm(
        types: askable,
        balances: balances,
        initialFrom: initialFrom,
        initialTo: initialTo,
      ),
    ),
  );
}

/// Opens the sick report. Resolves to what it produced, or null if dismissed.
///
/// [initialFrom] and [initialTo] are the days marked in the calendar, if the
/// report started there; otherwise it is today.
Future<SickReport?> showSickReportSheet(
  BuildContext context, {
  required List<AbsenceType> types,
  DateTime? initialFrom,
  DateTime? initialTo,
}) {
  final sickTypes = [
    for (final type in types)
      if (type.active && type.kind == AbsenceKind.sick) type,
  ];
  final repository = context.read<AbsenceRepository>();
  return showGlassModal<SickReport>(
    context,
    width: 460,
    builder: (sheetContext) => RepositoryProvider<AbsenceRepository>.value(
      value: repository,
      child: _SickForm(
        types: sickTypes,
        initialFrom: initialFrom,
        initialTo: initialTo,
      ),
    ),
  );
}

// --- the request ---------------------------------------------------------------

class _RequestForm extends StatefulWidget {
  const _RequestForm({
    required this.types,
    required this.balances,
    required this.initialFrom,
    required this.initialTo,
  });

  final List<AbsenceType> types;
  final AbsenceBalances? balances;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _note = TextEditingController();

  AbsenceType? _type;
  late DateTime _from;
  late DateTime _to;
  bool _halfFirst = false;
  bool _halfLast = false;
  DirectoryUser? _substitute;

  AbsencePreview? _preview;
  bool _previewing = false;
  bool _saving = false;
  String? _errorKey;

  /// Holds a run of half-day flips together, so switching both ends on and
  /// off again is one preview read rather than four. A new type or a new span
  /// is read at once — each is a single, deliberate pick.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final start = DateUtils.dateOnly(widget.initialFrom ?? DateTime.now());
    final end = DateUtils.dateOnly(widget.initialTo ?? start);
    _from = start;
    _to = end.isBefore(start) ? start : end;
    _type = _likelyType(widget.types);
    if (_type != null) unawaited(_loadPreview());
  }

  /// What somebody pressing "request time off" almost always means: leave.
  ///
  /// The catalogue arrives sorted by name, so its first entry is whatever
  /// happens to sort first — in German that was "Sonstiges". The system
  /// vacation type if the catalogue has it, else the first type that has to
  /// be asked for, else anything.
  static AbsenceType? _likelyType(List<AbsenceType> types) =>
      types.where((type) => type.systemKey == 'vacation').firstOrNull ??
      types.where((type) => type.requiresApproval).firstOrNull ??
      types.firstOrNull;

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    super.dispose();
  }

  AbsenceBalance? get _balance {
    final type = _type;
    if (type == null) return null;
    return widget.balances?.balances
        .where((balance) => balance.typeId == type.id)
        .firstOrNull;
  }

  /// What would be left afterwards, for the person's own form only.
  ///
  /// Their own figure, so it may be shown; a decider's inbox says whether the
  /// days are there and never how many (R2, R10).
  int? get _remainingAfter {
    final balance = _balance;
    final preview = _preview;
    if (balance == null || preview == null || balance.unlimited) return null;
    return balance.remainingMilliDays - preview.milliDays;
  }

  AbsenceRequestDraft get _draft => AbsenceRequestDraft(
    typeId: _type?.id ?? '',
    from: _from,
    to: _to,
    firstDayMilliDays: _halfFirst ? kMilliDay ~/ 2 : null,
    // A one-day span reads the first portion alone, so sending a last one for
    // it would be noise the server has to ignore.
    lastDayMilliDays: _to == _from || !_halfLast ? null : kMilliDay ~/ 2,
    note: _note.text,
    substituteId: _substitute?.id,
  );

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_loadPreview());
    });
  }

  Future<void> _loadPreview() async {
    if (_type == null) return;
    setState(() {
      _previewing = true;
      _errorKey = null;
    });
    try {
      final preview = await context.read<AbsenceRepository>().preview(_draft);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewing = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _preview = null;
        _errorKey = failure.message;
      });
    }
  }

  Future<void> _pickType(Rect? anchor) async {
    final picked = await showGlassOptions<AbsenceType>(
      context,
      title: context.t('absence.request.type'),
      anchorRect: anchor,
      options: [
        for (final type in widget.types)
          (value: type, child: _TypeOption(type: type, balances: widget.balances)),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _type = picked;
      // Portions a type does not allow cannot survive a switch to it, or the
      // form would send a half day the server is bound to refuse.
      if (!picked.halfDaysAllowed) {
        _halfFirst = false;
        _halfLast = false;
      }
    });
    unawaited(_loadPreview());
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showGlassDateRangePicker(
      context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialRange: DateTimeRange(start: _from, end: _to),
      title: context.t('absence.request.dates'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateUtils.dateOnly(picked.start);
      _to = DateUtils.dateOnly(picked.end);
      if (_from == _to) _halfLast = false;
    });
    unawaited(_loadPreview());
  }

  Future<void> _pickSubstitute(Rect? anchor) async {
    final picked = await showPersonPicker(
      context,
      anchorRect: anchor ?? Rect.zero,
    );
    if (picked == null || !mounted) return;
    setState(() => _substitute = picked);
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final filed = await context.read<AbsenceRepository>().submit(_draft);
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(
          filed.status == AbsenceRequestStatus.approved
              ? 'absence.request.autoApproved'
              : 'absence.request.filed',
        ),
      );
      Navigator.of(context).pop(filed);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = _type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.calendarPlus,
          title: context.t('absence.request.title'),
          subtitle: context.t('absence.request.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Builder(
                  builder: (anchor) => FieldButton(
                    icon: absenceIcon(type?.icon),
                    label: context.t('absence.request.type'),
                    value: type == null
                        ? context.t('absence.request.noTypes')
                        : absenceTypeName(context, type),
                    onTap: () => unawaited(_pickType(anchorRectOfContext(anchor))),
                  ),
                ),
                const SizedBox(height: 10),
                FieldButton(
                  icon: LucideIcons.calendarRange,
                  label: context.t('absence.request.dates'),
                  value: _spanLabel(context, _from, _to),
                  onTap: () => unawaited(_pickDates()),
                ),
                if (type?.halfDaysAllowed ?? false) ...[
                  const SizedBox(height: 4),
                  _HalfDayRow(
                    labelKey: _from == _to
                        ? 'absence.request.halfDayOnly'
                        : 'absence.request.halfFirst',
                    value: _halfFirst,
                    onChanged: (value) {
                      setState(() => _halfFirst = value);
                      _schedulePreview();
                    },
                  ),
                  if (_from != _to)
                    _HalfDayRow(
                      labelKey: 'absence.request.halfLast',
                      value: _halfLast,
                      onChanged: (value) {
                        setState(() => _halfLast = value);
                        _schedulePreview();
                      },
                    ),
                ],
                const SizedBox(height: 12),
                _preview == null && _errorKey == null
                    ? const SizedBox.shrink()
                    : _PreviewLine(
                        preview: _preview,
                        errorKey: _errorKey,
                        busy: _previewing,
                        remainingAfter: _remainingAfter,
                      ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: context.t('absence.request.note'),
                    helperText: context.t('absence.request.noteHint'),
                  ),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (anchor) => _SubstituteField(
                    person: _substitute,
                    onTap: () =>
                        unawaited(_pickSubstitute(anchorRectOfContext(anchor))),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t('absence.request.substituteHint'),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('absence.request.submit'),
          busy: _saving,
          onConfirm: _saving || type == null || (_preview?.milliDays ?? 0) <= 0
              ? null
              : _submit,
        ),
      ],
    );
  }
}

/// One row of the type picker: the type, and what is left of it.
class _TypeOption extends StatelessWidget {
  const _TypeOption({required this.type, required this.balances});

  final AbsenceType type;
  final AbsenceBalances? balances;

  @override
  Widget build(BuildContext context) {
    final balance = balances?.balances
        .where((row) => row.typeId == type.id)
        .firstOrNull;
    return Row(
      children: [
        Icon(
          absenceIcon(type.icon),
          size: 16,
          color: absenceColor(context, type.hue),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(absenceTypeName(context, type))),
        if (balance != null && !balance.unlimited)
          Text(
            daysLabel(context, balance.remainingMilliDays),
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class _HalfDayRow extends StatelessWidget {
  const _HalfDayRow({
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String labelKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    label: context.t(labelKey),
    trailing: HiveSwitch(value: value, onChanged: onChanged),
  );
}

/// The stand-in, as a field like the ones above it: caption, then the choice.
class _SubstituteField extends StatelessWidget {
  const _SubstituteField({required this.person, required this.onTap});

  final DirectoryUser? person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = person;
    final name = picked == null
        ? null
        : (picked.displayName.isEmpty ? picked.username : picked.displayName);
    return FieldButton(
      icon: LucideIcons.userRound,
      leading: picked == null
          ? null
          : HiveAvatar(
              name: name!,
              imageUrl: picked.avatarUrl,
              pronouns: picked.pronouns,
              size: 22,
            ),
      label: context.t('absence.request.substitute'),
      value: name ?? context.t('absence.request.substitutePlaceholder'),
      empty: picked == null,
      onTap: onTap,
    );
  }
}

/// "7 working days, 1 public holiday — 12.5 days left afterwards."
///
/// The figure with its reason beside it. A total on its own invites the
/// suspicion that a weekend was counted; the same total next to "2 days off"
/// does not.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.preview,
    required this.errorKey,
    required this.busy,
    required this.remainingAfter,
  });

  final AbsencePreview? preview;
  final String? errorKey;
  final bool busy;
  final int? remainingAfter;

  @override
  Widget build(BuildContext context) {
    final key = errorKey;
    if (key != null) {
      return _box(
        context,
        AppColors.danger,
        LucideIcons.circleAlert,
        context.t(key),
        null,
      );
    }
    final result = preview;
    if (result == null) return const SizedBox.shrink();
    final parts = <String>[
      daysLabel(context, result.milliDays),
      if (result.holidays > 0)
        context.t(
          'absence.request.holidaysIn',
          count: result.holidays,
          variables: {'count': '${result.holidays}'},
        ),
      if (result.daysOff > 0)
        context.t(
          'absence.request.daysOffIn',
          count: result.daysOff,
          variables: {'count': '${result.daysOff}'},
        ),
    ];
    final left = remainingAfter;
    final warnings = <String>[
      if (result.balanceShort) context.t('absence.request.balanceShort'),
      if (result.shortNotice) context.t('absence.request.shortNotice'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _box(
          context,
          AppColors.accentStrong,
          LucideIcons.calendarCheck,
          parts.join(' · '),
          left == null
              ? null
              : context.t(
                  'absence.request.remainingAfter',
                  variables: {'days': days(context, left)},
                ),
          busy: busy,
        ),
        for (final warning in warnings) ...[
          const SizedBox(height: 6),
          _box(
            context,
            AppColors.warning,
            LucideIcons.triangleAlert,
            warning,
            null,
          ),
        ],
      ],
    );
  }

  Widget _box(
    BuildContext context,
    Color tint,
    IconData icon,
    String title,
    String? subtitle, {
    bool busy = false,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: tint.withValues(alpha: 0.24)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        busy
            ? const SizedBox(width: 16, height: 16, child: HiveLoader(size: 16))
            : Icon(icon, size: 16, color: tint),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

// --- the sick report -------------------------------------------------------------

class _SickForm extends StatefulWidget {
  const _SickForm({
    required this.types,
    required this.initialFrom,
    required this.initialTo,
  });

  final List<AbsenceType> types;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<_SickForm> createState() => _SickFormState();
}

class _SickFormState extends State<_SickForm> {
  late DateTime _from;
  late DateTime _to;
  bool _halfDay = false;
  bool _saving = false;
  AbsenceType? _type;

  @override
  void initState() {
    super.initState();
    final start = DateUtils.dateOnly(widget.initialFrom ?? DateTime.now());
    final end = DateUtils.dateOnly(widget.initialTo ?? start);
    _from = start;
    _to = end.isBefore(start) ? start : end;
    _type = widget.types.firstOrNull;
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showGlassDateRangePicker(
      context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialRange: DateTimeRange(start: _from, end: _to),
      title: context.t('absence.sick.dates'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateUtils.dateOnly(picked.start);
      _to = DateUtils.dateOnly(picked.end);
      if (_from != _to) _halfDay = false;
    });
  }

  Future<void> _report() async {
    setState(() => _saving = true);
    try {
      final reported = await context.read<AbsenceRepository>().reportSick(
        from: _from,
        to: _to,
        halfDay: _halfDay,
        typeId: _type?.id,
      );
      if (!mounted) return;
      showGlassToast(
        context,
        reported.returnedMilliDays > 0
            // § 9 BUrlG: leave the sickness fell on comes back by itself, and
            // saying so is the only way anybody learns their balance moved.
            ? context.t(
                'absence.sick.reportedAndReturned',
                variables: {
                  'days': days(context, reported.returnedMilliDays),
                },
              )
            : context.t('absence.sick.reported'),
      );
      Navigator.of(context).pop(reported);
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
        icon: LucideIcons.thermometer,
        title: context.t('absence.sick.title'),
        subtitle: context.t('absence.sick.subtitle'),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldButton(
                icon: LucideIcons.calendarRange,
                label: context.t('absence.sick.dates'),
                value: _spanLabel(context, _from, _to),
                onTap: () => unawaited(_pickDates()),
              ),
              if (_from == _to) ...[
                const SizedBox(height: 4),
                _HalfDayRow(
                  labelKey: 'absence.sick.halfDay',
                  value: _halfDay,
                  onChanged: (value) => setState(() => _halfDay = value),
                ),
              ],
              // Only where an operator offers more than one. With one there is
              // nothing to choose, and a picker with a single row is a step
              // somebody has to take for no reason.
              if (widget.types.length > 1) ...[
                const SizedBox(height: 10),
                Builder(
                  builder: (anchor) => FieldButton(
                    icon: absenceIcon(_type?.icon),
                    label: context.t('absence.sick.type'),
                    value: _type == null
                        ? '—'
                        : absenceTypeName(context, _type!),
                    onTap: () async {
                      final picked = await showGlassOptions<AbsenceType>(
                        context,
                        title: context.t('absence.sick.type'),
                        anchorRect: anchorRectOfContext(anchor),
                        options: [
                          for (final type in widget.types)
                            (
                              value: type,
                              child: Text(absenceTypeName(context, type)),
                            ),
                        ],
                      );
                      if (picked != null && mounted) {
                        setState(() => _type = picked);
                      }
                    },
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                context.t('absence.sick.explainer'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('absence.sick.report'),
        busy: _saving,
        onConfirm: _saving ? null : _report,
      ),
    ],
  );
}

/// "15 – 19 Jun 2026", or one date where both ends are the same day.
String _spanLabel(BuildContext context, DateTime from, DateTime to) {
  final format = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag());
  if (from == to) return format.format(from);
  return '${format.format(from)} – ${format.format(to)}';
}
