import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/shift_models.dart';
import '../../core/repositories/shift_repository.dart';

class ShiftFeedState extends Equatable {
  const ShiftFeedState({
    this.loading = true,
    this.status,
    this.address,
    this.busy = false,
    this.errorKey,
  });

  final bool loading;
  final ShiftFeedStatus? status;

  /// The address of a feed made just now. Held only in memory and only until
  /// the section goes: the server never shows it again, and the app never
  /// stores it.
  final ShiftFeedAddress? address;

  /// A change in the air.
  final bool busy;
  final String? errorKey;

  bool get exists => status?.exists ?? false;

  @override
  List<Object?> get props => [loading, status, address, busy, errorKey];
}

/// The caller's personal shift feed (HIN-47): whether there is one, making a
/// new one (which ends the old one), and removing it.
class ShiftFeedCubit extends Cubit<ShiftFeedState> {
  ShiftFeedCubit(this._shifts) : super(const ShiftFeedState());

  final ShiftRepository _shifts;

  Future<void> load() async {
    emit(ShiftFeedState(status: state.status, address: state.address));
    try {
      final status = await _shifts.feed();
      if (isClosed) return;
      emit(
        ShiftFeedState(loading: false, status: status, address: state.address),
      );
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(_failed(failure.message));
    } catch (_) {
      if (isClosed) return;
      emit(_failed('errors.unexpected'));
    }
  }

  ShiftFeedState _failed(String key) => ShiftFeedState(
    loading: false,
    status: state.status,
    address: state.address,
    errorKey: key,
  );

  /// Makes a new address and shows it once; an existing feed stops working.
  /// Null on success, else the message key.
  Future<String?> create() async {
    if (state.busy) return null;
    emit(
      ShiftFeedState(
        loading: false,
        status: state.status,
        address: state.address,
        busy: true,
      ),
    );
    try {
      final address = await _shifts.createFeed();
      if (isClosed) return null;
      emit(
        ShiftFeedState(
          loading: false,
          status: ShiftFeedStatus(exists: true, createdAt: DateTime.now()),
          address: address,
        ),
      );
      return null;
    } on ApiFailure catch (failure) {
      if (!isClosed) emit(_failed(failure.message));
      return failure.message;
    } catch (_) {
      if (!isClosed) emit(_failed('errors.unexpected'));
      return 'errors.unexpected';
    }
  }

  /// Ends the feed. Null on success, else the message key.
  Future<String?> remove() async {
    if (state.busy) return null;
    emit(
      ShiftFeedState(
        loading: false,
        status: state.status,
        address: state.address,
        busy: true,
      ),
    );
    try {
      await _shifts.deleteFeed();
      if (isClosed) return null;
      emit(const ShiftFeedState(loading: false, status: ShiftFeedStatus()));
      return null;
    } on ApiFailure catch (failure) {
      if (!isClosed) emit(_failed(failure.message));
      return failure.message;
    } catch (_) {
      if (!isClosed) emit(_failed('errors.unexpected'));
      return 'errors.unexpected';
    }
  }

  /// Forgets the address shown once, when the person is done with it.
  void hideAddress() => emit(
    ShiftFeedState(
      loading: false,
      status: state.status,
      errorKey: state.errorKey,
    ),
  );
}
