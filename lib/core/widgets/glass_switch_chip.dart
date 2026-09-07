import 'package:flutter/material.dart';

import '../../features/search/search_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

/// One segment of a switcher that rides on glass.
///
/// The active segment is a translucent amber wash rather than an opaque fill:
/// an opaque chip on a lens reads as a sticker stuck to it instead of part of
/// it. Lifted out of the Gantt screen when the time module grew a switcher of
/// its own — two copies of a chip is how two switchers start looking like two
/// different controls.
class GlassSwitchChip extends StatelessWidget {
  const GlassSwitchChip({
    super.key,
    required this.label,
    required this.active,
    this.onTap,
    this.icon,
    this.iconOnly = false,
  });

  final String label;
  final bool active;

  /// Null makes the chip inert — what the segment you are already on wants: it
  /// stops rippling, stops taking focus, and stops telling a screen reader that
  /// it leads somewhere.
  final VoidCallback? onTap;
  final IconData? icon;

  /// Drops the label and keeps it as the tooltip — the compact layout, where a
  /// switcher with words would run past the screen.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    final fg = active
        ? (dark ? AppColors.accent : AppColors.accentStrong)
        : tokens.inkSoft;
    final compact = iconOnly && icon != null;
    final chip = Material(
      color: active
          ? AppColors.accent.withValues(alpha: dark ? 0.30 : 0.22)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 12,
            vertical: 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: compact ? 18 : 15, color: fg),
                if (!compact) const SizedBox(width: 5),
              ],
              if (!compact)
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: label, child: chip) : chip;
  }
}

/// The glass pill a row of [GlassSwitchChip]s rides in.
///
/// Lifted for the same reason the chip was: three switchers had grown the same
/// wrapper — the Gantt's zoom, the time module's view switcher, and the
/// calendar's day/week control, the last two side by side in one row — and three
/// copies of a container is how one control starts looking like three.
///
/// It bounds its own width because its callers do not: `PageHead.actions` and a
/// docked toolbar row both hand a widget whatever it asks for, and a switcher
/// with long words in it asked for more than the page had. Past the ceiling the
/// chips scroll inside the pill rather than pushing the title off the head.
class GlassSwitchBar extends StatelessWidget {
  const GlassSwitchBar({
    super.key,
    required this.chips,
    required this.maxWidth,
    this.compact = false,
  });

  final List<Widget> chips;
  final double maxWidth;

  /// The icon-only shape, which is a little taller so the glyphs are not
  /// cramped. Pass the same value the chips are given.
  final bool compact;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: GlassFloatingSurface(
      radius: (compact ? 44 : 42) / 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: chips),
        ),
      ),
    ),
  );
}
