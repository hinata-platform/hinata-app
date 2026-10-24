import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';

/// The words of [category] in the reason list, as `moderation.category.*`.
String reportCategoryTitle(BuildContext context, ReportCategory category) =>
    context.t('moderation.category.${category.name}');

String reportCategoryHint(BuildContext context, ReportCategory category) =>
    context.t('moderation.category.${category.name}Hint');

/// The first step: why. Threats and the safety of children are looked at
/// first, and the row says so with a glyph.
class ReportReasons extends StatelessWidget {
  const ReportReasons({super.key, required this.onChoose, this.focused});

  final ValueChanged<ReportCategory> onChoose;

  /// The reason that takes the focus, the one chosen before going back.
  final ReportCategory? focused;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final category in ReportCategory.values)
        ReportReasonRow(
          title: reportCategoryTitle(context, category),
          hint: reportCategoryHint(context, category),
          urgent: category.urgent,
          autofocus: category == focused,
          onTap: () => onChoose(category),
        ),
    ],
  );
}

class ReportReasonRow extends StatelessWidget {
  const ReportReasonRow({
    super.key,
    required this.title,
    required this.hint,
    required this.onTap,
    this.urgent = false,
    this.chosen = false,
    this.autofocus = false,
  });

  final String title;
  final String hint;
  final VoidCallback onTap;
  final bool urgent;
  final bool chosen;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    child: InkWell(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: chosen ? AppColors.accentSoft : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (urgent)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Icon(
                  LucideIcons.siren,
                  size: 16,
                  color: AppColors.warningInk,
                ),
              ),
            Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkFaint),
          ],
        ),
      ),
    ),
  );
}
