/// The three things a keeper does to somebody's year — grant it, correct it,
/// set the dates it is computed from — and the journal that shows what happened.
///
/// All four open over the entitlements list rather than on pages of their own:
/// each is one decision about one row, and a page would lose the list behind it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/field_button.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/read_on_trigger.dart';
import '../sprint/modals/glass_modal.dart';
import 'absence_labels.dart';

/// Grants [year] of [typeId] to [userIds], after showing what that would do.
///
/// The preview is not optional. A keeper about to give forty people a year
/// should see the part-year cases before writing them, not discover them in a
/// list of forty results — and § 5 BUrlG makes part-years the normal case, not
/// the exception.
Future<bool?> showAbsenceGrantSheet(
  BuildContext context, {
  required String typeId,
  required String typeName,
  required int year,
  required List<String> userIds,
  required Map<String, String> names,
}) {
  final repository = context.read<AbsenceRepository>();
  return showGlassModal<bool>(
    context,
    width: 520,
    builder: (sheetContext) => RepositoryProvider.value(
      value: repository,
      child: _GrantForm(
        typeId: typeId,
        typeName: typeName,
        year: year,
        userIds: userIds,
        names: names,
      ),
    ),
  );
}

class _GrantForm extends StatefulWidget {
  const _GrantForm({
    required this.typeId,
    required this.typeName,
    required this.year,
    required this.userIds,
    required this.names,
  });

  final String typeId;
  final String typeName;
  final int year;
  final List<String> userIds;
  final Map<String, String> names;

  @override
  State<_GrantForm> createState() => _GrantFormState();
}

