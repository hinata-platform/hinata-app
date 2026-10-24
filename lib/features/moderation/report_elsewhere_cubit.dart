import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/account_repository.dart';

/// A report of something that is no post, page or person (HIN-175): why,
/// then where and what moderation should know.
class ReportElsewhereState extends Equatable {
  const ReportElsewhereState({
    this.category,
    this.sending = false,
    this.sent = false,
    this.errorKey,
  });

  /// The reason chosen; none while the first step is open.
  final ReportCategory? category;

  final bool sending;
  final bool sent;

  /// Why the server did not take it, in its own words.
  final String? errorKey;

  @override
  List<Object?> get props => [category, sending, sent, errorKey];
}

class ReportElsewhereCubit extends Cubit<ReportElsewhereState> {
  ReportElsewhereCubit(this._account) : super(const ReportElsewhereState());

  final AccountRepository _account;

  void choose(ReportCategory category) =>
      emit(ReportElsewhereState(category: category));

  /// Back to the reasons; what was typed stays in the fields.
  void back() => emit(const ReportElsewhereState());

  Future<void> send({required String location, String? explanation}) async {
    final category = state.category;
    if (category == null || state.sending) return;
    emit(ReportElsewhereState(category: category, sending: true));
    final text = explanation?.trim();
    try {
      await _account.reportElsewhere(
        location: location.trim(),
        category: category,
        explanation: text == null || text.isEmpty ? null : text,
      );
      emit(ReportElsewhereState(category: category, sent: true));
    } on ApiFailure catch (failure) {
      emit(ReportElsewhereState(category: category, errorKey: failure.message));
    } catch (_) {
      emit(
        ReportElsewhereState(category: category, errorKey: 'errors.unexpected'),
      );
    }
  }
}
