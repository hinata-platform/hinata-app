import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_type.dart';

/// A count in a small honey pill: the filters set on a board, the cases
/// waiting on the moderation page (HIN-174).
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.semanticLabel});

  final int count;

  /// What the number means, for a screen reader; the number alone otherwise.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: semanticLabel != null,
    child: Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: AppType.caption,
          fontWeight: FontWeight.w700,
          color: AppColors.onAccent,
        ),
      ),
    ),
  );
}
