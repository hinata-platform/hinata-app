import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../models/moderation_models.dart' show ContentRefusal;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_type.dart';

export '../models/moderation_models.dart' show ContentRefusal;

/// The refusal where the person was writing (HIN-176): what was refused, that
/// the draft stays where it is, and the way to the house rules.
class ContentRefusedNotice extends StatelessWidget {
  const ContentRefusedNotice({
    super.key,
    required this.refusal,
    this.onReadRules,
  });

  final ContentRefusal refusal;

  /// Opens the house rules; the link is left out without it.
  final VoidCallback? onReadRules;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.accentSoft.withValues(alpha: dark ? .35 : .6),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl + 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.shieldAlert, size: 18, color: AppColors.accentInk),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('moderation.refused.title'),
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t(
                      refusal.terms.isEmpty
                          ? 'moderation.refused.bodyPlain'
                          : 'moderation.refused.body',
                      variables: {'terms': refusal.terms.join(', ')},
                    ),
                    style: TextStyle(
                      fontSize: AppType.label,
                      height: 1.4,
                      color: AppColors.ink,
                    ),
                  ),
                  if (onReadRules != null)
                    TextButton(
                      onPressed: onReadRules,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 40),
                      ),
                      child: Text(context.t('moderation.refused.readRules')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
