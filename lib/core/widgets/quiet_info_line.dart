import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// A glyph and a quiet sentence: what a step means, why something is held,
/// what comes next. [action] is a step offered under the sentence, such as
/// "Freigeben …". The glyph is decoration; the sentence says it all.
class QuietInfoLine extends StatelessWidget {
  const QuietInfoLine({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: ExcludeSemantics(
            child: Icon(icon, size: 16, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: AppType.label,
                  height: 1.4,
                  color: AppColors.inkSoft,
                ),
              ),
              if (action case final action?)
                Padding(padding: const EdgeInsets.only(top: 4), child: action),
            ],
          ),
        ),
      ],
    ),
  );
}
