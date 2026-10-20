import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveAvatarStack;

/// The people waiting for [shift], for a planner (HIN-162): muted chips in
/// their order, behind the people on it. With a free place a chip offers
/// "Jetzt zuteilen" ([onAssign]); on a full shift it only says who waits.
///
/// [shift.waitingIds] is filled for planners only, so for anybody else this
/// draws nothing.
class WaitlistChips extends StatelessWidget {
  const WaitlistChips({
    super.key,
    required this.shift,
    required this.users,
    this.onAssign,
  });

  final Shift shift;
  final Map<String, ShiftUser> users;

  /// Puts the waiting person on the shift; null where the caller does not plan.
  final void Function(String userId, String name)? onAssign;

  @override
  Widget build(BuildContext context) {
    final ids = shift.waitingIds;
    if (ids.isEmpty) return const SizedBox.shrink();
    final free = !shift.cancelled && shift.coverage.state != CoverageState.full;
    return Wrap(
      spacing: 6,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < ids.length; i++)
          _WaitingChip(
            name: users[ids[i]]?.name ?? '',
            avatarUrl: users[ids[i]]?.avatarUrl,
            position: i + 1,
            onTap: free && onAssign != null
                ? () => onAssign!(ids[i], users[ids[i]]?.name ?? '')
                : null,
          ),
      ],
    );
  }
}

class _WaitingChip extends StatelessWidget {
  const _WaitingChip({
    required this.name,
    required this.avatarUrl,
    required this.position,
    this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final int position;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = context.t(
      'shifts.waitlist.chip',
      variables: {'name': name, 'pos': position},
    );
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
      decoration: BoxDecoration(
        // The people on the shift sit on the same recess in ink; waiting
        // ones are told apart by the softer ink, the glyph and the rank.
        color: AppColors.recess,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: .7,
            child: HiveAvatarStack(
              names: [name],
              imageUrls: [avatarUrl],
              size: 22,
              max: 1,
            ),
          ),
          const SizedBox(width: 6),
          Icon(LucideIcons.hourglass, size: 13, color: AppColors.inkSoft),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$position. $name',
              style: TextStyle(
                fontSize: AppType.label,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
    // The pill stays small; the target around it is the full 48 points. The
    // node carries the tap itself, since its children are left out.
    return Semantics(
      button: onTap != null,
      label: onTap == null
          ? label
          : '$label. ${context.t('shifts.waitlist.assignNow')}',
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: onTap == null ? label : context.t('shifts.waitlist.assignNow'),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(widthFactor: 1, child: pill),
          ),
        ),
      ),
    );
  }
}
