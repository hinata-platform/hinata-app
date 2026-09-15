import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// The small spinner at the end of cards while their next page is on its way.
class BoardLoadingMore extends StatelessWidget {
  const BoardLoadingMore({super.key});

  /// The room it takes. Cards that may read on keep it free in between, so
  /// nothing moves when a page starts or stops being read.
  static const double height = 42;

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: height,
    child: Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

/// Stands after the loaded cards of a lazily built list that holds more, and
/// reads the next page from there.
///
/// A lazy list builds it only once the end of its cards is within reach of the
/// screen, so being built is what tells it to read on. It asks after the frame
/// it came in and after every page that arrived while it stayed, never from
/// its build. A page that did not come is asked for again once someone scrolls
/// the cards, the way the issue list reads on. While a page is on its way it
/// shows [BoardLoadingMore], whose room it keeps in between.
class BoardReadOn extends StatefulWidget {
  const BoardReadOn({
    super.key,
    required this.count,
    required this.loading,
    required this.onReadOn,
  });

  /// How far ahead of the screen a list that reads on builds its cards, and so
  /// how close to their end the next page is asked for.
  static const double reach = 600;

  /// The cards loaded so far. Another count means a page arrived.
  final int count;

  /// Whether the next page is on its way.
  final bool loading;

  /// Reads the next page.
  final VoidCallback onReadOn;

  @override
  State<BoardReadOn> createState() => _BoardReadOnState();
}

class _BoardReadOnState extends State<BoardReadOn> {
  /// The scroll of the cards it stands after.
  ScrollPosition? _position;

  /// Whether an ask waits for the frame to end, so that coming in and the list
  /// settling within the same frame ask once.
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _askAfterFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position == _position) return;
    _position?.isScrollingNotifier.removeListener(_scrolled);
    _position = position?..isScrollingNotifier.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(BoardReadOn old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _askAfterFrame();
  }

  @override
  void dispose() {
    _position?.isScrollingNotifier.removeListener(_scrolled);
    super.dispose();
  }

  void _scrolled() {
    if (_position?.isScrollingNotifier.value ?? false) _askAfterFrame();
  }

  void _askAfterFrame() {
    if (_asking) return;
    _asking = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _asking = false;
        _ask();
      })
      ..ensureVisualUpdate();
  }

  void _ask() {
    if (mounted && !widget.loading) widget.onReadOn();
  }

  @override
  Widget build(BuildContext context) => widget.loading
      ? const BoardLoadingMore()
      : const SizedBox(height: BoardLoadingMore.height);
}

/// A column's cards, read on as they are scrolled.
///
/// While the column may read on, a [BoardReadOn] stands after its cards, and
/// the list builds [BoardReadOn.reach] ahead of what is on screen: the next
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
          : const ScrollCacheExtent.pixels(BoardReadOn.reach),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: count + (readOn == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) => index < count
          ? itemBuilder(context, index)
          : BoardReadOn(count: count, loading: loadingMore, onReadOn: readOn!),
    );
  }
}
