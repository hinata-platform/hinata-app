import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;

/// The way to a column's cards that are not loaded yet: how many are left,
/// behind a quiet button, or a small spinner while they are being read.
class BoardLoadMore extends StatelessWidget {
  const BoardLoadMore({
    super.key,
    this.remaining = 0,
    this.loading = false,
    this.onPressed,
  });

  final int remaining;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: GhostButton(
          label: context.t(
            'board.loadMore',
            variables: {'count': '$remaining'},
          ),
          icon: LucideIcons.chevronDown,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// A column's cards, read on as they are scrolled.
///
/// The next page is asked for once the last loaded card has been built, which
/// the list does a little ahead of what is on screen: while the cards are
/// scrolled towards their end, and right after layout when they do not fill
/// the column, since those can never be scrolled to their end. What was built
/// is known for certain, where the length of a lazily laid out list is only an
/// estimate, and one that falls short right after a page arrived. The list
/// checks once it was laid out anew or scrolled, and once after a change that
/// lets it read on again, never from its build. While a page is on its way a
/// spinner stands at the end. A page that did not come ([failed]) is not asked
/// for again on its own; the list offers a button for it instead. In a lane
/// the list neither scrolls nor reads on; the board offers the rest under its
/// lanes.
class BoardCardList extends StatefulWidget {
  const BoardCardList({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.remaining = 0,
    this.laneMode = false,
    this.loadingMore = false,
    this.failed = false,
    this.onLoadMore,
  });

  final int count;
  final IndexedWidgetBuilder itemBuilder;

  /// The column's cards beyond the loaded ones.
  final int remaining;
  final bool laneMode;
  final bool loadingMore;

  /// Whether the last page asked for did not come.
  final bool failed;

  /// Reads the next page. Null while the column cannot read on: it holds no
  /// more, or the whole wall is being read again.
  final VoidCallback? onLoadMore;

  @override
  State<BoardCardList> createState() => _BoardCardListState();
}

class _BoardCardListState extends State<BoardCardList> {
  /// How far beyond what is on screen cards are built, and so how close to the
  /// end of the loaded cards the next page is asked for.
  static const double _reach = 600;

  /// The highest index of a card built since the list last got other cards.
  int _lastBuilt = -1;

  /// Whether the list asked for more since it was last handed other cards or
  /// another reading state, so one layout or one gesture never asks twice.
  bool _asked = false;

  @override
  void didUpdateWidget(BoardCardList old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _lastBuilt = -1;
    // A list that may read on again without being laid out anew, its failed
    // page taken back or its total grown, checks once the frame is done.
    if (old.count != widget.count ||
        old.loadingMore != widget.loadingMore ||
        old.failed != widget.failed ||
        (old.onLoadMore == null) != (widget.onLoadMore == null)) {
      _asked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askIfAtEnd());
    }
  }

  bool get _mayAsk =>
      !widget.laneMode &&
      !widget.loadingMore &&
      !widget.failed &&
      widget.onLoadMore != null;

  void _askIfAtEnd() {
    if (!mounted || !_mayAsk || _asked || _lastBuilt < widget.count - 1) {
      return;
    }
    _asked = true;
    widget.onLoadMore!();
  }

  /// Laid out anew: on the first frame, once scrolled, after a page arrived,
  /// or once the column's room changed.
  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _askIfAtEnd();
    return false;
  }

  Widget _card(BuildContext context, int index) {
    if (index > _lastBuilt) _lastBuilt = index;
    return widget.itemBuilder(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final retry =
        widget.failed && !widget.laneMode && widget.onLoadMore != null;
    final footer = widget.loadingMore || retry;
    final list = ListView.separated(
      shrinkWrap: true,
      physics: widget.laneMode ? const NeverScrollableScrollPhysics() : null,
      scrollCacheExtent: widget.laneMode
          ? null
          : const ScrollCacheExtent.pixels(_reach),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: widget.count + (footer ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) => index < widget.count
          ? _card(context, index)
          : widget.loadingMore
          ? const BoardLoadMore(loading: true)
          : BoardLoadMore(
              remaining: widget.remaining,
              onPressed: widget.onLoadMore,
            ),
    );
    if (widget.laneMode) return list;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: list,
    );
  }
}
