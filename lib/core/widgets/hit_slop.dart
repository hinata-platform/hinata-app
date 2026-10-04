import 'package:flutter/widgets.dart';

/// Grows a small control's touch target without growing what is drawn.
///
/// The ring of [padding] around [child] answers [onTap] as well. A tap on the
/// child itself is won by the child's own InkWell — the innermost recognizer
/// wins the gesture arena — so it fires once and still shows its ripple. The
/// ring adds no semantics node of its own: the child's InkWell already carries
/// the tap action for assistive technology.
class HitSlop extends StatelessWidget {
  const HitSlop({
    super.key,
    required this.onTap,
    required this.padding,
    required this.child,
  });

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    );
  }
}
