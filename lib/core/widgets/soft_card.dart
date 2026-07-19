import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Warm-surface card used for every dashboard/list block in the design.
/// Crisp 14 px radius with a hairline border; zero elevation.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius,
    this.border,
    this.onTap,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.surface;
    final r = borderRadius ?? BorderRadius.circular(AppTheme.radiusCard);
    // The Material clips the ink ripple (clipBehavior) and the decoration rounds
    // the surface, so no extra ClipRRect layer is needed — one fewer clip per
    // SoftCard, and SoftCard backs nearly every list row in the app.
    return Material(
      color: bg,
      borderRadius: r,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: r,
          border: border ?? Border.all(color: AppColors.hairline),
        ),
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                borderRadius: r,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}

/// Section title row with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentStrong,
            ),
            child: Text(
              actionLabel!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
