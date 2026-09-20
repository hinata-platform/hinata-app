import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'hex_mark.dart';

/// The brand empty state, used on every surface that can run out of rows: the
/// amber HexMark signet over a title and a caption, centred.
///
/// It sits on **nothing**. It used to bring a [SoftCard] of its own, and that
/// card was the problem: an empty list already sits inside a page, a panel or a
/// sheet that has a surface, so the card drew a second one — a pale slab in the
/// middle of the page with three lines floating in it. Almost every caller had
/// already turned it off by hand, which is the clearest vote a default gets.
///
/// Without a surface behind it the words have to carry themselves, so the title
/// is the page's ink rather than a soft grey, and the caption is one step down
/// from it rather than two.
class HiveEmptyState extends StatelessWidget {
  const HiveEmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.padding = const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
  });

  final String title;
  final String? message;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const HexMark(size: 40, color: AppColors.accentLine),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
