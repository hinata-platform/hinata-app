import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../board_card_list.dart';
import '../board_drag.dart';
import '../board_feedback.dart';
import 'board_wall_cubit.dart';

/// Dims the wall while a new read of it is under way. Only the dimming is
/// rebuilt when that starts or ends, never the cards under it.
class BoardWallDimmed extends StatelessWidget {
  const BoardWallDimmed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<BoardWallCubit, BoardWallState, bool>(
        selector: (wall) => wall.refreshing,
        builder: (context, refreshing) =>
            BoardDimmed(dimmed: refreshing, child: child),
      );
}

/// The most cards a column loads while the wall is grouped into lanes. Lanes
/// draw every card they hold at once, so past this the board offers the search
/// and the filter instead of another page.
const int kBoardLaneMaxCards = 300;

/// One column of a wall as the column draws it: its cards and count, and
/// whether it is reading on, failed to, or may.
class BoardColumnSlice extends Equatable {
  const BoardColumnSlice({
    required this.column,
    this.loadingMore = false,
    this.failed = false,
    this.canLoadMore = false,
  });

  /// The column called [name] on [wall], or null when the wall has none.
  static BoardColumnSlice? of(BoardWallState wall, String name) {
    final column = wall.column(name);
    if (column == null) return null;
    return BoardColumnSlice(
      column: column,
      loadingMore: wall.loadingMore.contains(name),
      failed: wall.failedColumns.contains(name),
      canLoadMore:
          column.hasMore &&
          wall.status == BoardWallStatus.ready &&
          !wall.refreshing,
    );
  }

  final BoardColumnView column;
  final bool loadingMore;
  final bool failed;

  /// Whether the column may read its next page now: it holds more, and no read
  /// of the whole wall is under way that would answer for it anew.
  final bool canLoadMore;

  @override
  List<Object?> get props => [column, loadingMore, failed, canLoadMore];
}

/// Whether [next] draws another wall than [previous] beyond what each column
/// picks up for itself: another board or sprint, other columns, other people
/// or references.
bool boardWallReshaped(BoardWallState previous, BoardWallState next) =>
    previous.status != next.status ||
    previous.board != next.board ||
    previous.sprintId != next.sprintId ||
    previous.pickedSprintId != next.pickedSprintId ||
    !listEquals(previous.sprints, next.sprints) ||
    !identical(previous.users, next.users) ||
    !identical(previous.refs, next.refs) ||
    !listEquals(
      [for (final column in previous.columns) column.name],
      [for (final column in next.columns) column.name],
    );

/// A wall's columns side by side, as wide as the room lets them be, each
/// rebuilt only when its own cards, count or reading changes.
///
/// A page arriving for one column, or a card moved between two, rebuilds those
/// and leaves the others as they are.
class BoardWallColumns extends StatelessWidget {
  const BoardWallColumns({
    super.key,
    required this.names,
    required this.padding,
    required this.columnBuilder,
  });

  /// The columns to draw, by name, in order.
  final List<String> names;
  final EdgeInsets padding;
  final Widget Function(
    BuildContext context,
    BoardColumnSlice slice,
    double width,
  )
  columnBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // The wall sizes its columns to the space it actually got, so a board with
    // more columns than fit at the design width still shows all of them where
    // there is room.
    builder: (context, constraints) {
      final width = boardColumnWidth(
        constraints.maxWidth - padding.horizontal,
        names.length,
      );
      // The horizontal controller lets a carried card pull the wall along when
      // it reaches an edge, so an off-screen column is still reachable
      // mid-drag.
      final snap = boardSnapStride(context, columnWidth: width);
      return BoardDragScroller(
        snapStride: snap,
        builder: (context, _, horizontal) => ListView.separated(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          physics: BoardColumnSnapPhysics.maybe(snap),
          padding: padding,
          itemCount: names.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: BoardWall.columnGap),
          itemBuilder: (context, index) =>
              BlocSelector<BoardWallCubit, BoardWallState, BoardColumnSlice?>(
                selector: (wall) => BoardColumnSlice.of(wall, names[index]),
                builder: (context, slice) => slice == null
                    ? const SizedBox.shrink()
                    : columnBuilder(context, slice, width),
              ),
        ),
      );
    },
  );
}

/// What a grouped wall offers under a column's lanes: the way to its cards
/// that are not loaded yet, until the column holds [kBoardLaneMaxCards].
class BoardLaneFooter extends StatelessWidget {
  const BoardLaneFooter({super.key, required this.name});

  /// The column's name.
  final String name;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<BoardWallCubit, BoardWallState, BoardColumnSlice?>(
        selector: (wall) => BoardColumnSlice.of(wall, name),
        builder: (context, slice) {
          final column = slice?.column;
          if (slice == null || column == null || !column.hasMore) {
            return const SizedBox.shrink();
          }
          if (column.issues.length >= kBoardLaneMaxCards) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                context.t(
                  'board.laneLimit',
                  variables: {'count': '${column.remaining}'},
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            );
          }
          return BoardLoadMore(
            remaining: column.remaining,
            loading: slice.loadingMore,
            onPressed: slice.canLoadMore
                ? () => context.read<BoardWallCubit>().loadMore(name)
                : null,
          );
        },
      );
}
