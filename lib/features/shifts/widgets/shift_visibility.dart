import 'package:flutter/widgets.dart';

import '../../shell/page_chrome.dart';

/// Tells [onVisible] whether the view around it is the one on screen, each
/// time that changes, after the frame (a cubit may emit in answer).
class ShiftVisibilityRelay extends StatefulWidget {
  const ShiftVisibilityRelay({
    super.key,
    required this.onVisible,
    required this.child,
  });

  final void Function(bool visible) onVisible;
  final Widget child;

  @override
  State<ShiftVisibilityRelay> createState() => _ShiftVisibilityRelayState();
}

class _ShiftVisibilityRelayState extends State<ShiftVisibilityRelay> {
  bool? _told;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = PageChromeVisibility.of(context);
    if (visible == _told) return;
    _told = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _told == visible) widget.onVisible(visible);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
