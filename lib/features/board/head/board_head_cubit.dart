import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/board_page_models.dart';
import '../../../core/repositories/board_repository.dart';
import '../board_filter.dart';
import '../board_swimlanes.dart' show BoardGrouping;

/// How long the options a board's filter offers stay fresh enough to show
/// once a change may have altered them.
const Duration kBoardFacetsFresh = Duration(seconds: 60);

/// The cards a board's facets are gathered over: the whole board or one
/// sprint, of the shape the board lists.
class BoardFacetsScope extends Equatable {
  const BoardFacetsScope({this.sprintId, this.shape = BoardCardShape.wall});

  final String? sprintId;
  final BoardCardShape shape;

  @override
  List<Object?> get props => [sprintId, shape];
}

/// A board's head: the search typed into it, the filter, the grouping, and
/// what the filter and the row of faces can offer.
class BoardHeadState extends Equatable {
  const BoardHeadState({
    this.filter = BoardFilter.empty,
    this.text = '',
    this.grouping = BoardGrouping.none,
    this.facets = BoardFacets.empty,
  });

  final BoardFilter filter;

  /// The search typed into the head.
  final String text;
  final BoardGrouping grouping;

  /// What the filter and the faces offer, over every card of the board.
  final BoardFacets facets;

  /// The cards the wall wants: sub-tasks become cards of their own only when
  /// the wall is grouped by them.
  BoardCardShape get wallShape => grouping == BoardGrouping.subtask
      ? BoardCardShape.subtasks
      : BoardCardShape.wall;

  /// What the server narrows by, for cards of [shape].
  BoardQuery query(BoardCardShape shape) =>
      filter.toQuery(text: text, shape: shape);

  /// Whether [other] narrows the cards another way: another search, filter or
  /// grouping.
  bool narrowsOtherThan(BoardHeadState other) =>
      text.trim() != other.text.trim() ||
      filter != other.filter ||
      grouping != other.grouping;

  /// Whether [other] draws the head another way. The search is not part of it:
  /// the field shows what is typed by itself, and a page rebuilt letter by
  /// letter gains nothing from it.
  bool drawsOtherThan(BoardHeadState other) =>
      filter != other.filter ||
      grouping != other.grouping ||
      facets != other.facets;

  BoardHeadState copyWith({
    BoardFilter? filter,
    String? text,
    BoardGrouping? grouping,
    BoardFacets? facets,
  }) => BoardHeadState(
    filter: filter ?? this.filter,
    text: text ?? this.text,
    grouping: grouping ?? this.grouping,
    facets: facets ?? this.facets,
  );

  @override
  List<Object?> get props => [filter, text, grouping, facets];
}

/// The head both kinds of board wear: what is searched for, filtered by and
/// grouped by, and the facets the filter offers.
///
/// The facets are gathered on the server over every card of the board, which
/// makes them the most expensive read a board has. So they are read when the
/// board opens, for the faces, and after that only when they may be out of
/// date and somebody looks: the filter reads them again after any change, the
/// faces at most once every [facetsFresh]. An answer for a sprint or shape the
/// board has left is never shown.
class BoardHeadCubit extends Cubit<BoardHeadState> {
  BoardHeadCubit({
    required BoardRepository boards,
    required this.boardId,
    this.facetsFresh = kBoardFacetsFresh,
    DateTime Function()? now,
  }) : _boards = boards,
       _now = now ?? DateTime.now,
       super(const BoardHeadState());

  final BoardRepository _boards;
  final String boardId;
  final Duration facetsFresh;
  final DateTime Function() _now;

  /// The scope of the facets held or being read.
  BoardFacetsScope? _scope;
  DateTime? _readAt;

  /// Whether a change may have altered the facets since they were read.
  bool _outdated = false;
  int _generation = 0;
  Future<void>? _reading;

  void search(String text) => emit(state.copyWith(text: text));

  void setFilter(BoardFilter filter) => emit(state.copyWith(filter: filter));

  /// Toggles the person [userId] among the assignees filtered by.
  void toggleAssignee(String userId) =>
      setFilter(state.filter.toggle(BoardFilterFacet.assignee, userId));

  void group(BoardGrouping grouping) =>
      emit(state.copyWith(grouping: grouping));

  /// Notes that the board's cards changed, so the facets may be out of date.
  void facetsChanged() => _outdated = true;

  /// Makes sure facets over [scope] are there. They are read when there are
  /// none for it yet, and read again when a change may have altered them: for
  /// the filter ([forFilter]) right away, for the faces once they are older
  /// than [facetsFresh]. The filter reads facets that went unchanged for as
  /// long again as well, since changes made by others are never announced.
  Future<void> ensureFacets(BoardFacetsScope scope, {bool forFilter = false}) {
    final reading = _reading;
    if (reading != null && scope == _scope) return reading;
    final readAt = _readAt;
    final age = readAt == null ? null : _now().difference(readAt);
    final due =
        scope != _scope ||
        age == null ||
        (forFilter
            ? _outdated || age >= facetsFresh
            : _outdated && age >= facetsFresh);
    if (!due) return Future.value();
    return _reading = _read(scope);
  }

  Future<void> _read(BoardFacetsScope scope) async {
    final generation = ++_generation;
    if (scope != _scope) {
      _scope = scope;
      _readAt = null;
    }
    _outdated = false;
    try {
      final facets = await _boards.facets(
        boardId,
        sprintId: scope.sprintId,
        shape: scope.shape,
      );
      if (isClosed || generation != _generation) return;
      _readAt = _now();
      emit(state.copyWith(facets: facets));
    } catch (_) {
      if (generation != _generation) return;
      // The filter keeps the options it had, and the next call reads again.
      _outdated = true;
    } finally {
      if (generation == _generation) _reading = null;
    }
  }
}
