import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/repositories/account_repository.dart';
import '../../core/repositories/moderation_repository.dart';

/// Why a piece of content shows as a folded line.
enum FoldReason {
  /// The reader blocks its author (HIN-168).
  blocked,

  /// The reader reported it (HIN-173).
  reported,
}

/// What the reader has folded away (HIN-26): the people they block
/// (HIN-168) and the comments they reported (HIN-173).
///
/// One place for everything folded, so the comment that folds and the profile
/// that offers to block agree. What the reader chose to see anyway is kept for
/// the session only and never written anywhere.
class HiddenContentState extends Equatable {
  const HiddenContentState({
    this.blocked = const {},
    this.reported = const {},
    this.revealed = const {},
  });

  /// The ids of the people the reader blocks.
  final Set<String> blocked;

  /// The ids of the comments the reader reported that are still there.
  final Set<String> reported;

  /// The ids of folded content the reader opened anyway in this session.
  final Set<String> revealed;

  /// Whether the reader blocks [personId].
  bool blocks(String personId) => blocked.contains(personId);

  /// Why [contentId], written by [authorId], shows as a folded line; null
  /// when it shows.
  FoldReason? foldOf({required String authorId, required String contentId}) {
    if (revealed.contains(contentId)) return null;
    if (blocked.contains(authorId)) return FoldReason.blocked;
    if (reported.contains(contentId)) return FoldReason.reported;
    return null;
  }

  /// Whether [contentId], written by [authorId], shows as a folded line.
  bool folds({required String authorId, required String contentId}) =>
      foldOf(authorId: authorId, contentId: contentId) != null;

  HiddenContentState copyWith({
    Set<String>? blocked,
    Set<String>? reported,
    Set<String>? revealed,
  }) => HiddenContentState(
    blocked: blocked ?? this.blocked,
    reported: reported ?? this.reported,
    revealed: revealed ?? this.revealed,
  );

  @override
  List<Object?> get props => [blocked, reported, revealed];
}

/// Holds [HiddenContentState] for the whole app: read once per sign-in,
/// changed by every block, unblock and report, emptied on sign-out.
class HiddenContentCubit extends Cubit<HiddenContentState> {
  HiddenContentCubit(
    this._account,
    this._moderation, {
    required FutureOr<bool> Function() enabled,
  }) : _enabled = enabled,
       super(const HiddenContentState());

  final AccountRepository _account;
  final ModerationRepository _moderation;

  /// Whether the server knows blocking and reporting at all; an older one has
  /// no route. Answered once the server has said so, which may be after the
  /// sign-in.
  final FutureOr<bool> Function() _enabled;

  /// Bumped by [reset], so an answer meant for an account that has left is
  /// dropped instead of folding the next account's comments.
  int _session = 0;

  /// Reads who the reader blocks and what they reported. A failure folds
  /// nothing: a comment that shows when it should have folded is the lesser
  /// harm than a thread that cannot load, and the next sign-in asks again.
  Future<void> load() async {
    final session = _session;
    if (!await _enabled() || isClosed || session != _session) return;
    await Future.wait([
      _read(
        _account.blockedIds,
        (ids) => state.copyWith(blocked: ids),
        session,
      ),
      _read(
        _moderation.reportedIds,
        (ids) => state.copyWith(reported: ids),
        session,
      ),
    ]);
  }

  Future<void> _read(
    Future<Set<String>> Function() ids,
    HiddenContentState Function(Set<String> ids) apply,
    int session,
  ) async {
    try {
      final read = await ids();
      if (isClosed || session != _session) return;
      emit(apply(read));
    } catch (_) {
      // Nothing folded; see [load].
    }
  }

  /// Blocks [personId], and their posts fold at once. A failure passes
  /// through as the repository's `ApiFailure` and changes nothing.
  Future<void> block(String personId) async {
    final session = _session;
    await _account.block(personId);
    if (isClosed || session != _session) return;
    noteBlocked(personId);
  }

  /// Folds the posts of [personId], blocked elsewhere, such as together with
  /// a report.
  void noteBlocked(String personId) {
    if (state.blocked.contains(personId)) return;
    emit(state.copyWith(blocked: {...state.blocked, personId}));
  }

  /// Lifts the block on [personId]. Fails like [block].
  Future<void> unblock(String personId) async {
    final session = _session;
    await _account.unblock(personId);
    if (isClosed || session != _session) return;
    emit(state.copyWith(blocked: {...state.blocked}..remove(personId)));
  }

  /// Folds the comment [commentId] the reader just reported.
  void noteReported(String commentId) {
    if (state.reported.contains(commentId)) return;
    emit(
      state.copyWith(
        reported: {...state.reported, commentId},
        revealed: {...state.revealed}..remove(commentId),
      ),
    );
  }

  /// Shows one folded item for the rest of the session.
  void reveal(String contentId) {
    if (state.revealed.contains(contentId)) return;
    emit(state.copyWith(revealed: {...state.revealed, contentId}));
  }

  /// Forgets the session that ended: whoever signs in next folds their own.
  void reset() {
    _session++;
    if (state != const HiddenContentState()) emit(const HiddenContentState());
  }
}
