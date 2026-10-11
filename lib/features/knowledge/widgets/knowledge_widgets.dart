import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_filter_bar.dart'
    show GlassPill, kGlassPillHeight;
import '../data/knowledge_models.dart';
import '../knowledge_tokens.dart';

/// When something happened, the way the knowledge base says it: "just now",
/// "5 min ago", "3 h ago", "2 days ago", then the date.
String kbWhen(BuildContext context, DateTime? at) {
  if (at == null) return '—';
  final local = at.toLocal();
  final d = DateTime.now().difference(local);
  if (d.inMinutes < 1) return context.t('knowledge.time.justNow');
  if (d.inMinutes < 60) {
    return context.t(
      'knowledge.time.minutes',
      count: d.inMinutes,
      variables: {'count': d.inMinutes},
    );
  }
  if (d.inHours < 24) {
    return context.t(
      'knowledge.time.hours',
      count: d.inHours,
      variables: {'count': d.inHours},
    );
  }
  if (d.inDays < 7) {
    return context.t(
      'knowledge.time.days',
      count: d.inDays,
      variables: {'count': d.inDays},
    );
  }
  return kbDate(context, local);
}

/// A calendar date in the reader's language.
String kbDate(BuildContext context, DateTime? at) => at == null
    ? '—'
    : DateFormat.yMMMd(
        Localizations.localeOf(context).toString(),
      ).format(at.toLocal());

/// A date with its time, for the version history.
String kbDateTime(BuildContext context, DateTime? at) => at == null
    ? '—'
    : DateFormat.yMMMd(
        Localizations.localeOf(context).toString(),
      ).add_Hm().format(at.toLocal());

/// A space's glyph on its own tint: icon on a soft square in the space's hue.
class KbSpaceGlyph extends StatelessWidget {
  const KbSpaceGlyph({
    super.key,
    required this.icon,
    required this.hue,
    this.size = 40,
  });

  final String icon;
  final int hue;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: KbTokens.spaceChipBg(hue),
      borderRadius: BorderRadius.circular(size * 0.26),
    ),
    alignment: Alignment.center,
    child: Icon(
      lucideIcon(icon),
      size: size * 0.5,
      color: KbTokens.spaceChipText(hue),
    ),
  );
}

/// A small caps heading over a group: "RECENTLY OPENED", "PAGES".
class KbSectionLabel extends StatelessWidget {
  const KbSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: AppType.caption,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A label on a page, as a quiet chip. Filtering by a label is
/// [KbLabelPill]'s job.
class KbLabelChip extends StatelessWidget {
  const KbLabelChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      border: Border.all(color: AppColors.hairline2),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.tag, size: 12, color: AppColors.inkSoft),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One page in a list: glyph, title, where it lives and when it changed.
/// Used by the start page, a space and the search.
class KbPageRow extends StatelessWidget {
  const KbPageRow({
    super.key,
    required this.article,
    required this.space,
    required this.meta,
    required this.onTap,
    this.excerpt,
  });

  final KbArticle article;
  final KbSpace? space;

  /// The line under the title: space, editor, when.
  final String meta;
  final String? excerpt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hue = space?.hue ?? 250;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(KbTokens.radiusControl),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KbTokens.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KbSpaceGlyph(icon: article.icon, hue: hue, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            height: 1.4,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        if (excerpt case final text? when text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.label,
                              height: 1.45,
                              color: AppColors.inkSoft,
                            ),
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
      ),
    );
  }
}

/// A label as a glass filter pill: amber wash while it narrows the list, so
/// a filtered list never looks like an empty one.
class KbLabelPill extends StatelessWidget {
  const KbLabelPill({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: GlassPill(
      active: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? LucideIcons.check : LucideIcons.tag,
              size: 15,
              color: selected ? AppColors.accentInk : AppColors.inkSoft,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: AppType.caption,
                color: AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The favourite toggle: a round glass pill, washed amber while the page is
/// a favourite. The tooltip names it, `selected` says which way it stands.
class KbStarPill extends StatelessWidget {
  const KbStarPill({
    super.key,
    required this.starred,
    required this.tooltip,
    required this.onTap,
  });

  final bool starred;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      label: tooltip,
      selected: starred,
      child: GlassPill(
        active: starred,
        onTap: onTap,
        child: SizedBox(
          width: kGlassPillHeight,
          child: Icon(
            LucideIcons.star,
            size: 18,
            color: starred ? AppColors.accentInk : AppColors.inkSoft,
          ),
        ),
      ),
    ),
  );
}
