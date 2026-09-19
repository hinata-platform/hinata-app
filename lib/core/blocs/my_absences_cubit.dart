import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/absence_models.dart';
import '../models/absence_request_models.dart';
import '../repositories/absence_repository.dart';

/// What the reader's own absence management looks like right now: the types on
/// offer, this year's balances, the requests nobody has decided yet, and whether
/// they keep absences for the organisation.
class MyAbsencesState extends Equatable {
  const MyAbsencesState({
    this.managed = false,
    this.loaded = false,
    this.types = const [],
    this.balances,
    this.pending = const [],
    this.keeper = false,
    this.revision = 0,
  });

  /// Whether the instance runs absence management. Without it absences are
  /// entered directly, as they were before requests existed, and nothing else
  /// here is read.
  final bool managed;

  /// Whether a load has answered — so a screen can tell "nothing pending" from
  /// "not asked yet".
  final bool loaded;

  final List<AbsenceType> types;
  final AbsenceBalances? balances;

  /// The reader's own requests that wait for a decision.
  final List<AbsenceRequest> pending;

  final bool keeper;

  /// Counts the reader's own changes. A screen that holds absences of its own
  /// — the calendar's window, the list's page — reloads when it moves.
  final int revision;

  /// The days of [pending], at local midnight — what the calendar hatches.
  Set<DateTime> get requestedDays => daysCovered(pending);

  /// The pending request covering [day], if one does.
  AbsenceRequest? pendingOn(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    for (final request in pending) {
      if (!date.isBefore(request.from) && !date.isAfter(request.to)) {
        return request;
      }
    }
    return null;
  }

  /// The types a person may ask for: active, and not sickness — sickness is
  /// reported, never requested (R11).
  List<AbsenceType> get askable => [
    for (final type in types)
      if (type.active && type.kind != AbsenceKind.sick) type,
  ];

  /// The types sickness is reported under.
  List<AbsenceType> get sickTypes => [
    for (final type in types)
      if (type.active && type.kind == AbsenceKind.sick) type,
  ];

  MyAbsencesState copyWith({
    bool? managed,
    bool? loaded,
    List<AbsenceType>? types,
    AbsenceBalances? balances,
    List<AbsenceRequest>? pending,
    bool? keeper,
    int? revision,
  }) => MyAbsencesState(
    managed: managed ?? this.managed,
    loaded: loaded ?? this.loaded,
    types: types ?? this.types,
    balances: balances ?? this.balances,
    pending: pending ?? this.pending,
    keeper: keeper ?? this.keeper,
    revision: revision ?? this.revision,
  );

  @override
  List<Object?> get props => [
    managed,
    loaded,
    types,
    balances,
    pending,
    keeper,
    revision,
  ];
}

/// The reader's own absence management, read once and shared.
///
/// Five places ask the same questions — the calendar hatching requested days,
/// the list and the timesheet marking them, the absences view listing them and
/// every "+" that opens the request form with the types and balances it shows.
/// Each of them used to read "my open requests" on every navigation between the
/// module's views, which are separate routes and rebuild their state on every
/// switch. One read here, again after each of the reader's own changes.
class MyAbsencesCubit extends Cubit<MyAbsencesState> {
  MyAbsencesCubit(this._absences) : super(const MyAbsencesState());

  final AbsenceRepository _absences;

  Future<void>? _inFlight;

  /// Most requests one person can have waiting that the calendar shows: a
  /// hundred absences a year is the server's own ceiling (HIN-91).
  static const int _pendingMax = 100;

  /// Reads everything once. [managed] is the instance's flag: with absence
  /// management off nothing is asked — the routes answer 404, and a 404 is
  /// what makes the app re-read its meta.
  Future<void> ensureLoaded({required bool managed}) {
    if (!managed) {
      if (state.managed || !state.loaded) {
        emit(MyAbsencesState(loaded: true, revision: state.revision));
      }
      return Future.value();
    }
    if (state.loaded && state.managed) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  /// Reads everything again — after the reader filed, edited, withdrew or
  /// cancelled something, or reported sickness — and moves [revision] so the
  /// screens holding absences of their own reload them.
  Future<void> changed() async {
    emit(state.copyWith(revision: state.revision + 1));
    if (!state.managed) return;
    await (_inFlight ??= _load().whenComplete(() => _inFlight = null));
  }

  /// Forgets the session that ended: another server may run another catalogue.
  void reset() {
    _inFlight = null;
    if (state != const MyAbsencesState()) emit(const MyAbsencesState());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>([
        _absences.types(),
        _absences.balances(year: DateTime.now().year),
        _absences.myRequests(
          status: AbsenceRequestStatus.submitted,
          size: _pendingMax,
        ),
        _absences.isKeeper(),
      ]);
      if (isClosed) return;
      final pending = results[2]! as ({List<AbsenceRequest> items, int total});
      emit(
        state.copyWith(
          managed: true,
          loaded: true,
          types: results[0]! as List<AbsenceType>,
          balances: results[1]! as AbsenceBalances,
          pending: pending.items,
          keeper: results[3]! as bool,
        ),
      );
    } catch (_) {
      // A page without the pending hatch is still a usable page; the next
      // change or the next session asks again.
      if (!isClosed) emit(state.copyWith(managed: true, loaded: true));
    }
  }
}
