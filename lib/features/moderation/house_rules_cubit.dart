import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/account_repository.dart';

enum HouseRulesStatus { loading, ready, accepting, failure }

/// The instance's house rules for the person signed in (HIN-175).
class HouseRulesState extends Equatable {
  const HouseRulesState({
    this.status = HouseRulesStatus.loading,
    this.rules,
    this.errorKey,
  });

  final HouseRulesStatus status;
  final HouseRules? rules;

  /// Why the rules could not be read or accepted, as an i18n key or the
  /// server's own words.
  final String? errorKey;

  HouseRulesState copyWith({
    HouseRulesStatus? status,
    HouseRules? rules,
    String? Function()? errorKey,
  }) => HouseRulesState(
    status: status ?? this.status,
    rules: rules ?? this.rules,
    errorKey: errorKey == null ? this.errorKey : errorKey(),
  );

  @override
  List<Object?> get props => [status, rules, errorKey];
}

/// Reads the house rules and accepts the version on screen.
class HouseRulesCubit extends Cubit<HouseRulesState> {
  HouseRulesCubit(this._account) : super(const HouseRulesState());

  final AccountRepository _account;

  Future<void> load() async {
    emit(
      state.copyWith(status: HouseRulesStatus.loading, errorKey: () => null),
    );
    try {
      final rules = await _account.houseRules();
      if (isClosed) return;
      emit(HouseRulesState(status: HouseRulesStatus.ready, rules: rules));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(
        HouseRulesState(
          status: HouseRulesStatus.failure,
          errorKey: failure.message,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(
        const HouseRulesState(
          status: HouseRulesStatus.failure,
          errorKey: 'errors.unexpected',
        ),
      );
    }
  }

  /// Accepts the version on screen; true once it counted.
  ///
  /// Stays [HouseRulesStatus.accepting] on success: the gate leaves as soon as
  /// the session knows, and a button that comes back first invites a second
  /// tap. A newer version that arrived in the meantime answers 409; that one
  /// is read and shown instead, to be accepted on its own.
  Future<bool> accept() async {
    final rules = state.rules;
    if (rules == null || state.status == HouseRulesStatus.accepting) {
      return false;
    }
    emit(
      state.copyWith(status: HouseRulesStatus.accepting, errorKey: () => null),
    );
    try {
      await _account.acceptHouseRules(rules.version);
      return true;
    } on ApiFailure catch (failure) {
      if (isClosed) return false;
      if (failure.statusCode == 409) {
        await load();
        // Said only once the newer version is on screen; a failed read says
        // why it failed instead.
        if (!isClosed && state.status == HouseRulesStatus.ready) {
          emit(state.copyWith(errorKey: () => failure.message));
        }
        return false;
      }
      emit(
        state.copyWith(
          status: HouseRulesStatus.ready,
          errorKey: () => failure.message,
        ),
      );
      return false;
    } catch (_) {
      if (isClosed) return false;
      emit(
        state.copyWith(
          status: HouseRulesStatus.ready,
          errorKey: () => 'errors.unexpected',
        ),
      );
      return false;
    }
  }
}
