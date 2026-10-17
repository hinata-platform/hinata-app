import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// The dashboard's frosted card, for pages beside it (HIN-157): a white wash
/// over the app's ambient background, a white rim and a soft navy shadow.
///
/// No backdrop blur: the ambient background is blurred already, and a blur per
/// card is a gaussian pass per frame a scrolling page cannot cache (see the
/// dashboard's own card). A [RepaintBoundary] keeps a card from repainting
/// while the page scrolls.
class FrostedCard extends StatelessWidget {
  const FrostedCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(21),
    this.gradient,
  });

  final Widget child;

  /// A question or a name over the content, in the card's title style.
  final String? title;

  /// Beside the title: a figure, a range, an action.
  final Widget? trailing;
  final EdgeInsets padding;

  /// Replaces the white wash, for a navy hero card.
  final Gradient? gradient;

  static const double radius = 26;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onGradient = gradient != null;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D2B55).withValues(alpha: dark ? .48 : .26),
              blurRadius: 40,
              spreadRadius: -24,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: gradient == null
                ? (dark
                      ? Colors.white.withValues(alpha: .09)
                      : Colors.white.withValues(alpha: .55))
                : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: onGradient || dark
                  ? Colors.white.withValues(alpha: .13)
                  : Colors.white.withValues(alpha: .62),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null || trailing != null) ...[
                Row(
                  children: [
                    if (title != null)
                      Expanded(
                        child: Text(
                          title!,
                          style: TextStyle(
                            fontSize: AppType.title,
                            fontWeight: FontWeight.w700,
                            color: onGradient
                                ? const Color(0xFFF3F1FA)
                                : AppColors.ink,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 16),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}