class _GrantFormState extends State<_GrantForm> {
  List<AbsenceGrantPreview>? _preview;
  bool _loading = true;
  bool _saving = false;
  String? _errorKey;
  int _override = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final preview = await context.read<AbsenceRepository>().previewGrant(
        typeId: widget.typeId,
        year: widget.year,
        userIds: widget.userIds,
        allowanceMilliDays: _override > 0 ? _override : null,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  Future<void> _grant() async {
    setState(() => _saving = true);
    try {
      final written = await context.read<AbsenceRepository>().grantMany(
        typeId: widget.typeId,
        year: widget.year,
        userIds: widget.userIds,
        allowanceMilliDays: _override > 0 ? _override : null,
      );
      if (!mounted) return;
      showGlassToast(
        context,
        written.isEmpty
            ? context.t('absence.entitlements.grantedNone')
            : context.t(
                'absence.entitlements.granted',
                count: written.length,
                variables: {'count': '${written.length}'},
              ),
      );
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
        icon: LucideIcons.calendarPlus,
        title: context.t(
          'absence.entitlements.grantTitle',
          variables: {'year': '${widget.year}'},
        ),
        subtitle: widget.typeName,
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('absence.entitlements.grantHint'),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _AmountField(
                label: context.t('absence.entitlements.allowanceOverride'),
                helper: context.t('absence.entitlements.allowanceOverrideHint'),
                milliDays: _override,
                // Re-asked rather than recomputed here: what a part year is
                // worth is the server's arithmetic, and a second copy of it in
                // the client is a second answer waiting to disagree.
                onSubmitted: (value) {
                  setState(() => _override = value);
                  unawaited(_load());
                },
              ),
              const SizedBox(height: 14),
              Text(
                context.t('absence.entitlements.preview'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 6),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: HiveLoader(size: 26)),
                )
              else if (_errorKey != null)
                Text(
                  context.t(_errorKey!),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.danger,
                  ),
                )
              else
                // As long as the keeper's selection, which the server caps at
                // five hundred. Built as they scroll rather than all at once,
                // and rebuilt on every allowance they try.
                ListView.builder(
                  shrinkWrap: true,
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _preview?.length ?? 0,
                  itemBuilder: (context, index) => _PreviewRow(
                    row: _preview![index],
                    name: widget.names[_preview![index].userId],
                  ),
                ),
            ],
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('absence.entitlements.grant'),
        busy: _saving,
        onConfirm: _saving || _loading || _errorKey != null ? null : _grant,
      ),
    ],
  );
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row, this.name});

  final AbsenceGrantPreview row;
  final String? name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name ?? row.userId,
                style: TextStyle(fontSize: 13, color: AppColors.ink),
              ),
              if (row.reason != null && row.reason != 'FULL')
                Text(
                  context.t('absence.entitlements.reason.${row.reason}'),
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          row.alreadyGranted
              ? context.t('absence.entitlements.alreadyGranted')
              : daysLabel(context, row.accruedMilliDays),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            // Somebody who already has the year is not an error and not a
            // result: the row is greyed so the eye skips it.
            color: row.alreadyGranted ? AppColors.inkFaint : AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

// --- a correction ---------------------------------------------------------------

/// Books a correction on one person's balance. Resolves to true once booked.
Future<bool?> showAbsenceAdjustSheet(
  BuildContext context, {
  required String userId,
  required String name,
  required String typeId,
  required int year,
}) {
  final repository = context.read<AbsenceRepository>();
  return showGlassModal<bool>(
    context,
    width: 460,
    builder: (sheetContext) => RepositoryProvider.value(
      value: repository,
      child: _AdjustForm(
        userId: userId,
        name: name,
        typeId: typeId,
        year: year,
      ),
    ),
  );
}

class _AdjustForm extends StatefulWidget {
  const _AdjustForm({
    required this.userId,
    required this.name,
    required this.typeId,
    required this.year,
  });

  final String userId;
  final String name;
  final String typeId;
  final int year;

  @override
  State<_AdjustForm> createState() => _AdjustFormState();
}

class _AdjustFormState extends State<_AdjustForm> {
  /// Mirrors `TimeOffLedgerEntry.REASON_MAX`. Five hundred, not three: a field
  /// that stops short of what the server accepts cuts a keeper's sentence off
  /// for no reason anybody can see.
  static const int _reasonMax = 500;

  final _reason = TextEditingController();
  final _amount = TextEditingController();
  DateTime? _effectiveOn;
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showGlassDatePicker(
      context,
      initialDate: _effectiveOn ?? DateTime(widget.year, 1, 1),
      firstDate: DateTime(widget.year - 1),
      lastDate: DateTime(widget.year + 1, 12, 31),
      title: context.t('absence.entitlements.adjustEffective'),
    );
    if (picked != null && mounted) {
      setState(() => _effectiveOn = DateUtils.dateOnly(picked));
    }
  }

  Future<void> _save() async {
    final milliDays = parseSignedDays(_amount.text);
    if (milliDays == 0) {
      showGlassErrorToast(context, context.t('error.timeOff.adjustmentZero'));
      return;
    }
    if (_reason.text.trim().isEmpty) {
      // The same refusal the server makes, made where the field is: a balance
      // that moved for no stated cause is the one somebody will be asked about
      // in a year and will not be able to answer.
      showGlassErrorToast(context, context.t('error.timeOff.reasonRequired'));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AbsenceRepository>().adjust(
        userId: widget.userId,
        typeId: widget.typeId,
        year: widget.year,
        milliDays: milliDays,
        reason: _reason.text.trim(),
        effectiveOn: _effectiveOn,
      );
      if (!mounted) return;
      showGlassToast(context, context.t('absence.entitlements.adjustSaved'));
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
        icon: LucideIcons.squarePen,
        title: context.t(
          'absence.entitlements.adjustTitle',
          variables: {'name': widget.name},
        ),
        subtitle: context.t('absence.entitlements.adjustHint'),
        subtitleMaxLines: 3,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
              ],
              decoration: InputDecoration(
                labelText: context.t('absence.entitlements.adjustAmount'),
                helperText: context.t('absence.entitlements.adjustAmountHint'),
                helperMaxLines: 2,
                suffixText: context.t('absence.types.daysUnit'),
              ),
            ),
            const SizedBox(height: 10),
            FieldButton(
              icon: LucideIcons.calendarDays,
              label: context.t('absence.entitlements.adjustEffective'),
              value: _effectiveOn == null
                  ? context.t('absence.entitlements.notSet')
                  : MaterialLocalizations.of(
                      context,
                    ).formatFullDate(_effectiveOn!),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLength: _reasonMax,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.t('absence.entitlements.adjustReason'),
                helperText: context.t('absence.entitlements.adjustReasonHint'),
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('absence.entitlements.adjust'),
        busy: _saving,
        onConfirm: _saving ? null : _save,
      ),
    ],
  );
}

// --- joining and leaving -----------------------------------------------------------

