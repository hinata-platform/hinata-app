import 'package:flutter/material.dart';

import '../../features/search/search_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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
    required this.onTap,
    this.icon,
    this.iconOnly = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
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
