import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/issue_detail.dart';
import '../../../core/repositories/issue_repository.dart';

/// What adding a person came to, for the toast the sheet shows.
enum AddOutcome { added, alreadyShared, alreadyMember, failed }

/// The share dialog's state: who the issue is shared with, the members it
/// names (who see it anyway), and which rows have a request in flight.
class IssueParticipantsState extends Equatable {
  const IssueParticipantsState({
    this.participants = const [],
    this.namedWithAccess = const [],
    this.loading = false,
    this.busy = const {},
    this.errorKey,
  });

  final List<IssueParticipant> participants;

  /// The people the issue names (reporter, assignees) who reach it anyway.
  final List<DirectoryUser> namedWithAccess;
  final bool loading;

  /// Ids of the people being added or removed right now.
  final Set<String> busy;

  /// The i18n key of the last failure, cleared by the next change.
  final String? errorKey;

  /// Whether the issue is shared with as many people as it can be.
  bool get isFull =>
      participants.length >= IssueParticipantsCubit.maxParticipants;

  IssueParticipantsState copyWith({
    List<IssueParticipant>? participants,
    bool? loading,
    Set<String>? busy,
    String? errorKey,
  }) => IssueParticipantsState(
    participants: participants ?? this.participants,
    namedWithAccess: namedWithAccess,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [
    participants,
    namedWithAccess,
    loading,
    busy,
    errorKey,
  ];
}

/// Shares one issue with people outside its project and takes them off again
/// (HIN-136). Both changes show at once and are put back if the server
/// refuses. Nothing is broadcast: no list shows participants, and the detail
/// re-reads its history when the dialog closes.
class IssueParticipantsCubit extends Cubit<IssueParticipantsState> {
  IssueParticipantsCubit({
    required IssueRepository issues,
    required this.issueId,
    required this.meId,
    List<DirectoryUser> namedWithAccess = const [],
  }) : _issues = issues,
       super(IssueParticipantsState(namedWithAccess: namedWithAccess));

  /// The most people one issue is shared with; the server holds the same cap.
  static const maxParticipants = 25;

  final IssueRepository _issues;
  final String issueId;

  /// The signed-in user, recorded as who added a row shown before the server
  /// answers.
  final String? meId;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    try {
      final list = await _issues.participants(issueId);
      if (isClosed) return;
      emit(state.copyWith(participants: list, loading: false));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, errorKey: failure.message));
    }
  }

  /// Shares the issue with [user]. The row shows at once; the server's list
  /// then decides, which is how a member picked from the directory is told
  /// apart: sharing with them changes nothing, so they are not listed.
  Future<AddOutcome> add(DirectoryUser user) async {
    if (state.participants.any((p) => p.id == user.id)) {
      return AddOutcome.alreadyShared;
    }
    if (state.namedWithAccess.any((m) => m.id == user.id)) {
      return AddOutcome.alreadyMember;
    }
    final before = state.participants;
    emit(
      state.copyWith(
        participants: [
          ...before,
          IssueParticipant(
            id: user.id,
            displayName: user.displayName.isEmpty
                ? user.username
                : user.displayName,
            avatarUrl: user.avatarUrl,
            pronouns: user.pronouns,
            addedAt: DateTime.now(),
            addedById: meId,
          ),
        ],
        busy: {...state.busy, user.id},
      ),
    );
    try {
      await _issues.addParticipant(issueId, user.id);
      final list = await _issues.participants(issueId);
      if (isClosed) return AddOutcome.added;
      emit(
        state.copyWith(
          participants: list,
          busy: {...state.busy}..remove(user.id),
        ),
      );
      return list.any((p) => p.id == user.id)
          ? AddOutcome.added
          : AddOutcome.alreadyMember;
    } on ApiFailure catch (failure) {
      if (isClosed) return AddOutcome.failed;
      emit(
        state.copyWith(
          participants: before,
          busy: {...state.busy}..remove(user.id),
          errorKey: failure.message,
        ),
      );
      return AddOutcome.failed;
    }
  }

  /// Takes [userId] off the issue; the row goes at once and comes back in
  /// its place if the server refuses.
  Future<bool> remove(String userId) async {
    final before = state.participants;
    emit(
      state.copyWith(
        participants: [
          for (final p in before)
            if (p.id != userId) p,
        ],
        busy: {...state.busy, userId},
      ),
    );
    try {
      await _issues.removeParticipant(issueId, userId);
      if (isClosed) return true;
      emit(state.copyWith(busy: {...state.busy}..remove(userId)));
      return true;
    } on ApiFailure catch (failure) {
      if (isClosed) return false;
      emit(
        state.copyWith(
          participants: before,
          busy: {...state.busy}..remove(userId),
          errorKey: failure.message,
        ),
      );
      return false;
    }
  }
}
