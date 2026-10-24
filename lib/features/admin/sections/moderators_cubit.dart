import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/admin_user_models.dart';
import '../../../core/repositories/admin_repository.dart';

enum ModeratorsStatus { loading, ready, failure }

/// Who moderates the instance, for Admin → Moderation (HIN-26).
class ModeratorsState extends Equatable {
  const ModeratorsState({
    this.status = ModeratorsStatus.loading,
    this.moderators = const [],
    this.total = 0,
    this.errorKey,
  });

  final ModeratorsStatus status;

  /// The first page of them, by name.
  final List<AdminUser> moderators;

  /// How many hold the role in all; more than [moderators] past the page.
  final int total;

  /// Why they could not be read, as an i18n key.
  final String? errorKey;

  @override
  List<Object?> get props => [status, moderators, total, errorKey];
}

/// Reads the people who hold the moderation role. They are few by design, so
/// one page holds them; the section names how many more there are past it.
class ModeratorsCubit extends Cubit<ModeratorsState> {
  ModeratorsCubit(this._admin) : super(const ModeratorsState());

  static const pageSize = 50;

  final AdminRepository _admin;

  Future<void> load() async {
    emit(const ModeratorsState());
    try {
      final page = await _admin.adminUsersPage(
        role: UserRoleFilter.moderator,
        sort: UserSortKey.name,
        desc: false,
        perPage: pageSize,
      );
      emit(
        ModeratorsState(
          status: ModeratorsStatus.ready,
          moderators: page.items,
          total: page.total,
        ),
      );
    } on ApiFailure catch (failure) {
      emit(
        ModeratorsState(
          status: ModeratorsStatus.failure,
          errorKey: failure.message,
        ),
      );
    } catch (_) {
      emit(
        const ModeratorsState(
          status: ModeratorsStatus.failure,
          errorKey: 'errors.unexpected',
        ),
      );
    }
  }
}
