import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../api/hivora_repository.dart';
import '../models/core_models.dart';
import '../storage/app_storage.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthChecked extends AuthEvent {
  const AuthChecked();
}

class LoginSubmitted extends AuthEvent {
  const LoginSubmitted(this.identifier, this.password);

  final String identifier;
  final String password;

  @override
  List<Object?> get props => [identifier];
}

/// Tokens arriving via the SSO deep link (hivora://auth-callback).
class SsoTokensReceived extends AuthEvent {
  const SsoTokensReceived(this.accessToken, this.refreshToken);

  final String accessToken;
  final String refreshToken;
}

class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

enum AuthStatus { unknown, unauthenticated, authenticating, authenticated }

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.unknown, this.user, this.errorKey});

  final AuthStatus status;
  final AuthUser? user;
  final String? errorKey;

  AuthState copyWith({AuthStatus? status, AuthUser? user, String? errorKey}) =>
      AuthState(status: status ?? this.status, user: user ?? this.user, errorKey: errorKey);

  @override
  List<Object?> get props => [status, user, errorKey];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.repository, required this.storage}) : super(const AuthState()) {
    on<AuthChecked>(_onChecked, transformer: restartable());
    on<LoginSubmitted>(_onLogin, transformer: droppable());
    on<SsoTokensReceived>(_onSsoTokens, transformer: droppable());
    on<LogoutRequested>(_onLogout);
  }

  final HivoraRepository repository;
  final AppStorage storage;

  Future<void> _onChecked(AuthChecked event, Emitter<AuthState> emit) async {
    if (storage.accessToken == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    try {
      final user = await repository.me();
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } on ApiFailure {
      await storage.clearTokens();
      emit(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onLogin(LoginSubmitted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.authenticating));
    try {
      final result = await repository.login(event.identifier, event.password);
      await storage.setTokens(access: result.access, refresh: result.refresh);
      emit(AuthState(status: AuthStatus.authenticated, user: result.user));
    } on ApiFailure catch (failure) {
      emit(AuthState(
        status: AuthStatus.unauthenticated,
        errorKey: failure.statusCode == 401
            ? 'auth.invalidCredentials'
            : failure.statusCode == 429
                ? 'auth.tooManyAttempts'
                : failure.message,
      ));
    }
  }

  Future<void> _onSsoTokens(SsoTokensReceived event, Emitter<AuthState> emit) async {
    await storage.setTokens(access: event.accessToken, refresh: event.refreshToken);
    add(const AuthChecked());
  }

  Future<void> _onLogout(LogoutRequested event, Emitter<AuthState> emit) async {
    await storage.clearTokens();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}
