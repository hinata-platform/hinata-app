import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../models/time_usage_models.dart' show BudgetLevel;
import 'honey_glass.dart';

/// One value of a distribution: what it is called, how much, in which colour,
/// and, for a share rather than a distribution, its own limit.
typedef LiquidItem = ({String label, int value, Color color, int? limit});

/// How full a vessel stands: against its own limit when it has one, else
/// against the largest value.
double _fillOf(LiquidItem item, int top) {
  final limit = item.limit ?? top;
  return limit <= 0 ? 0 : (item.value / limit).clamp(0.0, 1.0);
}

/// The figure of an item: the value, or "value/limit" for a share, and the
/// unit after it when there is one.
String _figureOf(
  LiquidItem item,
  String Function(int value)? format,
  String? unit,
) {
  String shown(int value) => format?.call(value) ?? '$value';
  final figure = item.limit == null
      ? shown(item.value)
      : '${shown(item.value)}/${shown(item.limit!)}';
  return unit == null ? figure : '$figure $unit';
}

/// A distribution as glass capsules standing side by side, each filled from
/// the bottom with its own colour, the figure over it and the name under it
/// (HIN-157). Heights follow the largest value, so the fullest capsule is
/// full, or, where an item carries its own limit, its share of that. Made
/// for a handful of values, the states of a workflow, say.
class LiquidColumns extends StatelessWidget {
  const LiquidColumns({
    super.key,
    required this.items,
    this.format,
    this.height = 132,
  });

  final List<LiquidItem> items;
  final String Function(int value)? format;
  final double height;

  String _figure(LiquidItem item) => _figureOf(item, format, null);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final top = items.map((item) => item.value).reduce(math.max);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth / items.length).clamp(44.0, 84.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Spread over the card when they fit, scrolled when they do not.
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      label: '${item.label}: ${_figure(item)}',
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          Text(
                            _figure(item),
                            style: TextStyle(
                              fontSize: AppType.label,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: width * 0.62,
                            height: height,
                            child: TweenAnimationBuilder<double>(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 800),
                              curve: Curves.easeOutBack,
                              tween: Tween(begin: 0, end: _fillOf(item, top)),
                              builder: (context, fill, _) => CustomPaint(
                                painter: _ColumnPainter(
                                  fill: fill,
                                  colors: HoneyGlass.tinted(item.color),
                                  dark: dark,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              height: 1.3,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColumnPainter extends CustomPainter {
  const _ColumnPainter({
    required this.fill,
    required this.colors,
    required this.dark,
  });

  final double fill;
  final List<Color> colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final radius = Radius.circular(math.min(size.width, 22) / 2);
    final shape = Path()..addRRect(RRect.fromRectAndRadius(bounds, radius));
    HoneyGlass.paintVessel(canvas, shape, bounds, dark);
    final inner = bounds.deflate(3);
    final innerShape = Path()
      ..addRRect(RRect.fromRectAndRadius(inner, Radius.circular(radius.x - 3)));
    final top = inner.bottom - inner.height * fill.clamp(0.0, 1.0);
    HoneyGlass.paintHoney(
      canvas,
      innerShape,
      Rect.fromLTRB(inner.left, top, inner.right, inner.bottom),
      BudgetLevel.within,
      surface: HoneySurface.wave,
      colorsOverride: colors,
    );
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.fill != fill || old.colors != colors || old.dark != dark;
}

/// A distribution as rows: the name, a glass tube with its colour up to the
/// share of the largest, or of its own limit where it carries one, the figure
/// (HIN-157). For many values or long names, people or activities.
class LiquidRows extends StatelessWidget {
  const LiquidRows({super.key, required this.items, this.format, this.unit});

  final List<LiquidItem> items;
  final String Function(int value)? format;

  /// Said after each figure, "points" say.
  final String? unit;

  String _figure(LiquidItem item) => _figureOf(item, format, unit);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final top = items.map((item) => item.value).reduce(math.max);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              label: '${item.label}: ${_figure(item)}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.label,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 14,
                      child: Transform.flip(
                        flipX: Directionality.of(context) == TextDirection.rtl,
                        child: CustomPaint(
                          painter: _RowPainter(
                            fill: _fillOf(item, top),
                            colors: HoneyGlass.tinted(item.color),
                            dark: dark,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    // A count needs a few digits, a duration "27 h 9 min";
                    // both grow with the text size so neither wraps.
                    width: MediaQuery.textScalerOf(
                      context,
                    ).scale(format == null && unit == null ? 44 : 92),
                    child: Text(
                      _figure(item),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RowPainter extends CustomPainter {
  const _RowPainter({
    required this.fill,
    required this.colors,
    required this.dark,
  });

  final double fill;
  final List<Color> colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(size.height / 2)),
      );
    HoneyGlass.paintVessel(canvas, shape, bounds, dark);
    final inner = bounds.deflate(2);
    final innerShape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(inner.height / 2)),
      );
    HoneyGlass.paintHoney(
      canvas,
      innerShape,
      Rect.fromLTWH(
        inner.left,
        inner.top,
        inner.width * fill.clamp(0.0, 1.0),
        inner.height,
      ),
      BudgetLevel.within,
      bubbles: false,
      colorsOverride: colors,
    );
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
  }

  @override
  bool shouldRepaint(_RowPainter old) =>
      old.fill != fill || old.colors != colors || old.dark != dark;
}
