import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_type.dart';
import 'frosted_card.dart';

/// One figure over a report: an icon, what it counts, the number, and an
/// optional line under it.
typedef FigureTile = ({
  IconData icon,
  String label,
  String value,
  String? note,
  Color? valueColor,
});

/// The figures over a report as frosted tiles (HIN-157): four abreast where
/// they fit, two, or one on the narrowest phone. The report overview and a
/// sprint's insights stand on the same row of them.
class FigureTiles extends StatelessWidget {
  const FigureTiles({super.key, required this.tiles});

  final List<FigureTile> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 860
          ? 4
          : constraints.maxWidth >= 300
          ? 2
          : 1;
      const gap = 14.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final tile in tiles)
            SizedBox(
              width: width,
              child: Semantics(
                label: ['${tile.label}: ${tile.value}', ?tile.note].join(', '),
                excludeSemantics: true,
                child: FrostedCard(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              tile.icon,
                              size: 16,
                              color: AppColors.accentInk,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tile.label,
                              style: TextStyle(
                                fontSize: AppType.label,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Shrinks rather than wraps where two tiles share a
                      // phone's width and the figure is a long one.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          tile.value,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: AppType.hero,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: tile.valueColor ?? AppColors.ink,
                          ),
                        ),
                      ),
                      if (tile.note case final note?) ...[
                        const SizedBox(height: 4),
                        Text(
                          note,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
