import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';

/// Generic async data holder used by read-mostly feature screens.
class FetchState<T> extends Equatable {
  const FetchState({this.data, this.isLoading = false, this.errorKey});

  final T? data;
  final bool isLoading;
  final String? errorKey;

  bool get hasData => data != null;

  FetchState<T> copyWith({T? data, bool? isLoading, String? errorKey}) =>
      FetchState<T>(
        data: data ?? this.data,
        isLoading: isLoading ?? this.isLoading,
        errorKey: errorKey,
      );

  @override
  List<Object?> get props => [data, isLoading, errorKey];
}

class FetchCubit<T> extends Cubit<FetchState<T>> {
  FetchCubit(this._loader) : super(FetchState<T>());

  final Future<T> Function() _loader;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    // The page that asked may be gone by the time the answer is: leaving it
    // closes the cubit, and an emit then throws instead of being dropped.
    try {
      final data = await _loader();
      if (!isClosed) emit(FetchState<T>(data: data));
    } on ApiFailure catch (failure) {
      if (!isClosed) {
        emit(state.copyWith(isLoading: false, errorKey: failure.message));
      }
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(isLoading: false, errorKey: 'errors.unexpected'));
      }
    }
  }
}
