import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/repositories/moderation_repository.dart';
import '../../../core/repositories/user_repository.dart';

enum CaseLoad { loading, ready, gone, failure }

class CaseDetailState extends Equatable {
  const CaseDetailState({
    this.load = CaseLoad.loading,
    this.detail,
    this.names = const {},
    this.busy = false,
    this.loadingReports = false,
    this.noticeKey,
    this.errorKey,
  });

  final CaseLoad load;
  final CaseDetail? detail;

  /// Display names of everyone the case names by id.
  final Map<String, String> names;

  /// A step on the case is on its way; every other one waits.
  final bool busy;
  final bool loadingReports;

  /// A word about the last step, shown once: done, or what moved meanwhile.
  final String? noticeKey;

  /// Why the last step was refused, as the server worded it.
  final String? errorKey;

  CaseDetailState copyWith({
    CaseLoad? load,
    CaseDetail? detail,
    Map<String, String>? names,
    bool? busy,
    bool? loadingReports,
    String? noticeKey,
    String? errorKey,
  }) => CaseDetailState(
    load: load ?? this.load,
    detail: detail ?? this.detail,
    names: names ?? this.names,
    busy: busy ?? this.busy,
    loadingReports: loadingReports ?? this.loadingReports,
    // Both words are said once; the next state drops them unless it says one.
    noticeKey: noticeKey,
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [
    load,
    detail,
    names,
    busy,
    loadingReports,
    noticeKey,
    errorKey,
  ];
}

/// One case on the moderation page (HIN-174): opened, taken, given back, its
/// reporters and withheld content uncovered with a reason, its files fetched
/// into memory, and every step after the decision.
///
/// Each step sends the revision last read. A 409 means somebody else moved
/// the case meanwhile: it is read again, and the reader is told whether it was
/// decided or only changed.
class CaseDetailCubit extends Cubit<CaseDetailState> {
  CaseDetailCubit(this._moderation, this._users, this.caseId)
    : super(const CaseDetailState());

  final ModerationRepository _moderation;
  final UserRepository _users;
  final String caseId;

  static const _reportsPage = 20;

  int get _rev => state.detail?.summary.rev ?? 0;

  Future<void> load() async {
    if (state.detail == null) emit(state.copyWith(load: CaseLoad.loading));
    await _read();
  }

  Future<void> _read({String? noticeKey}) async {
    try {
      final detail = await _moderation.detail(caseId);
      final names = await _namesOf(detail);
      if (isClosed) return;
      emit(
        state.copyWith(
          load: CaseLoad.ready,
          detail: detail,
          names: names,
          busy: false,
          noticeKey: noticeKey,
        ),
      );
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(
        state.copyWith(
          load: failure.statusCode == 404 ? CaseLoad.gone : CaseLoad.failure,
          busy: false,
          errorKey: state.detail == null ? null : failure.message,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(load: CaseLoad.failure, busy: false));
    }
  }

  /// The names held already, and the missing ones in one request. Names are a
  /// courtesy: without them the case still reads.
  Future<Map<String, String>> _namesOf(CaseDetail detail) async {
    final missing = [
      for (final id in detail.personIds)
        if (!state.names.containsKey(id)) id,
    ];
    if (missing.isEmpty) return state.names;
    try {
      final found = await _users.usersByIds(missing);
      return {
        ...state.names,
        for (final user in found) user.id: user.displayName,
      };
    } catch (_) {
      return state.names;
    }
  }

  Future<void> claim({bool takeOver = false}) =>
      _step(() => _moderation.claim(caseId, _rev, takeOver: takeOver));

  Future<void> release() => _step(() => _moderation.release(caseId, _rev));

  Future<void> revealReporter(String reportId, String reason) =>
      _step(() => _moderation.revealReporter(caseId, reportId, reason));

  /// Asks to open withheld content, or opens it as the second person.
  Future<void> revealEvidence(String reason) =>
      _step(() => _moderation.revealEvidence(caseId, reason));

  Future<void> confirm() => _step(
    () => _moderation.confirm(caseId, _rev),
    doneKey: 'moderation.case.confirmed',
  );

  Future<void> reject(String note) => _step(
    () => _moderation.reject(caseId, _rev, note),
    doneKey: 'moderation.case.rejected',
  );

  Future<void> restore(String note) => _step(
    () => _moderation.restore(caseId, _rev, note),
    doneKey: 'moderation.case.restored',
  );

  Future<void> liftSuspension(String note) => _step(
    () => _moderation.liftSuspension(caseId, _rev, note),
    doneKey: 'moderation.suspension.lifted',
  );

  Future<void> recordAppeal(String text, DateTime receivedAt) => _step(
    () => _moderation.recordAppeal(caseId, text, receivedAt),
    doneKey: 'moderation.appealReview.recorded',
  );

  Future<void> decideAppeal(AppealResult result, String note) => _step(
    () => _moderation.decideAppeal(caseId, _rev, result, note),
    doneKey: result == AppealResult.uphold
        ? 'moderation.appealReview.upheld'
        : 'moderation.appealReview.reversed',
  );

  Future<void> legalHold({
    DateTime? until,
    bool indefinite = false,
    required String reason,
  }) => _step(
    () => _moderation.legalHold(
      caseId,
      until: until,
      indefinite: indefinite,
      reason: reason,
    ),
    doneKey: 'moderation.case.held',
  );

  /// Reads the case again after its decision dialog closed with [noticeKey]:
  /// sent, or decided or changed by somebody else meanwhile.
  Future<void> afterDecision(String noticeKey) => _read(noticeKey: noticeKey);

  /// File [index] of the evidence, into memory and never onto the disk.
  Future<Uint8List> file(int index) => _moderation.evidenceFile(caseId, index);

  /// The next page of reports after the ones shown.
  Future<void> moreReports() async {
    final detail = state.detail;
    if (detail == null ||
        state.loadingReports ||
        detail.reports.length >= detail.reportTotal) {
      return;
    }
    emit(state.copyWith(loadingReports: true));
    try {
      final page = await _moderation.reports(
        caseId,
        detail.reports.length ~/ _reportsPage,
        _reportsPage,
      );
      if (isClosed) return;
      final known = {for (final report in detail.reports) report.id};
      emit(
        state.copyWith(
          detail: detail.copyWith(
            reports: [
              ...detail.reports,
              for (final report in page.items)
                if (!known.contains(report.id)) report,
            ],
          ),
          loadingReports: false,
        ),
      );
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(loadingReports: false, errorKey: failure.message));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(loadingReports: false));
    }
  }

  Future<void> _step(Future<Object?> Function() run, {String? doneKey}) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await run();
      await _read(noticeKey: doneKey);
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      final moved = movedMeanwhile(failure);
      if (moved != null) {
        await _read(noticeKey: moved);
        return;
      }
      emit(state.copyWith(busy: false, errorKey: failure.message));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(busy: false, errorKey: 'errors.unexpected'));
    }
  }
}

/// What a 409 on a step means for the reader: the case was decided or only
/// changed meanwhile; null for any other refusal.
String? movedMeanwhile(ApiFailure failure) {
  if (failure.statusCode != 409) return null;
  return switch (failure.details['code']) {
    'decided' => 'moderation.case.decidedMeanwhile',
    'changed' => 'moderation.case.changedMeanwhile',
    _ => null,
  };
}
