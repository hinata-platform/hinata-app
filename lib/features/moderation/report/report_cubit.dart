import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/moderation_repository.dart';

/// Reporting one thing from the app (HIN-173), or something without a menu of
/// its own (HIN-175): first the reason, then what moderation should know, then
/// sending it.
class ReportState extends Equatable {
  const ReportState({
    this.category,
    this.previous,
    this.alsoBlock = false,
    this.locationMissing = false,
    this.explanationMissing = false,
    this.sending = false,
    this.sent = false,
    this.errorKey,
    this.retryAt,
  });

  /// The reason chosen; none while the first step is open.
  final ReportCategory? category;

  /// The reason chosen before going back, so the first step can put the focus
  /// on it again.
  final ReportCategory? previous;

  /// Whether the author is blocked with the report.
  final bool alsoBlock;

  /// Something without a menu of its own needs to be said where it is.
  final bool locationMissing;

  /// The reason needs an explanation the field does not hold yet.
  final bool explanationMissing;

  final bool sending;
  final bool sent;

  /// Why the server did not take it, in its own words; the sheet stays open
  /// and keeps what was typed.
  final String? errorKey;

  /// When the reader may report again after too many reports; the latest
  /// moment it can be, since the server names the length of its window.
  final DateTime? retryAt;

  ReportState copyWith({
    bool? alsoBlock,
    bool? locationMissing,
    bool? explanationMissing,
    bool? sending,
    bool? sent,
    String? Function()? errorKey,
    DateTime? Function()? retryAt,
  }) => ReportState(
    category: category,
    previous: previous,
    alsoBlock: alsoBlock ?? this.alsoBlock,
    locationMissing: locationMissing ?? this.locationMissing,
    explanationMissing: explanationMissing ?? this.explanationMissing,
    sending: sending ?? this.sending,
    sent: sent ?? this.sent,
    errorKey: errorKey == null ? this.errorKey : errorKey(),
    retryAt: retryAt == null ? this.retryAt : retryAt(),
  );

  @override
  List<Object?> get props => [
    category,
    previous,
    alsoBlock,
    locationMissing,
    explanationMissing,
    sending,
    sent,
    errorKey,
    retryAt,
  ];
}

class ReportCubit extends Cubit<ReportState> {
  ReportCubit(this._moderation, this.target, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const ReportState());

  final ModerationRepository _moderation;

  /// What is reported; [TargetRef.elsewhere] for something that has no menu
  /// of its own, which the reader then says where it is.
  final TargetRef target;

  final DateTime Function() _now;

  void choose(ReportCategory category) => emit(
    ReportState(
      category: category,
      previous: state.previous,
      alsoBlock: state.alsoBlock,
    ),
  );

  /// Back to the reasons; what was typed stays in the field.
  void back() =>
      emit(ReportState(previous: state.category, alsoBlock: state.alsoBlock));

  void setAlsoBlock(bool value) => emit(state.copyWith(alsoBlock: value));

  /// Sends the report with [explanation], and [location] for something
  /// without a menu of its own. Fails in the sheet, never after it closed, and
  /// leaves the fields as they are.
  Future<void> send(String explanation, {String location = ''}) async {
    final category = state.category;
    if (category == null || state.sending) return;
    final text = explanation.trim();
    final place = location.trim();
    final locationMissing = target.kind == ContentKind.other && place.isEmpty;
    final explanationMissing =
        category.needsExplanation &&
        text.length < ReportCategory.explanationMin;
    if (locationMissing || explanationMissing) {
      emit(
        state.copyWith(
          locationMissing: locationMissing,
          explanationMissing: explanationMissing,
          errorKey: () => null,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        sending: true,
        locationMissing: false,
        explanationMissing: false,
        errorKey: () => null,
        retryAt: () => null,
      ),
    );
    try {
      await _moderation.report(
        target,
        category,
        explanation: text.isEmpty ? null : text,
        alsoBlock: state.alsoBlock,
        location: place.isEmpty ? null : place,
      );
      if (isClosed) return;
      emit(state.copyWith(sending: false, sent: true));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      final window = failure.statusCode == 429
          ? int.tryParse(failure.details['retryAfter'] ?? '')
          : null;
      emit(
        state.copyWith(
          sending: false,
          errorKey: () => window == null ? failure.message : null,
          retryAt: () =>
              window == null ? null : _now().add(Duration(seconds: window)),
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(sending: false, errorKey: () => 'errors.unexpected'));
    }
  }
}
