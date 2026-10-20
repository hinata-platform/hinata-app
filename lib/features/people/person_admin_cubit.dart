import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/admin_user_models.dart';
import '../admin/users/user_management_cubit.dart';

class PersonAdminState extends Equatable {
  const PersonAdminState({
    this.user,
    this.lastActiveAdmin = false,
    this.loading = true,
    this.errorKey,
  });

  final AdminUser? user;

  /// The person is the one active administrator left, who can neither lose the
  /// role nor be deleted.
  final bool lastActiveAdmin;
  final bool loading;
  final String? errorKey;

  @override
  List<Object?> get props => [user, lastActiveAdmin, loading, errorKey];
}

/// The administrator's side of a person's profile: the account as the admin
/// area knows it, for the same actions the admin area's drawer offers.
///
/// Asks the admin endpoints the directory asks; only for a reader who holds
/// the platform role, which the profile says before this is ever built.
class PersonAdminCubit extends Cubit<PersonAdminState> {
  PersonAdminCubit(this.users, this.personId) : super(const PersonAdminState());

  final UserManagementCubit users;
  final String personId;

  Future<void> load() async {
    try {
      final user = await users.user(personId);
      // The directory's counts say how many active administrators there are;
      // one row is all it takes to read them.
      final page = await users.users(perPage: 1);
      if (isClosed) return;
      emit(
        PersonAdminState(
          user: user,
          lastActiveAdmin: page.isLastActiveAdmin(user),
          loading: false,
        ),
      );
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(
        PersonAdminState(
          user: state.user,
          lastActiveAdmin: state.lastActiveAdmin,
          loading: false,
          errorKey: failure.message,
        ),
      );
    }
  }
}
