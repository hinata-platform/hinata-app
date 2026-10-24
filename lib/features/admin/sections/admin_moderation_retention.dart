import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_switch_chip.dart';
import '../admin_form_helpers.dart';

/// How long the moderation keeps what it decided (HIN-174): six or twelve
/// months, after which done cases, their reports and the quarantine go,
/// unless law enforcement was told. Written into the settings draft the shell
/// saves, under `moderation.retentionMonths`.
class RetentionCard extends StatefulWidget {
  const RetentionCard({super.key, required this.moderation});

  final Map<String, dynamic> moderation;

  /// The choices the server takes.
  static const months = [6, 12];

  @override
  State<RetentionCard> createState() => _RetentionCardState();
}

class _RetentionCardState extends State<RetentionCard> {
  /// Read without writing: a draft nobody touched stays as the server sent
  /// it, and none there means six.
  int get _months =>
      (widget.moderation['retentionMonths'] as num?)?.toInt() ??
      RetentionCard.months.first;

  void _choose(int months) =>
      setState(() => widget.moderation['retentionMonths'] = months);

  @override
  Widget build(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.archive,
    title: context.t('admin.moderation.retentionTitle'),
    subtitle: context.t('admin.moderation.retentionHint'),
    children: [
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              context.t('admin.moderation.retentionLabel'),
              style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
            ),
            // As wide as its two choices, never a track across the card.
            GlassSwitchBar(
              inline: true,
              maxWidth: constraints.maxWidth,
              chips: [
                for (final months in RetentionCard.months)
                  GlassSwitchChip(
                    label: context.t(
                      'admin.moderation.retentionMonths',
                      count: months,
                    ),
                    active: months == _months,
                    onTap: () => _choose(months),
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