/// The two dates the entitlement arithmetic reads. Resolves to true once saved.
Future<bool?> showAbsenceEmploymentSheet(
  BuildContext context, {
  required String userId,
  required String name,
}) {
  final repository = context.read<AbsenceRepository>();
  return showGlassModal<bool>(
    context,
    width: 460,
    builder: (sheetContext) => RepositoryProvider.value(
      value: repository,
      child: _EmploymentForm(userId: userId, name: name),
    ),
  );
}

class _EmploymentForm extends StatefulWidget {
  const _EmploymentForm({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  State<_EmploymentForm> createState() => _EmploymentFormState();
}

class _EmploymentFormState extends State<_EmploymentForm> {
  /// Mirrors `TimeOffEmployment.NOTE_MAX`.
  static const int _noteMax = 300;

  final _note = TextEditingController();
  DateTime? _hiredOn;
  DateTime? _leftOn;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dates = await context.read<AbsenceRepository>().employment(
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _hiredOn = dates.hiredOn;
        _leftOn = dates.leftOn;
        _note.text = dates.note ?? '';
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  Future<void> _pick(
    DateTime? current,
    ValueChanged<DateTime?> onPicked,
    String title,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showGlassDatePicker(
      context,
      initialDate: current ?? today,
      firstDate: DateTime(today.year - 60),
      lastDate: DateTime(today.year + 5, 12, 31),
      title: title,
    );
    if (picked != null && mounted) onPicked(DateUtils.dateOnly(picked));
  }

  Future<void> _save() async {
    if (_hiredOn != null && _leftOn != null && _leftOn!.isBefore(_hiredOn!)) {
      showGlassErrorToast(context, context.t('error.timeOff.employmentOrder'));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AbsenceRepository>().saveEmployment(
        userId: widget.userId,
        hiredOn: _hiredOn,
        leftOn: _leftOn,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      showGlassToast(
        context,
        context.t('absence.entitlements.employmentSaved'),
      );
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
        icon: LucideIcons.calendarClock,
        title: context.t(
          'absence.entitlements.employmentTitle',
          variables: {'name': widget.name},
        ),
        subtitle: context.t('absence.entitlements.employmentHint'),
        subtitleMaxLines: 3,
      ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: HiveLoader(size: 28)),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DateRow(
                icon: LucideIcons.logIn,
                label: context.t('absence.entitlements.hiredOn'),
                value: _hiredOn,
                onPick: () => _pick(
                  _hiredOn,
                  (value) => setState(() => _hiredOn = value),
                  context.t('absence.entitlements.hiredOn'),
                ),
                onClear: () => setState(() => _hiredOn = null),
              ),
              const SizedBox(height: 10),
              _DateRow(
                icon: LucideIcons.logOut,
                label: context.t('absence.entitlements.leftOn'),
                value: _leftOn,
                onPick: () => _pick(
                  _leftOn,
                  (value) => setState(() => _leftOn = value),
                  context.t('absence.entitlements.leftOn'),
                ),
                onClear: () => setState(() => _leftOn = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: _noteMax,
                decoration: InputDecoration(
                  labelText: context.t('absence.entitlements.employmentNote'),
                ),
              ),
            ],
          ),
        ),
      GlassModalFooter(
        confirmLabel: context.t('common.save'),
        busy: _saving,
        onConfirm: _saving || _loading ? null : _save,
      ),
    ],
  );
}

/// A date that can be set and, just as importantly, unset: a leaving date
/// entered by mistake would otherwise halve somebody's year for good.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FieldButton(
          icon: icon,
          label: label,
          value: value == null
              ? context.t('absence.entitlements.notSet')
              : MaterialLocalizations.of(context).formatFullDate(value!),
          onTap: onPick,
        ),
      ),
      if (value != null)
        IconButton(
          tooltip: context.t('absence.entitlements.clear'),
          onPressed: onClear,
          icon: Icon(LucideIcons.x, size: 16, color: AppColors.inkSoft),
        ),
    ],
  );
}

// --- the journal -------------------------------------------------------------------

/// One person's movements for one type and year, oldest first.
Future<void> showAbsenceLedgerSheet(
  BuildContext context, {
  required String userId,
  required String name,
  required String typeId,
  required int year,
}) {
  final repository = context.read<AbsenceRepository>();
  return showGlassModal<void>(
    context,
    width: 520,
    builder: (sheetContext) => RepositoryProvider.value(
      value: repository,
      child: _LedgerSheet(
        userId: userId,
        name: name,
        typeId: typeId,
        year: year,
      ),
    ),
  );
}

