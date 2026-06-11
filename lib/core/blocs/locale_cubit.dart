import 'dart:ui';

import 'package:hydrated_bloc/hydrated_bloc.dart';

/// Persisted locale selection (hydrated across restarts).
class LocaleCubit extends HydratedCubit<Locale> {
  LocaleCubit() : super(const Locale('en'));

  void setLocale(String code) => emit(Locale(code));

  @override
  Locale? fromJson(Map<String, dynamic> json) =>
      json['code'] is String ? Locale(json['code'] as String) : null;

  @override
  Map<String, dynamic>? toJson(Locale state) => {'code': state.languageCode};
}
