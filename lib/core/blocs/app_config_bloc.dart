import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/hinata_repository.dart';
import '../models/core_models.dart';
import '../storage/app_storage.dart';

/// Connection lifecycle: pick server -> verify -> (setup) -> ready.
/// Also enforces the server's minimum app version on every start.
sealed class AppConfigEvent extends Equatable {
  const AppConfigEvent();

  @override
  List<Object?> get props => [];
}

class AppConfigStarted extends AppConfigEvent {
  const AppConfigStarted();
}

class ServerUrlSubmitted extends AppConfigEvent {
  const ServerUrlSubmitted(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

class SetupFinished extends AppConfigEvent {
  const SetupFinished();
}

enum AppConfigStatus {
  initial,
  connecting,
  needsServerUrl,
  needsSetup,
  updateRequired,
  ready,
}

class AppConfigState extends Equatable {
  const AppConfigState({
    this.status = AppConfigStatus.initial,
    this.meta,
    this.appVersion = '1.0.0',
    this.errorKey,
  });

  final AppConfigStatus status;
  final ServerMeta? meta;
  final String appVersion;
  final String? errorKey;

  AppConfigState copyWith({
    AppConfigStatus? status,
    ServerMeta? meta,
    String? appVersion,
    String? errorKey,
  }) =>
      AppConfigState(
        status: status ?? this.status,
        meta: meta ?? this.meta,
        appVersion: appVersion ?? this.appVersion,
        errorKey: errorKey,
      );

  @override
  List<Object?> get props => [status, meta, appVersion, errorKey];
}

class AppConfigBloc extends Bloc<AppConfigEvent, AppConfigState> {
  AppConfigBloc({required this.repository, required this.storage})
      : super(const AppConfigState()) {
    on<AppConfigStarted>(_onStarted, transformer: restartable());
    on<ServerUrlSubmitted>(_onServerUrlSubmitted, transformer: droppable());
    on<SetupFinished>(_onSetupFinished);
  }

  final HinataRepository repository;
  final AppStorage storage;

  /// Compile-time default backend, baked in via
  /// `--dart-define=HINATA_DEFAULT_SERVER=https://api.track.asta.hn`. Used when no
  /// server URL has been chosen yet (e.g. the hosted web build), so users land
  /// straight in the app instead of the connect screen. Empty ⇒ show /connect.
  static const String _defaultServer =
      String.fromEnvironment('HINATA_DEFAULT_SERVER');

  Future<void> _onStarted(AppConfigStarted event, Emitter<AppConfigState> emit) async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version;
    if (storage.serverUrl == null) {
      if (_defaultServer.isEmpty) {
        emit(state.copyWith(status: AppConfigStatus.needsServerUrl, appVersion: version));
        return;
      }
      await storage.setServerUrl(_defaultServer);
    }
    emit(state.copyWith(status: AppConfigStatus.connecting, appVersion: version));
    await _verify(emit);
  }

  Future<void> _onServerUrlSubmitted(
      ServerUrlSubmitted event, Emitter<AppConfigState> emit) async {
    var url = event.url.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      emit(state.copyWith(errorKey: 'connect.invalidUrl'));
      return;
    }
    emit(state.copyWith(status: AppConfigStatus.connecting));
    await storage.setServerUrl(url);
    await _verify(emit);
  }

  Future<void> _onSetupFinished(SetupFinished event, Emitter<AppConfigState> emit) async {
    await _verify(emit);
  }

  Future<void> _verify(Emitter<AppConfigState> emit) async {
    try {
      final meta = await repository.meta();
      if (isVersionBelow(state.appVersion, meta.minAppVersion)) {
        emit(state.copyWith(status: AppConfigStatus.updateRequired, meta: meta));
      } else if (!meta.setupCompleted) {
        emit(state.copyWith(status: AppConfigStatus.needsSetup, meta: meta));
      } else {
        emit(state.copyWith(status: AppConfigStatus.ready, meta: meta));
      }
    } catch (_) {
      emit(state.copyWith(
        status: AppConfigStatus.needsServerUrl,
        errorKey: 'connect.failed',
      ));
    }
  }
}
