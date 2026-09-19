/// The ways into an absence, the same from every screen of the time module.
///
/// The calendar's day menu, the "+" of every view, the day chips of the list and
/// the timesheet, and the absences view all end up here, so asking for
/// leave from the month grid and from the list is one form with one outcome —
/// and whatever changed is told to [MyAbsencesCubit] once, which is what makes
/// every other view of the module redraw its hatch and its marks.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/my_absences_cubit.dart';
import '../../core/models/absence_request_models.dart';
import '../../core/models/availability_models.dart';
import '../account/time_off_sheet.dart';
import 'absence_request_sheet.dart';
import 'absence_sheet.dart';

/// Whether the instance runs absence management — requests, approvals, types.
/// Without it an absence is entered directly, as it was before requests.
bool absencesManaged(BuildContext context) =>
    context.read<AppConfigBloc>().state.meta?.absenceManagement ?? false;

/// The reader's own absence management, read once per session.
Future<MyAbsencesState> _mine(BuildContext context) async {
  final cubit = context.read<MyAbsencesCubit>();
  await cubit.ensureLoaded(managed: absencesManaged(context));
  return cubit.state;
}

/// Asks for time off from [from] to [to] — or, without absence management,
/// enters it. Resolves to true when something was filed.
Future<bool> askForAbsence(
  BuildContext context, {
  DateTime? from,
  DateTime? to,
}) async {
  final cubit = context.read<MyAbsencesCubit>();
  if (!absencesManaged(context)) {
    final saved = await showTimeOffSheet(
      context,
      initialRange: from == null
          ? null
          : DateTimeRange(start: from, end: to ?? from),
    );
    if (saved ?? false) unawaited(cubit.changed());
    return saved ?? false;
  }
  final mine = await _mine(context);
  if (!context.mounted) return false;
  final filed = await showAbsenceRequestSheet(
    context,
    types: mine.askable,
    balances: mine.balances,
    initialFrom: from,
    initialTo: to,
  );
  if (filed != null) unawaited(cubit.changed());
  return filed != null;
}

/// Reports sickness from [from] to [to]. Resolves to true when it was reported.
///
/// Only with absence management; without it sickness is an absence like any
/// other and [askForAbsence] enters it.
Future<bool> reportSickness(
  BuildContext context, {
  DateTime? from,
  DateTime? to,
}) async {
  final cubit = context.read<MyAbsencesCubit>();
  final mine = await _mine(context);
  if (!context.mounted) return false;
  final reported = await showSickReportSheet(
    context,
    types: mine.sickTypes,
    initialFrom: from,
    initialTo: to,
  );
  if (reported != null) unawaited(cubit.changed());
  return reported != null;
}

/// What an absence sheet is opened on: an absence somebody entered, or a
/// request somebody made. Exactly one of the two, said in the type rather than
/// in a pair of optional arguments the caller has to keep apart.
sealed class AbsenceTarget {
  const AbsenceTarget();

  /// The absence itself, from a list, a calendar band or a day chip.
  const factory AbsenceTarget.entered(TimeOff absence) = EnteredAbsence;

  /// A request, decided or not, from one of the request lists.
  const factory AbsenceTarget.requested(AbsenceRequest request) =
      RequestedAbsence;
}

class EnteredAbsence extends AbsenceTarget {
  const EnteredAbsence(this.absence);

  final TimeOff absence;
}

class RequestedAbsence extends AbsenceTarget {
  const RequestedAbsence(this.request);

  final AbsenceRequest request;
}

/// Opens [target] with everything that can still be done about it — edit and
/// delete for one entered directly, withdraw or edit while a request waits,
/// approve or reject somebody else's, cancel an approved one, ask again after
/// a refusal. Resolves to true when something changed.
Future<bool> openAbsence(BuildContext context, AbsenceTarget target) async {
  final cubit = context.read<MyAbsencesCubit>();
  final mine = await _mine(context);
  if (!context.mounted) return false;
  final changed = await showAbsenceSheet(
    context,
    target: target,
    types: mine.types,
    askable: mine.askable,
    balances: mine.balances,
    keeper: mine.keeper,
  );
  if (changed) unawaited(cubit.changed());
  return changed;
}
