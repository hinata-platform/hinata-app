import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The hover wash every tappable tile in a glass dialog shows under a mouse:
/// the ink at a whisper, so it reads on light glass as well as on dark.
Color hoverWash() => AppColors.ink.withValues(alpha: 0.06);

/// Lays [base] under the hover wash while [hovered], and leaves it alone
/// otherwise.
Color withHoverWash(Color base, bool hovered) =>
    hovered ? Color.alphaBlend(hoverWash(), base) : base;

/// Tells [builder] whether a mouse rests on [child]'s area and shows the click
/// cursor there. For tiles that draw their own fill: they mix the wash in
/// with [withHoverWash].
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({super.key, required this.builder, this.enabled = true});

  final Widget Function(BuildContext context, bool hovered) builder;

  /// A disabled tile neither changes the cursor nor lights up.
  final bool enabled;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  void _set(bool hovered) {
    if (_hovered != hovered) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: widget.builder(context, widget.enabled && _hovered),
    );
  }
}