class _LedgerSheet extends StatefulWidget {
  const _LedgerSheet({
    required this.userId,
    required this.name,
    required this.typeId,
    required this.year,
  });

  final String userId;
  final String name;
  final String typeId;
  final int year;

  @override
  State<_LedgerSheet> createState() => _LedgerSheetState();
}

class _LedgerSheetState extends State<_LedgerSheet> {
  late final PagedCubit<AbsenceLedgerEntry> _entries =
      PagedCubit<AbsenceLedgerEntry>(
        (page, size) => context.read<AbsenceRepository>().ledger(
          userId: widget.userId,
          typeId: widget.typeId,
          year: widget.year,
          page: page,
          size: size,
        ),
        pageSize: 50,
        keyOf: (entry) => entry.id,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_entries.load());
  }

  @override
  void dispose() {
    unawaited(_entries.close());
    super.dispose();
  }

  /// **Only a list gets a [Flexible].**
  ///
  /// A sheet is `Column(min)` inside a box that caps it at most of the screen.
  /// A `Flexible` child is handed that whole height as its maximum, and an
  /// empty state is a `Center` — which has no height factor, so it takes every
  /// point it is offered. The result is a dialog the size of the display with
  /// two lines of text floating in the middle of it.
  ///
  /// So the branch decides the shape: the spinner and the empty state are
  /// ordinary children, which a Column gives unbounded height and which
  /// therefore size to themselves. Only the list — the one thing that really
  /// can be longer than the screen — is flexible and scrolls.
  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _entries,
    child:
        BlocBuilder<
          PagedCubit<AbsenceLedgerEntry>,
          PagedState<AbsenceLedgerEntry>
        >(
          builder: (context, state) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassModalHeader(
                icon: LucideIcons.scrollText,
                title: context.t(
                  'absence.entitlements.ledgerTitle',
                  variables: {'name': widget.name},
                ),
                subtitle: '${widget.year}',
              ),
              if (state.isLoading && !state.hasData)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: HiveLoader(size: 28),
                )
              else if (state.items.isEmpty)
                HiveEmptyState(
                  title: context.t('absence.entitlements.ledgerEmpty'),
                  message: context.t('absence.entitlements.ledgerEmptyMessage'),
                  card: false,
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
                )
              else
                // Built as they scroll into view: "read on" appends fifty rows
                // at a time, and a concrete child list would lay out every one
                // of them on every frame of the sheet.
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.items.length) {
                        return ReadOnTrigger(
                          count: state.items.length,
                          loading: state.isLoadingMore,
                          onReadOn: () => unawaited(_entries.loadMore()),
                        );
                      }
                      return LedgerRow(entry: state.items[index]);
                    },
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
  );
}

/// One movement: when, why, and how much — with the sign, because the direction
/// is the point of the column.
///
/// Shared with the person's own journal in settings, so a keeper and the person
/// they keep read the same line about the same row.
class LedgerRow extends StatelessWidget {
  const LedgerRow({super.key, required this.entry});

  final AbsenceLedgerEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(entry.kind.labelKey),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.effectiveOn == null
                    ? ''
                    : MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(entry.effectiveOn!.toLocal()),
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
              if (entry.reason != null && entry.reason!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  entry.reason!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          signedDaysLabel(context, entry.milliDays),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: entry.milliDays < 0 ? AppColors.inkSoft : AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

/// A number of days typed into a modal, held in thousandths.
class _AmountField extends StatefulWidget {
  const _AmountField({
    required this.label,
    required this.helper,
    required this.milliDays,
    required this.onSubmitted,
  });

  final String label;
  final String helper;
  final int milliDays;

  /// Called when the field loses focus or is submitted — not on every
  /// keystroke: each change here costs a preview request.
  final ValueChanged<int> onSubmitted;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final _controller = TextEditingController(
    text: formatDays(widget.milliDays),
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSubmitted(parseDays(_controller.text));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      helperMaxLines: 2,
      suffixText: context.t('absence.types.daysUnit'),
    ),
    onSubmitted: (text) => widget.onSubmitted(parseDays(text)),
  );
}
