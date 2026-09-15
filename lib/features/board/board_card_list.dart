import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../core/widgets/read_on_trigger.dart';

/// A column's cards, read on as they are scrolled.
///
/// While the column may read on, a [ReadOnTrigger] stands after its cards, and
/// the list builds [ReadOnTrigger.reach] ahead of what is on screen: the next
/// page is asked for once the cards are scrolled close to their end, and right
/// after layout when they do not fill the column. In a lane the list neither
/// scrolls nor reads on; the board reads on under its lanes.
class BoardCardList extends StatelessWidget {
  const BoardCardList({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.laneMode = false,
    this.loadingMore = false,
    this.onLoadMore,
  });

  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final bool laneMode;
  final bool loadingMore;

  /// Reads the next page. Null while the column cannot read on: it holds no
  /// more, or the whole wall is being read again.
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final readOn = laneMode ? null : onLoadMore;
    return ListView.separated(
      shrinkWrap: true,
      physics: laneMode ? const NeverScrollableScrollPhysics() : null,
      scrollCacheExtent: laneMode
          ? null
          : const ScrollCacheExtent.pixels(ReadOnTrigger.reach),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: count + (readOn == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) => index < count
          ? itemBuilder(context, index)
          : ReadOnTrigger(
              count: count,
              loading: loadingMore,
              onReadOn: readOn!,
            ),
    );
  }
}
