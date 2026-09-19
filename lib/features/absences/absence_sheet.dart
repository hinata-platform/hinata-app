/// One absence, opened from wherever it showed up: what it is, where it stands,
/// and what can still be done about it.
///
/// An absence is one of two things, and the sheet is honest about which. One
/// entered directly — a type nobody approves, or any absence on an instance
/// without absence management — is the person's to edit and delete. One that a
/// request produced changes only through that request: its days are booked
/// against a balance, and the server refuses a direct edit that would leave the
/// booking behind. For that one the sheet shows the request, with its story and
/// the steps it still allows.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_request_models.dart';
import '../../core/models/availability_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../account/time_off_sheet.dart';
import '../sprint/modals/glass_modal.dart';
import '../time/day_marks.dart' show timeOffIcon;
import 'absence_labels.dart';
import 'absence_request_sheet.dart';
import 'absence_request_widgets.dart';

/// Opens [absence] or [request]. Resolves to true when something about it
/// changed, so the screen behind can redraw.
Future<bool> showAbsenceSheet(
  BuildContext context, {
  TimeOff? absence,
  AbsenceRequest? request,
  required List<AbsenceType> types,
  AbsenceBalances? balances,
  bool keeper = false,
}) async {
  assert(absence != null || request != null, 'Nothing to open.');
  final absences = context.read<AbsenceRepository>();
  final availability = context.read<AvailabilityRepository>();
  final users = context.read<UserRepository>();
  // Read here, where the page's providers are: the sheet sits on the root
  // navigator and asks nothing of the tree above it.
  final meId = context.read<AuthBloc>().state.user?.id;
  final changed = await showGlassModal<bool>(
    context,
    width: 480,
    builder: (sheetContext) => MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AbsenceRepository>.value(value: absences),
        RepositoryProvider<AvailabilityRepository>.value(value: availability),
        RepositoryProvider<UserRepository>.value(value: users),
      ],
      child: _AbsenceSheet(
        absence: absence,
        request: request,
        types: types,
        balances: balances,
        keeper: keeper,
        meId: meId,
      ),
    ),
  );
  return changed ?? false;
}

class _AbsenceSheet extends StatefulWidget {
  const _AbsenceSheet({
    required this.absence,
    required this.request,
    required this.types,
    required this.balances,
    required this.keeper,
    required this.meId,
  });

  final TimeOff? absence;
  final AbsenceRequest? request;
  final List<AbsenceType> types;
  final AbsenceBalances? balances;
  final bool keeper;

  /// Who is reading: their own request offers edit and withdraw, somebody
  /// else's offers the decision.
  final String? meId;

  @override
  State<_AbsenceSheet> createState() => _AbsenceSheetState();
}

class _AbsenceSheetState extends State<_AbsenceSheet> {
  late AbsenceRequest? _request = widget.request;
  bool _loading = false;
  bool _busy = false;
  String? _errorKey;
  String? _substituteName;

  TimeOff? get _absence => widget.absence;

  @override
  void initState() {
    super.initState();
    final requestId = _absence?.requestId;
    if (_request == null && requestId != null && requestId.isNotEmpty) {
      unawaited(_loadRequest(requestId));
    } else {
      unawaited(_loadSubstitute());
    }
  }

