import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/work_models.dart' show RelativeDateBasis;
import '../../core/repositories/org_settings_repository.dart';

enum OrganizationStatus { loading, ready, failure }

/// The Organisation page: the settings as the server holds them, and the
/// deadline basis as the page shows it.
///
/// The time-tracking block inside [settings] is the page's draft and is
/// written into in place by the policy controls, exactly as the admin form it
/// came from was; a save replaces it with what the server answered. That is
/// why equality here cannot see a moved control: the page rebuilds the
/// section itself, and only a save or a load emits.
class OrganizationState extends Equatable {
  const OrganizationState({
    this.status = OrganizationStatus.loading,
    this.settings,
    this.basis,
    this.saving = false,
    this.errorKey,
  });

  final OrganizationStatus status;
  final OrgSettings? settings;

  /// The organisation's own deadline basis on screen, or null while it follows
  /// the platform. Compared with [settings] on save, so an untouched card sends
  /// nothing.
  final RelativeDateBasis? basis;
  final bool saving;

  /// Why the page could not load, as an i18n key.
  final String? errorKey;

  OrganizationState copyWith({
    OrganizationStatus? status,
    OrgSettings? settings,
    RelativeDateBasis? Function()? basis,
    bool? saving,
    String? Function()? errorKey,
  }) => OrganizationState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    basis: basis == null ? this.basis : basis(),
    saving: saving ?? this.saving,
    errorKey: errorKey == null ? this.errorKey : errorKey(),
  );

  @override
  List<Object?> get props => [status, settings, basis, saving, errorKey];
}

class OrganizationCubit extends Cubit<OrganizationState> {
  OrganizationCubit(this._repository) : super(const OrganizationState());

  final OrgSettingsRepository _repository;

  Future<void> load() async {
    emit(
      state.copyWith(status: OrganizationStatus.loading, errorKey: () => null),
    );
    try {
      final settings = await _repository.settings();
      emit(
        state.copyWith(
          status: OrganizationStatus.ready,
          settings: settings,
          basis: () => settings.defaultDeadlineBasis,
        ),
      );
    } on ApiFailure catch (failure) {
      emit(
        state.copyWith(
          status: OrganizationStatus.failure,
          errorKey: () => failure.message,
        ),
      );
    } catch (_) {
      // A malformed 200 (a proxy page, a cast error) is not an ApiFailure, and
      // without this the loader would spin forever.
      emit(
        state.copyWith(
          status: OrganizationStatus.failure,
          errorKey: () => 'errors.unexpected',
        ),
      );
    }
  }

  /// A basis for the organisation, or null to follow the platform.
  void setBasis(RelativeDateBasis? basis) =>
      emit(state.copyWith(basis: () => basis));

  /// Writes the draft. Completes with null on success, or the server's error
  /// key for the page to show.
  ///
  /// The basis goes along only while project templates are on ([templates]):
  /// the server refuses one while they are off. And only when it was moved.
  Future<String?> save({required bool templates}) async {
    final settings = state.settings;
    if (settings == null || state.saving) return null;
    emit(state.copyWith(saving: true));
    final basisChanged =
        templates && state.basis != settings.defaultDeadlineBasis;
    try {
      final saved = await _repository.update(
        timeTracking: settings.timeTracking,
        defaultDeadlineBasis: basisChanged ? state.basis : null,
        clearDefaultDeadlineBasis: basisChanged && state.basis == null,
      );
      emit(
        state.copyWith(
          settings: saved,
          basis: () => saved.defaultDeadlineBasis,
          saving: false,
        ),
      );
      return null;
    } on ApiFailure catch (failure) {
      emit(state.copyWith(saving: false));
      return failure.message;
    }
  }
}
