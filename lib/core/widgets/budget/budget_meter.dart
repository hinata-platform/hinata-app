import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_type.dart';
import 'budget_style.dart';
import 'honey_glass.dart';

/// A budget or an estimate as a glass tube filling with honey: the large
/// form, for the places where somebody decides how much more to spend
/// (HIN-151, "Honigstand").
///
/// The tube is the budget. Fine marks stand at a quarter, half and three
/// quarters, and a notch at the project's warning share. From the limit on
/// the honey turns to ember, and whatever lies beyond it hangs off the end as
/// a small capsule of its own that names the overhang, so "125 h of 100 h"
/// reads as "full, and 25 h spilled" rather than as a bar that merely filled.
///
/// [pending] shows time that is about to be recorded, as translucent hatched
/// honey after what is already there: the entry in the form, before it is
/// saved.
///
/// [gauge] null is the loading state: the empty tube and a dash, the same
/// height as the finished meter so nothing jumps when the numbers arrive.
class BudgetMeter extends StatelessWidget {
  const BudgetMeter({
    super.key,
    required this.label,
    required this.gauge,
    this.format = budgetMinutes,
    this.pending = 0,
    this.showRemainder = true,
    this.footer,
  });

  final String label;
  final BudgetGauge? gauge;
  final BudgetAmountFormat format;
  final int pending;
  final bool showRemainder;

  /// An extra line under the remainder, e.g. a forecast (HIN-156).
  final Widget? footer;

  static const tubeHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final gauge = this.gauge;
    final level = gauge?.level ?? BudgetLevel.within;
    final sums = TextStyle(
      fontSize: AppType.label,
      height: 1.35,
      color: AppColors.inkSoft,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final meter = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppType.label,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              gauge == null ? '–' : BudgetStyle.percent(context, gauge),
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: AppType.heading,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: gauge == null ? AppColors.inkFaint : AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: tubeHeight,
                child: _AnimatedTube(
                  label: label,
                  gauge: gauge,
                  pending: pending,
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
            if (gauge != null && gauge.overBy > 0) ...[
              const SizedBox(width: 8),
              OverflowCapsule(text: '+${format(context, gauge.overBy)}'),
            ],
          ],
        ),
        if (gauge != null && showRemainder) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                BudgetStyle.usedOfLimit(context, gauge, format),
                style: sums,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (level != BudgetLevel.within) ...[
                    Icon(
                      BudgetStyle.icon(level),
                      size: 14,
                      color: BudgetStyle.ink(level),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    BudgetStyle.remainder(context, gauge, format),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      height: 1.35,
                      fontWeight: level == BudgetLevel.within
                          ? FontWeight.w500
                          : FontWeight.w700,
                      color: BudgetStyle.ink(level),
                    ),
                  ),
                ],
              ),
              if (pending > 0)
                Text(
                  context.t(
                    'budget.pending',
                    variables: {'amount': format(context, pending)},
                  ),
                  style: sums.copyWith(
                    fontSize: AppType.caption,
                    color: BudgetStyle.ink(level),
                  ),
                ),
            ],
          ),
        ],
        if (footer != null) ...[const SizedBox(height: 6), footer!],
      ],
    );
    return Semantics(
      container: true,
      label: gauge == null
          ? label
          : BudgetStyle.semantics(context, label, gauge, format),
      child: ExcludeSemantics(child: meter),
    );
  }
}

/// The tube, eased to a new level whenever its value changes, and drawn
/// still when the reader asks for less motion.
class _AnimatedTube extends StatelessWidget {
  const _AnimatedTube({
    required this.label,
    required this.gauge,
    required this.pending,
    required this.dark,
  });

