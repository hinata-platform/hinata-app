import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hex_mark.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveAvatarStack;
import '../shift_texts.dart';
import 'coverage_hex.dart';
import 'shift_actions.dart';

/// "Nächste Schicht" on navy, like the sprint card on the dashboard (HIN-44).
///
/// The day and the time large in Sora, then when, until, what and where, the
/// people on it, and the one action the state asks for. Breaks into lines at
/// any text size instead of clipping.
class NextShiftHero extends StatelessWidget {
  const NextShiftHero({
    super.key,
    required this.next,
    required this.now,
    required this.onAction,
    this.detail,
    this.selfId,
    this.offline = false,
    this.onOpen,
    this.large = false,
  });

  final MyShift next;
  final DateTime now;

  /// The shift's detail, for the names. Without it the others are counted.
  final ShiftDetail? detail;

  /// The reader, left out of "mit …".
  final String? selfId;

  /// Drawn from the snapshot: no actions, people counted, never named.
  final bool offline;
  final ValueChanged<ShiftAction> onAction;
  final VoidCallback? onOpen;

  /// The wide window's size of the date.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final shift = next.shift;
    final others = _others();
    final otherCount = (shift.assignedCount - 1).clamp(0, 999);
    final peopleLine = others.isNotEmpty
        ? context.t(
            'shifts.next.with',
            variables: {'names': _join(context, others.map((u) => u.name))},
          )
        : otherCount > 0
        ? context.t('shifts.next.withOthers', count: otherCount)
        : context.t('shifts.next.alone');
    final zone = zoneHint(context, shift, next.event.timezone);
    const soft = TextStyle(
      fontSize: AppType.body,
      color: AppColors.inkSoftOnNavy,
    );
    // A place that came off the waiting list: confirm by the deadline, or
    // give it up again (HIN-162).
    final offer = shiftOfferFor(
      shift,
      status: next.status,
      promoted: next.promoted,
    );
    final confirmBy = next.promoted ? next.confirmByLocal : null;
    final radius = BorderRadius.circular(AppTheme.radiusCard + 6);
    return Semantics(
      container: true,
      label: context.t('shifts.next.badge'),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryDeep.withValues(alpha: 0xE0 / 255),
                AppColors.primary.withValues(alpha: 0xD1 / 255),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
            borderRadius: radius,
          ),
          child: InkWell(
            onTap: onOpen,
            child: Stack(
              children: [
                Positioned(
                  right: -200,
                  bottom: -220,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: .07,
                        child: HexMark(size: 420, color: AppColors.accent),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(large ? 24 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                context.t('shifts.next.badge').toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontMono,
                                  fontSize: AppType.caption,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: AppColors.honeyOnNavy,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          CoverageHex(
                            coverage: shift.coverage,
                            size: 36,
                            showFigure: false,
                            animate: true,
                            onNavy: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${dayLabel(context, shift.startsLocal)}, '
                        '${clockLabel(context, shift.startsLocal)}',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBrand,
                          fontSize: large ? AppType.hero : AppType.display,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1.1,
                          color: AppColors.inkOnNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          relativeStart(context, shift.startsAt, now),
                          untilLabel(context, shift.endsLocal),
                          shift.title,
                          next.event.title,
                        ].where((p) => p.isNotEmpty).join(' · '),
                        style: soft,
                      ),
                      if (next.event.location != null) ...[
                        const SizedBox(height: 10),
                        _Line(
                          icon: LucideIcons.mapPin,
                          text: next.event.location!,
                        ),
                      ],
                      if (zone != null) ...[
                        const SizedBox(height: 6),
                        _Line(icon: LucideIcons.globe, text: zone),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              LucideIcons.users,
                              size: 15,
                              color: AppColors.inkSoftOnNavy,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!offline && detail != null) ...[
                            HiveAvatarStack(
                              names: [
                                for (final id in detail!.shift.assigneeIds)
                                  detail!.users[id]?.name ?? '',
                              ],
                              imageUrls: [
                                for (final id in detail!.shift.assigneeIds)
                                  detail!.users[id]?.avatarUrl,
                              ],
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              peopleLine,
                              style: const TextStyle(
                                fontSize: AppType.label,
                                color: AppColors.inkSoftOnNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (confirmBy != null) ...[
                        const SizedBox(height: 12),
                        _Line(
                          icon: LucideIcons.clockAlert,
                          text: confirmByLabel(context, confirmBy, now: now),
                          color: AppColors.honeyOnNavy,
                        ),
                      ],
                      if (!offline && !offer.isEmpty) ...[
                        const SizedBox(height: 18),
                        ShiftOfferView(
                          offer: offer,
                          shift: shift,
                          onAction: onAction,
                          onNavy: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The people on it besides the reader, named only from the detail answer
  /// (which the server fills for project members only).
  List<ShiftUser> _others() {
    final d = detail;
    if (offline || d == null) return const [];
    return [
      for (final id in d.shift.assigneeIds)
        if (id != selfId && d.users[id] != null && d.users[id]!.name.isNotEmpty)
          d.users[id]!,
    ];
  }

  static String _join(BuildContext context, Iterable<String> names) {
    final list = names.toList();
    if (list.length <= 1) return list.join();
    return context.t(
      'shifts.next.and',
      variables: {
        'first': list.sublist(0, list.length - 1).join(', '),
        'last': list.last,
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.text,
    this.color = AppColors.inkSoftOnNavy,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: ExcludeSemantics(child: Icon(icon, size: 15, color: color)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: AppType.label, color: color),
        ),
      ),
    ],
  );
}
