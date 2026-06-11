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
    try {
      emit(FetchState<T>(data: await _loader()));
    } on ApiFailure catch (failure) {
      emit(state.copyWith(isLoading: false, errorKey: failure.message));
    } catch (_) {
      emit(state.copyWith(isLoading: false, errorKey: 'errors.unexpected'));
    }
  }
}