  /// Whose tube this is, so it rises from empty only the first time.
  final String label;
  final BudgetGauge? gauge;
  final int pending;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final gauge = this.gauge;
    final target = gauge == null ? 0.0 : gauge.fraction.clamp(0.0, 1.0);
    final pendingTarget = gauge == null
        ? 0.0
        : ((gauge.used + pending) / gauge.limit).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeOutBack,
      tween: Tween(begin: BudgetFill.begin(label, gauge, target), end: target),
      // Honey fills from where reading starts: from the right in Arabic.
      builder: (context, value, _) => Transform.flip(
        flipX: Directionality.of(context) == TextDirection.rtl,
        child: CustomPaint(
          painter: HoneyTubePainter(
            fill: value,
            pendingTo: pendingTarget,
            level: gauge == null
                ? BudgetLevel.within
                : BudgetGauge(
                    used: gauge.used + pending,
                    limit: gauge.limit,
                    nearPercent: gauge.nearPercent,
                  ).level,
            nearAt:
                (gauge?.nearPercent ?? BudgetGauge.defaultNearPercent) / 100,
            dark: dark,
            showScale: gauge != null,
          ),
        ),
      ),
    );
  }
}

/// A horizontal glass tube with honey up to [fill] (0..1) and, beyond it,
/// pending honey up to [pendingTo].
class HoneyTubePainter extends CustomPainter {
  const HoneyTubePainter({
    required this.fill,
    required this.level,
    required this.dark,
    this.pendingTo = 0,
    this.nearAt = 0.8,
    this.showScale = false,
  });

  final double fill;
  final double pendingTo;
  final BudgetLevel level;
  final double nearAt;
  final bool dark;
  final bool showScale;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(size.height / 2)),
      );
    HoneyGlass.paintVessel(canvas, shape, bounds, dark);
    final inner = bounds.deflate(2.5);
    final innerShape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(inner.height / 2)),
      );
    final liquidLevel = fill >= 1 ? BudgetLevel.over : level;
    final filled = Rect.fromLTWH(
      inner.left,
      inner.top,
      inner.width * fill.clamp(0.0, 1.0),
      inner.height,
    );
    HoneyGlass.paintHoney(canvas, innerShape, filled, liquidLevel);
    if (pendingTo > fill) {
      HoneyGlass.paintPending(
        canvas,
        innerShape,
        Rect.fromLTRB(
          filled.right,
          inner.top,
          inner.left + inner.width * pendingTo,
          inner.bottom,
        ),
        level,
        dark: dark,
      );
    }
    if (showScale) {
      final tick = Paint()
        ..strokeWidth = 1
        ..color = dark
            ? Colors.white.withValues(alpha: 0x59 / 255)
            : AppColors.glassShade.withValues(alpha: 0x33 / 255);
      for (final at in const [0.25, 0.5, 0.75]) {
        if ((at - nearAt).abs() < 0.04) continue;
        final x = inner.left + inner.width * at;
        canvas.drawLine(
          Offset(x, inner.bottom - inner.height * 0.32),
          Offset(x, inner.bottom - 1),
          tick,
        );
      }
      // The warning share: a notch from top to bottom, in the warning amber.
      if (nearAt > 0 && nearAt < 1) {
        final x = inner.left + inner.width * nearAt;
        canvas.drawLine(
          Offset(x, inner.top + 1),
          Offset(x, inner.bottom - 1),
          Paint()
            ..strokeWidth = 1.6
            ..color = AppColors.warningBar.withValues(alpha: 0.9),
        );
      }
    }
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
  }

  @override
  bool shouldRepaint(HoneyTubePainter old) =>
      old.fill != fill ||
      old.pendingTo != pendingTo ||
      old.level != level ||
      old.nearAt != nearAt ||
      old.dark != dark ||
      old.showScale != showScale;
}

/// The honey that went over: a small ember capsule hanging off a full
/// vessel, naming the overhang ("+25 h").
class OverflowCapsule extends StatelessWidget {
  const OverflowCapsule({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _CapsulePainter(dark: dark),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: AppType.caption,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: HoneyGlass.onLiquid,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _CapsulePainter extends CustomPainter {
  const _CapsulePainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(size.height / 2)),
      );
    HoneyGlass.paintVessel(canvas, shape, bounds, dark);
    HoneyGlass.paintHoney(
      canvas,
      shape,
      bounds,
      BudgetLevel.over,
      bubbles: false,
    );
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
  }

  @override
  bool shouldRepaint(_CapsulePainter old) => old.dark != dark;
}
