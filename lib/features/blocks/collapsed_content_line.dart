import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_type.dart';
import 'hidden_content_cubit.dart';

/// One quiet line in place of content that is folded away: what happened, and
/// at most one action (HIN-26). Blocking folds with it (HIN-168), and so will
/// reporting (HIN-173), so both read the same.
class CollapsedContentLine extends StatelessWidget {
  const CollapsedContentLine({
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
          Icon(icon, size: 16, color: AppColors.inkSoft),
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

/// Shows [child], or the folded line when the reader blocks its author and
/// has not opened it in this session (HIN-168).
///
/// Asks [HiddenContentCubit] when one is above it and shows [child] when none
/// is, so a surface built without the app around it (a test, a preview)
/// renders as it always did.
class HiddenContentFold extends StatelessWidget {
  const HiddenContentFold({
    super.key,
    required this.authorId,
    required this.contentId,
    required this.authorName,
    required this.child,
  });

  final String authorId;
  final String contentId;
  final String authorName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final folded = context.select<HiddenContentCubit?, bool>(
      (hidden) =>
          hidden?.state.folds(authorId: authorId, contentId: contentId) ??
          false,
    );
    if (!folded) return child;
    return CollapsedContentLine(
      icon: LucideIcons.chevronsDownUp,
      text: context.t('blocks.folded', variables: {'name': authorName}),
      actionLabel: context.t('blocks.show'),
      onAction: () => context.read<HiddenContentCubit>().reveal(contentId),
    );
  }
}
