import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_type.dart';

/// One quiet line in place of content: what happened, and at most one action
/// (HIN-26). Blocking and reporting fold with it (HIN-168, HIN-173), and the
/// moderation's placeholder takes the same shape, so all of them read alike.
class QuietContentLine extends StatelessWidget {
  const QuietContentLine({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;

  /// The one thing to do about it, such as showing it anyway; none when null.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final action = actionLabel;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 16, color: AppColors.inkSoft),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.label,
                fontStyle: FontStyle.italic,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
