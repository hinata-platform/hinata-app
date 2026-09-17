import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/board_page_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/read_on_trigger.dart';
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

/// How many cards a column of a grouped wall reads at a time: the most the
/// server hands over, rather than the screenful a scrolled column reads.
///
/// A lane holds the cards of one group alone, and those may sit anywhere in a
/// column — an epic's finished work lies behind everything else that was ever
/// finished — so the lanes need the column read far down, and reading it a
/// screenful at a time would be ten requests where three will do.
const int kBoardLanePageSize = kBoardMaxPageSize;

/// One column of a wall as the column draws it: its cards and count, and
/// whether it is reading on or may.
class BoardColumnSlice extends Equatable {
  const BoardColumnSlice({
    required this.column,
    this.loadingMore = false,
    this.canLoadMore = false,
    this.failed = false,
  });

  /// The column called [name] on [wall], or null when the wall has none.
  static BoardColumnSlice? of(BoardWallState wall, String name) {
    final column = wall.column(name);
    if (column == null) return null;
    return BoardColumnSlice(
      column: column,
      loadingMore: wall.loadingMore.contains(name),
      canLoadMore:
          column.hasMore &&
          wall.status == BoardWallStatus.ready &&
          !wall.refreshing,
      failed: wall.failedColumns.contains(name),
    );
  }

  final BoardColumnView column;
  final bool loadingMore;

  /// Whether the column may read its next page now: it holds more, and no read
  /// of the whole wall is under way that would answer for it anew.
  final bool canLoadMore;

  /// Whether the column's last page did not come.
  final bool failed;

  /// Whether the column reads its next page by itself while the wall is
  /// grouped into lanes: it may read on, it is not reading already, it holds
  /// fewer cards than the lanes draw at once, and its last page came — unless
  /// [retry] asks again for one that did not.
  bool fillsLanes({bool retry = false}) =>
      canLoadMore &&
      !loadingMore &&
      column.issues.length < kBoardLaneMaxCards &&
      (retry || !failed);

  @override
  List<Object?> get props => [column, loadingMore, canLoadMore, failed];
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

/// Stands under a column's lanes on a grouped wall and reads the column on
/// while they need it: a spinner while a page is on its way, whose room it
/// keeps in between, and once the column holds [kBoardLaneMaxCards] how many
/// more there are to search or filter for.
///
/// A lane holds the cards of one group alone, and a column hands them over in
/// board order, so a group's cards may all sit past the first page: an epic
/// whose work is done shows an empty Done lane until the column has been read
/// that far. So the columns of a grouped wall read on by themselves, page
/// after page, rather than waiting to be scrolled to their end — which the
/// lanes of a board that fills the screen never are.
///
/// It reads in [kBoardLanePageSize] cards and stops at [kBoardLaneMaxCards],
/// where the board offers the search and the filter instead. A page that did
/// not come stops it as well, and is asked for again only once someone scrolls
/// the lanes, see [readOnUnderLanes].
class BoardLaneFooter extends StatefulWidget {
  const BoardLaneFooter({super.key, required this.name});

  /// The column's name.
  final String name;

  @override
  State<BoardLaneFooter> createState() => _BoardLaneFooterState();
}

class _BoardLaneFooterState extends State<BoardLaneFooter> {
  /// Whether an ask waits for the frame to end, so that coming in and a page
  /// arriving within the same frame ask once.
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _askAfterFrame();
  }

  /// Has the column read on once the frame is drawn, if it may then: asked
  /// from a build or a listener, the wall would be changed while it is being
  /// drawn.
  void _askAfterFrame() {
    if (_asking) return;
    _asking = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _asking = false;
        if (!mounted) return;
        final wall = context.read<BoardWallCubit>();
        final slice = BoardColumnSlice.of(wall.state, widget.name);
        if (slice?.fillsLanes() ?? false) {
          unawaited(wall.loadMore(widget.name, size: kBoardLanePageSize));
        }
      })
      // Nothing may be drawing, and then no frame would end.
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<BoardWallCubit, BoardWallState>(
        // Every step of the column is one it may read on from: a page that
        // arrived, a read of the wall that ended, a card that moved here.
        listenWhen: _stepped,
        listener: (context, _) => _askAfterFrame(),
        buildWhen: _stepped,
        builder: (context, wall) {
          final slice = BoardColumnSlice.of(wall, widget.name);
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
          return slice.loadingMore
              ? const LoadingMoreIndicator()
              : const SizedBox(height: LoadingMoreIndicator.height);
        },
      );

  bool _stepped(BoardWallState previous, BoardWallState next) =>
      BoardColumnSlice.of(previous, widget.name) !=
      BoardColumnSlice.of(next, widget.name);
}

/// Reads on under a grouped wall's lanes as they are scrolled: the next page
/// of each column among [names] that holds more and fewer than
/// [kBoardLaneMaxCards].
///
/// The lanes' columns read on by themselves as their pages arrive (see
/// [BoardLaneFooter]); this is what picks the reading up again where that
/// stopped. A column whose last page did not come reads again only on [retry],
/// which the lanes pass once someone scrolls them, so a failing page is not
/// asked for over and over while nobody moves.
void readOnUnderLanes(
  BoardWallCubit wall,
  Iterable<String> names, {
  required bool retry,
}) {
  for (final name in names) {
    final slice = BoardColumnSlice.of(wall.state, name);
    if (slice == null || !slice.fillsLanes(retry: retry)) continue;
    unawaited(wall.loadMore(name, size: kBoardLanePageSize));
  }
}
