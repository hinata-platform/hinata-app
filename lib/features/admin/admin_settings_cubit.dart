import 'package:dio/dio.dart' show MultipartFile;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/repositories/meta_repository.dart';

enum AdminSettingsStatus { loading, ready, failure }

/// The admin area's settings draft, as the server last answered it.
///
/// The sections write into [settings] in place, exactly as they did when the
/// screen held the map itself; only a load or a save emits. That is why
/// equality here cannot see a moved control.
class AdminSettingsState extends Equatable {
  const AdminSettingsState({
    this.status = AdminSettingsStatus.loading,
    this.settings,
    this.saving = false,
    this.errorKey,
  });

  final AdminSettingsStatus status;
  final Map<String, dynamic>? settings;
  final bool saving;

  /// Why the settings could not be read, as an i18n key.
  final String? errorKey;

  AdminSettingsState copyWith({
    AdminSettingsStatus? status,
    Map<String, dynamic>? settings,
    bool? saving,
    String? Function()? errorKey,
  }) => AdminSettingsState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    saving: saving ?? this.saving,
    errorKey: errorKey == null ? this.errorKey : errorKey(),
  );

  @override
  List<Object?> get props => [status, settings, saving, errorKey];
}

/// The admin screen: reading and saving the platform settings, and the
/// organisation logo the General section uploads and previews.
class AdminSettingsCubit extends Cubit<AdminSettingsState> {
  AdminSettingsCubit({
    required AdminRepository admin,
    required MetaRepository meta,
  }) : _admin = admin,
       _meta = meta,
       super(const AdminSettingsState());

  final AdminRepository _admin;
  final MetaRepository _meta;

  Future<void> load() async {
    emit(
      state.copyWith(status: AdminSettingsStatus.loading, errorKey: () => null),
    );
    try {
      final settings = await _admin.adminSettings();
      emit(
        state.copyWith(status: AdminSettingsStatus.ready, settings: settings),
      );
    } on ApiFailure catch (failure) {
      emit(
        state.copyWith(
          status: AdminSettingsStatus.failure,
          errorKey: () => failure.message,
        ),
      );
    } catch (_) {
      // A malformed 200 payload (e.g. a cast error, an HTML proxy page) throws
      // outside ApiFailure — surface the generic error + Retry instead of
      // getting stuck on the loader forever.
      emit(
        state.copyWith(
          status: AdminSettingsStatus.failure,
          errorKey: () => 'errors.unexpected',
        ),
      );
    }
  }

  /// Writes the draft and keeps what the server answered. A failure passes
  /// through as the repository's [ApiFailure], for the screen to report.
  Future<void> save() async {
    final settings = state.settings;
    if (settings == null) return;
    emit(state.copyWith(saving: true));
    try {
      // Without the time-tracking block: it is kept on the Organisation page
      // now (HIN-129), and for an admin who also holds that role the copy
      // loaded here would overwrite what was saved there in the meantime.
      final saved = await _admin.updateAdminSettings(
        {...settings}..remove('timeTracking'),
      );
      emit(state.copyWith(settings: saved, saving: false));
    } catch (_) {
      emit(state.copyWith(saving: false));
      rethrow;
    }
  }

  /// Uploads a logo and answers with the URL to write into the draft.
  Future<String> uploadLogo(MultipartFile file) =>
      _admin.uploadOrganizationLogo(file);

  Future<void> deleteLogo() => _admin.deleteOrganizationLogo();

  /// The logo as the app serves it, past the HTTP cache when [cacheBust] is
  /// set.
  Future<({List<int> bytes, bool isSvg})?> logo({int? cacheBust}) =>
      _meta.organizationLogo(cacheBust: cacheBust);
}
