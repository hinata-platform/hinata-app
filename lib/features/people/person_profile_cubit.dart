import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/person_profile.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/util/zone_clock.dart';

enum PersonProfileStatus { loading, ready, notFound, failure }

class PersonProfileState extends Equatable {
  const PersonProfileState({
    this.status = PersonProfileStatus.loading,
    this.profile,
    this.errorKey,
    this.clockReady = false,
  });

  final PersonProfileStatus status;
  final PersonProfile? profile;
  final String? errorKey;

  /// The zone database is loaded, so the person's local time can be told.
  final bool clockReady;

  PersonProfileState copyWith({
    PersonProfileStatus? status,
    PersonProfile? profile,
    String? errorKey,
    bool? clockReady,
  }) => PersonProfileState(
    status: status ?? this.status,
    profile: profile ?? this.profile,
    errorKey: errorKey,
    clockReady: clockReady ?? this.clockReady,
  );

  @override
  List<Object?> get props => [status, profile, errorKey, clockReady];
}

/// One person's profile (HIN-165): who they are, what the reader shares with
/// them, and where their day stands.
class PersonProfileCubit extends Cubit<PersonProfileState> {
  PersonProfileCubit(
    this._users,
    this.personId, {
    Future<void> Function()? loadClock,
  }) : _loadClock = loadClock ?? ZoneClock.ensureLoaded,
       super(const PersonProfileState());

  final UserRepository _users;
  final String personId;
  final Future<void> Function() _loadClock;

  Future<void> load() async {
    if (state.profile == null) {
      emit(state.copyWith(status: PersonProfileStatus.loading));
    }
    try {
      final profile = await _users.profile(personId);
      if (isClosed) return;
      emit(state.copyWith(status: PersonProfileStatus.ready, profile: profile));
      // The profile shows without waiting for the zone database; the local
      // time joins it once the database is there.
      if (!state.clockReady) {
        await _loadClock();
        if (!isClosed) emit(state.copyWith(clockReady: true));
      }
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: failure.statusCode == 404
              ? PersonProfileStatus.notFound
              : PersonProfileStatus.failure,
          errorKey: failure.message,
        ),
      );
    }
  }
}
