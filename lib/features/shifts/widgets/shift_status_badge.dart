import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/shift_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../shift_texts.dart';

/// The status of the caller's place as a static badge (the `StateBadge`
/// pattern): a glyph and a word, never a control of its own. The row it sits
/// in is what opens the sheet.
class ShiftStatusBadge extends StatelessWidget {
  const ShiftStatusBadge({super.key, required this.status});

  final ShiftAssignmentStatus status;

  @override
  Widget build(BuildContext context) {
    final pending = status == ShiftAssignmentStatus.assigned;
    final color = pending ? AppColors.warningInk : AppColors.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.soft(
          pending ? AppColors.warningBar : AppColors.accent,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pending ? LucideIcons.hourglass : LucideIcons.check,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              statusLabel(context, status),
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
