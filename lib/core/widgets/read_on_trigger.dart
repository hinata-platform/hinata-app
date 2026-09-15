import 'package:flutter/material.dart';

/// The small spinner at the end of a list while its next page is on its way.
class LoadingMoreIndicator extends StatelessWidget {
  const LoadingMoreIndicator({super.key});

  /// The room it takes. A list that may read on keeps it free in between, so
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

/// Stands after the loaded rows of a list that holds more, and reads the next
/// page from there: a board's cards, a sprint's rows, a person's absences.
///
/// A lazy list builds it only once the end of its rows is within reach of the
/// screen, so being built is what tells it to read on. It asks after the frame
/// it came in and after every page that arrived while it stayed, never from
/// its build. A page that did not come is asked for again only once someone
/// scrolls the rows, the way the issue list reads on, so a read that fails is
/// never repeated on its own. While a page is on its way it shows
/// [LoadingMoreIndicator], whose room it keeps in between.
class ReadOnTrigger extends StatefulWidget {
  const ReadOnTrigger({
    super.key,
    required this.count,
    required this.loading,
    required this.onReadOn,
  });

  /// How far ahead of the screen a list that reads on builds its rows, and so
  /// how close to their end the next page is asked for.
  static const double reach = 600;

  /// The rows loaded so far. Another count means a page arrived.
  final int count;

  /// Whether the next page is on its way.
  final bool loading;

  /// Reads the next page.
  final VoidCallback onReadOn;

  @override
  State<ReadOnTrigger> createState() => _ReadOnTriggerState();
}

class _ReadOnTriggerState extends State<ReadOnTrigger> {
  /// The scroll of the rows it stands after.
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
  void didUpdateWidget(ReadOnTrigger old) {
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
      ? const LoadingMoreIndicator()
      : const SizedBox(height: LoadingMoreIndicator.height);
}