  /// The request behind an absence it produced — the one place that says what
  /// can still be done about it.
  Future<void> _loadRequest(String id) async {
    setState(() => _loading = true);
    try {
      final found = await context.read<AbsenceRepository>().request(id);
      if (!mounted) return;
      setState(() {
        _request = found;
        _loading = false;
      });
      unawaited(_loadSubstitute());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  Future<void> _loadSubstitute() async {
    final id = _request?.substituteId;
    if (id == null || id.isEmpty) return;
    try {
      final found = await context.read<UserRepository>().usersByIds([id]);
      if (!mounted || found.isEmpty) return;
      final person = found.first;
      setState(
        () => _substituteName = person.displayName.isEmpty
            ? person.username
            : person.displayName,
      );
    } on ApiFailure {
      // The line simply stays away.
    }
  }

  AbsenceType? get _type {
    final typeId = _request?.typeId ?? _absence?.typeId;
    return widget.types.where((type) => type.id == typeId).firstOrNull;
  }

  String _title(BuildContext context) {
    final request = _request;
    if (request != null) return typeName(context, request, _type);
    final type = _type;
    if (type != null) return absenceTypeName(context, type);
    return context.t(_absence!.type.labelKey);
  }

  IconData get _icon {
    final type = _type;
    if (type != null) return absenceIcon(type.icon);
    final absence = _absence;
    return absence == null
        ? LucideIcons.calendarOff
        : timeOffIcon(absence.type);
  }

  String _subtitle(BuildContext context) {
    final request = _request;
    if (request != null) {
      return [
        spanLabel(context, request.from, request.to),
        daysLabel(context, request.milliDays),
      ].join(' · ');
    }
    final absence = _absence!;
    return [
      spanLabel(context, absence.from, absence.to),
      if (absence.halfDay) context.t('absence.sheet.halfDay'),
    ].join(' · ');
  }

  // --- steps --------------------------------------------------------------------

  /// Runs one step, says what came of it, and closes with "something changed".
  /// A refusal is the server's own sentence and leaves the sheet open.
  Future<void> _step(Future<Object?> Function() action, String doneKey) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showGlassToast(context, context.t(doneKey));
      Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  Future<void> _withdraw(AbsenceRequest request) => _step(
    () => context.read<AbsenceRepository>().withdraw(request.id),
    'absence.request.withdrawn',
  );

  Future<void> _cancel(AbsenceRequest request) async {
    final reason = await showAbsenceReasonSheet(
      context,
      titleKey: 'absence.request.cancelTitle',
      required: false,
    );
    if (reason == null || !mounted) return;
    await _step(
      () => context.read<AbsenceRepository>().cancel(
        request.id,
        note: reason.isEmpty ? null : reason,
      ),
      'absence.request.cancelled',
    );
  }

  Future<void> _approve(AbsenceRequest request) => _step(
    () => context.read<AbsenceRepository>().approve(request.id),
    'absence.request.approved',
  );

  Future<void> _reject(AbsenceRequest request) async {
    final reason = await showAbsenceReasonSheet(
      context,
      titleKey: 'absence.request.rejectTitle',
      required: true,
    );
    if (reason == null || !mounted) return;
    await _step(
      () => context.read<AbsenceRepository>().reject(request.id, note: reason),
      'absence.request.rejected',
    );
  }

  /// Edits a waiting request, or asks again from one that ended — both in the
  /// request form, on top of this sheet.
  Future<void> _reopenForm(AbsenceRequest request, {required bool edit}) async {
    final filed = await showAbsenceRequestSheet(
      context,
      types: widget.types,
      balances: widget.balances,
      existing: edit ? request : null,
      template: edit ? null : request,
    );
    if (filed != null && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _editDirect(TimeOff absence) async {
    final saved = await showTimeOffSheet(context, existing: absence);
    if ((saved ?? false) && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _deleteDirect(TimeOff absence) async {
    final id = absence.id;
    if (id == null) return;
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('availability.timeOff.delete'),
      message: context.t('availability.timeOff.deleteConfirm'),
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _step(
      () => context.read<AvailabilityRepository>().deleteTimeOff(id),
      'availability.timeOff.deleted',
    );
  }

  // --- drawing ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: _icon,
          title: _loading ? context.t('absence.sheet.title') : _title(context),
          subtitle: _loading ? '' : _subtitle(context),
        ),
        Flexible(child: _body(context)),
        _footer(context),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: HiveLoader(size: 30)),
      );
    }
    final request = _request;
    final absence = _absence;
    final errorKey = _errorKey;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: request != null
                ? AbsenceStatusChip(status: request.status)
                : AbsenceEnteredChip(sick: absence?.type == TimeOffType.sick),
          ),
          if (errorKey != null) ...[
            const SizedBox(height: 10),
            AbsenceNoteLine(
              icon: LucideIcons.circleAlert,
              tint: AppColors.danger,
              text: context.t(errorKey),
            ),
          ],
          ..._lines(context, request, absence),
          if (request != null && request.history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              context.t('absence.sheet.history'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 2),
            for (final step in request.history.reversed)
              AbsenceHistoryRow(
                step: step,
                hideNote: step.note == request.note,
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _lines(
    BuildContext context,
    AbsenceRequest? request,
    TimeOff? absence,
  ) {
    final note = request?.note ?? absence?.note;
    final decision = request?.decisionNote;
    final substitute = _substituteName;
    final lines = <(IconData, Color, String)>[
      if (request != null && request.status.open && request.balanceShort)
        (
          LucideIcons.triangleAlert,
          AppColors.warning,
          context.t('absence.request.balanceShortRow'),
        ),
      if (request != null && request.status.open && request.shortNotice)
        (
          LucideIcons.clock,
          AppColors.warning,
          context.t('absence.request.shortNoticeRow'),
        ),
      if (note != null && note.isNotEmpty)
        (LucideIcons.stickyNote, AppColors.inkSoft, note),
      if (substitute != null)
        (
          LucideIcons.userRound,
          AppColors.inkSoft,
          context.t(
            'absence.sheet.substitute',
            variables: {'name': substitute},
          ),
        ),
      if (decision != null && decision.isNotEmpty)
        (
          LucideIcons.messageSquareQuote,
          request!.status == AbsenceRequestStatus.rejected
              ? AppColors.danger
              : AppColors.inkSoft,
          decision,
        ),
      if (_startedForMe(request))
        (
          LucideIcons.lock,
          AppColors.inkSoft,
          context.t('absence.sheet.startedHint'),
        ),
      if (absence != null && request == null && absence.fromRequest)
        (
          LucideIcons.info,
          AppColors.inkSoft,
          context.t('absence.sheet.fromRequest'),
        ),
    ];
    return [
      for (final (icon, tint, text) in lines) ...[
        const SizedBox(height: 10),
        AbsenceNoteLine(icon: icon, tint: tint, text: text),
      ],
    ];
  }

  bool _isMine(AbsenceRequest request) => request.userId == widget.meId;

  /// Approved leave that has begun, for somebody who cannot cancel it: it is a
  /// record of what happened now, and only whoever keeps absences changes that.
  bool _startedForMe(AbsenceRequest? request) =>
      request != null &&
      request.status == AbsenceRequestStatus.approved &&
      !widget.keeper &&
      !request.from.isAfter(DateUtils.dateOnly(DateTime.now()));

  Widget _footer(BuildContext context) {
    final buttons = _buttons(context);
    if (buttons.isEmpty) return const SizedBox(height: 14);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        8,
        22,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: buttons,
      ),
    );
  }

  List<Widget> _buttons(BuildContext context) {
    if (_loading || _busy) {
      return _busy
          ? const [
              Padding(padding: EdgeInsets.all(8), child: HiveLoader(size: 24)),
            ]
          : const [];
    }
    final request = _request;
    final absence = _absence;
    if (request == null) {
      if (absence == null || absence.fromRequest) return const [];
      return [
        _outlined(
          icon: LucideIcons.trash2,
          label: context.t('common.delete'),
          danger: true,
          onPressed: () => unawaited(_deleteDirect(absence)),
        ),
        _filled(
          icon: LucideIcons.pencil,
          label: context.t('common.edit'),
          onPressed: () => unawaited(_editDirect(absence)),
        ),
      ];
    }
    final mine = _isMine(request);
    return switch (request.status) {
      AbsenceRequestStatus.submitted when mine => [
        _outlined(
          icon: LucideIcons.undo2,
          label: context.t('absence.request.withdraw'),
          onPressed: () => unawaited(_withdraw(request)),
        ),
        _filled(
          icon: LucideIcons.pencil,
          label: context.t('common.edit'),
          onPressed: () => unawaited(_reopenForm(request, edit: true)),
        ),
      ],
      AbsenceRequestStatus.submitted => [
        _outlined(
          icon: LucideIcons.x,
          label: context.t('absence.request.reject'),
          onPressed: () => unawaited(_reject(request)),
        ),
        _filled(
          icon: LucideIcons.check,
          label: context.t('absence.request.approve'),
          onPressed: () => unawaited(_approve(request)),
        ),
      ],
      AbsenceRequestStatus.approved when mine || widget.keeper => [
        if (!_startedForMe(request))
          _outlined(
            icon: LucideIcons.calendarMinus,
            label: context.t('absence.request.cancel'),
            danger: true,
            onPressed: () => unawaited(_cancel(request)),
          ),
      ],
      AbsenceRequestStatus.rejected ||
      AbsenceRequestStatus.withdrawn ||
      AbsenceRequestStatus.cancelled when mine => [
        _filled(
          icon: LucideIcons.calendarPlus,
          label: context.t('absence.sheet.askAgain'),
          onPressed: () => unawaited(_reopenForm(request, edit: false)),
        ),
      ],
      _ => const [],
    };
  }

  Widget _filled({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label),
  );

  Widget _outlined({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
  }) => OutlinedButton.icon(
    onPressed: onPressed,
    style: danger
        ? OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
          )
        : null,
    icon: Icon(icon, size: 16),
    label: Text(label),
  );
}
