import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../theme/glass_buttons.dart';

/// A primary action with a menu beside it, as one capsule.
///
/// The anatomy of `GlassButtonGroup` in liquid_glass_widgets: one shared
/// surface, the segments inside it, a hairline between them — not two buttons
/// pushed together, whose two rounded ends met in the middle as a pinch. The
/// surface is the honey capsule of [GlassButtons.filled] (lit from above, a rim
/// of light), not refractive glass: it sits on cards and in heads, and the
/// app's primary action is honey everywhere.
///
/// The left segment runs [onPressed]; the arrow hands its own context to
/// [onMenu], so the menu can hang from it.
class GlassSplitButton extends StatelessWidget {
  const GlassSplitButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.onMenu,
    required this.menuTooltip,
    this.icon,
    this.menuIcon = LucideIcons.chevronDown,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final void Function(BuildContext arrowContext)? onMenu;
  final String menuTooltip;
  final IconData menuIcon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null || onMenu != null;
    const capsule = StadiumBorder();
    ButtonStyle segment(OutlinedBorder shape, EdgeInsets padding) =>
        TextButton.styleFrom(
          foregroundColor: AppColors.navy,
          overlayColor: AppColors.navy,
          padding: padding,
          minimumSize: const Size(40, GlassButtons.minHeight),
          shape: shape,
          textStyle: const TextStyle(
            fontSize: AppType.label,
            fontWeight: FontWeight.w700,
          ),
        );
    const end = Radius.circular(GlassButtons.minHeight);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: capsule,
        color: enabled
            ? AppColors.accent
            : AppColors.accent.withValues(alpha: 0.24),
        shadows: enabled
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: DecoratedBox(
        // The rim and the light falling from above, over the whole capsule so
        // both segments share one highlight.
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.55),
              width: 0.8,
            ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: enabled ? 0.22 : 0),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, 0.6],
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: onPressed,
                style: segment(
                  const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(left: end),
                  ),
                  const EdgeInsets.fromLTRB(18, 10, 12, 10),
                ),
                icon: icon == null ? null : Icon(icon, size: 16),
                label: Text(label),
              ),
              // The hairline between the segments, inset so it does not cut
              // the rim.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  width: 1,
                  child: ColoredBox(
                    color: AppColors.navy.withValues(alpha: 0.22),
                  ),
                ),
              ),
              Builder(
                builder: (arrowContext) => TextButton(
                  onPressed: onMenu == null
                      ? null
                      : () => onMenu!(arrowContext),
                  style: segment(
                    const RoundedRectangleBorder(
                      borderRadius: BorderRadius.horizontal(right: end),
                    ),
                    const EdgeInsets.fromLTRB(8, 10, 12, 10),
                  ),
                  child: Tooltip(
                    message: menuTooltip,
                    child: Icon(menuIcon, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
