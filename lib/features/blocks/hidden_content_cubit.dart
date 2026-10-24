import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/repositories/account_repository.dart';

/// What the reader has folded away (HIN-26, HIN-168): the people they block.
///
/// One place for everything folded, so the comment that folds and the profile
/// that offers to block agree. What the reader chose to see anyway is kept for
/// the session only and never written anywhere.
class HiddenContentState extends Equatable {
  const HiddenContentState({this.blocked = const {}, this.revealed = const {}});

  /// The ids of the people the reader blocks.
  final Set<String> blocked;

  /// The ids of folded content the reader opened anyway in this session.
  final Set<String> revealed;

  /// Whether the reader blocks [personId].
  bool blocks(String personId) => blocked.contains(personId);

  /// Whether [contentId], written by [authorId], shows as a folded line.
  bool folds({required String authorId, required String contentId}) =>
      blocked.contains(authorId) && !revealed.contains(contentId);

  HiddenContentState copyWith({Set<String>? blocked, Set<String>? revealed}) =>
      HiddenContentState(
        blocked: blocked ?? this.blocked,
        revealed: revealed ?? this.revealed,
      );

  @override
  List<Object?> get props => [blocked, revealed];
}

/// Holds [HiddenContentState] for the whole app: read once per sign-in,
/// changed by every block and unblock, emptied on sign-out.
class HiddenContentCubit extends Cubit<HiddenContentState> {
  HiddenContentCubit(this._account, {required bool Function() enabled})
    : _enabled = enabled,
      super(const HiddenContentState());

  final AccountRepository _account;

  /// Whether the server knows blocking at all; an older one has no route.
  final bool Function() _enabled;

  /// Bumped by [reset], so an answer meant for an account that has left is
  /// dropped instead of folding the next account's comments.
  int _session = 0;

  /// Reads who the reader blocks. A failure folds nothing: a comment that
  /// shows when it should have folded is the lesser harm than a thread that
  /// cannot load, and the next sign-in asks again.
  Future<void> load() async {
    if (!_enabled()) return;
    final session = _session;
    try {
      final ids = await _account.blockedIds();
      if (isClosed || session != _session) return;
      emit(state.copyWith(blocked: ids));
    } catch (_) {
      // Nothing folded; see above.
    }
  }

  /// Blocks [personId], and their posts fold at once. A failure passes
  /// through as the repository's `ApiFailure` and changes nothing.
  Future<void> block(String personId) async {
    final session = _session;
    await _account.block(personId);
    if (isClosed || session != _session) return;
    emit(state.copyWith(blocked: {...state.blocked, personId}));
  }

  /// Lifts the block on [personId]. Fails like [block].
  Future<void> unblock(String personId) async {
    final session = _session;
    await _account.unblock(personId);
    if (isClosed || session != _session) return;
    emit(state.copyWith(blocked: {...state.blocked}..remove(personId)));
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
