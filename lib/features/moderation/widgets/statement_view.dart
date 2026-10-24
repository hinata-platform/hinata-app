import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';

/// A notice of the moderation, one statement per line as DSA Art. 17(3) asks
/// (HIN-173): what was done, why and on what grounds, whether a machine was
/// involved, what moderation wrote, and what the person can do. The words are
/// the server's, in the reader's language. [compact] is the smaller form the
/// moderation reads before it decides (HIN-174).
class StatementView extends StatelessWidget {
  const StatementView({
    super.key,
    required this.statement,
    this.compact = false,
  });

  final Statement statement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    String? joined(List<String?> parts) {
      final text = parts
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(' ');
      return text.isEmpty ? null : text;
    }

    final facts = <(IconData, String, String?)>[
      (LucideIcons.messageSquare, 'moderation.statement.measure', s.measure),
      (
        LucideIcons.flag,
        'moderation.statement.basis',
        joined([s.basis, s.facts]),
      ),
      (
        LucideIcons.bookOpenCheck,
        s.lawGround ? 'moderation.statement.law' : 'moderation.statement.rule',
        s.groundText,
      ),
      (LucideIcons.bot, 'moderation.statement.automation', s.automation),
      (
        LucideIcons.messageCircle,
        'moderation.statement.message',
        s.messageToAuthor,
      ),
      (
        LucideIcons.scale,
        'moderation.statement.remedies',
        joined([s.appeal, s.courtsNote]),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, key, text) in facts)
          if (text != null && text.trim().isNotEmpty)
            _Fact(
              icon: icon,
              label: context.t(key),
              text: text,
              compact: compact,
            ),
      ],
    );
  }
}

/// One statement: a glyph, what it is, and the sentence.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.text,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 5 : 8),
    child: MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: Icon(
                icon,
                size: compact ? 16 : 18,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: compact ? AppType.label : AppType.body,
                    height: 1.45,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
