import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_filter_bar.dart'
    show GlassSearchField, WideToolbar;
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../data/knowledge_models.dart';
import '../data/knowledge_repository.dart';
import '../knowledge_tokens.dart';
import '../widgets/knowledge_widgets.dart';

/// The start page: find a page by searching, pick up where you left off,
/// open a favourite, or browse a space.
///
/// Search comes first because it is the fastest way to a page whose place one
/// does not know. Below it, only what this person has: recently opened pages,
/// favourites, then the spaces and what changed last.
class KnowledgeHomeView extends StatelessWidget {
  const KnowledgeHomeView({
    super.key,
    required this.repo,
    required this.search,
    required this.query,
    required this.onQueryChanged,
    required this.wide,
    required this.onOpenArticle,
    required this.onOpenSpace,
    required this.onNewSpace,
    required this.onNewPage,
  });

  final KnowledgeRepository repo;

  /// The page's search text, shared with the docked search on a phone.
  final TextEditingController search;
  final String query;
  final ValueChanged<String> onQueryChanged;

  /// A wide window: title and search are drawn here, not in the app bar.
  final bool wide;
  final ValueChanged<String> onOpenArticle;
  final ValueChanged<String> onOpenSpace;
  final VoidCallback onNewSpace;
  final VoidCallback onNewPage;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) ...[
          PageHead(
            title: context.t('knowledge.title'),
            subtitle: context.t(
              'knowledge.subtitle',
              variables: {
                'articles': '${repo.articles.length}',
                'spaces': '${repo.spaces.length}',
              },
            ),
            actions: [
              GhostButton(
                label: context.t('knowledge.newSpace'),
                icon: LucideIcons.folderPlus,
                onPressed: onNewSpace,
                collapseToIcon: true,
              ),
              PrimaryButton(
                label: context.t('knowledge.newArticle'),
                icon: LucideIcons.plus,
                onPressed: onNewPage,
                collapseToIcon: true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          WideToolbar(
            leading: [
              SizedBox(
                width: 420,
                child: GlassSearchField(
                  controller: search,
                  hint: context.t('knowledge.searchHint'),
                  onChanged: onQueryChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (q.isNotEmpty)
          _Results(repo: repo, query: q, onOpenArticle: onOpenArticle)
        else if (repo.spaces.isEmpty && repo.articles.isEmpty)
          HiveEmptyState(
            title: context.t('knowledge.emptyTitle'),
            message: context.t('knowledge.emptyMessage'),
            action: PrimaryButton(
              label: context.t('knowledge.newSpace'),
              icon: LucideIcons.folderPlus,
              onPressed: onNewSpace,
            ),
          )
        else
          ..._overview(context),
      ],
    );
  }

  List<Widget> _overview(BuildContext context) {
    final recent = repo.recent.take(4).toList();
    final starred = repo.starred.take(6).toList();
    final updated = repo.recentlyUpdated(limit: 6);
    return [
      if (recent.isNotEmpty) ...[
        KbSectionLabel(context.t('knowledge.home.continue')),
        const SizedBox(height: 12),
        _ContinueGrid(repo: repo, articles: recent, onOpen: onOpenArticle),
        const SizedBox(height: 32),
      ],
      if (starred.isNotEmpty) ...[
        KbSectionLabel(context.t('knowledge.home.starred')),
        const SizedBox(height: 6),
        for (final a in starred) _row(context, a),
        const SizedBox(height: 28),
      ],
      KbSectionLabel(context.t('knowledge.home.spaces')),
      const SizedBox(height: 12),
      _SpacesGrid(repo: repo, onOpenSpace: onOpenSpace, onNewSpace: onNewSpace),
      if (updated.isNotEmpty) ...[
        const SizedBox(height: 32),
        KbSectionLabel(context.t('knowledge.recentlyUpdated')),
        const SizedBox(height: 6),
        for (final a in updated) _row(context, a),
      ],
    ];
  }

  Widget _row(BuildContext context, KbArticle a) {
    final space = repo.spaceById(a.spaceId);
    final editor = repo.userById(a.editorId)?.name;
    return KbPageRow(
      article: a,
      space: space,
      meta: [
        if (space != null) space.name,
        context.t(
          'knowledge.updatedAgo',
          variables: {'when': kbWhen(context, a.updatedAt)},
        ),
        ?editor,
      ].join(' · '),
      onTap: () => onOpenArticle(a.id),
    );
  }
}

/// Matches in titles, labels, spaces and text; titles first.
class _Results extends StatelessWidget {
  const _Results({
    required this.repo,
    required this.query,
    required this.onOpenArticle,
  });

  final KnowledgeRepository repo;
  final String query;
  final ValueChanged<String> onOpenArticle;

  @override
  Widget build(BuildContext context) {
    final matches = repo.search(query);
    if (matches.isEmpty) {
      return HiveEmptyState(
        title: context.t('knowledge.noResultsTitle'),
        message: context.t('knowledge.noResultsMessage'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: KbSectionLabel(
            context.t(
              'knowledge.resultCount',
              variables: {'count': '${matches.length}'},
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (final a in matches.take(50))
          KbPageRow(
            article: a,
            space: repo.spaceById(a.spaceId),
            meta: [
              if (repo.spaceById(a.spaceId) case final s?) s.name,
              ...repo.ancestorsOf(a.id).map((p) => p.title),
            ].join(' › '),
            excerpt: repo.searchExcerpt(a.id, query),
            onTap: () => onOpenArticle(a.id),
          ),
      ],
    );
  }
}

/// Recently opened pages as cards: where it lives, its title, when it changed.
class _ContinueGrid extends StatelessWidget {
  const _ContinueGrid({
    required this.repo,
    required this.articles,
    required this.onOpen,
  });

  final KnowledgeRepository repo;
  final List<KbArticle> articles;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < KbTokens.bpPhone
            ? 1
            : (c.maxWidth / 240).floor().clamp(2, 4);
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final a in articles)
              SizedBox(
                width: w,
                child: _ContinueCard(
                  article: a,
                  space: repo.spaceById(a.spaceId),
                  onTap: () => onOpen(a.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.article,
    required this.space,
    required this.onTap,
  });

  final KbArticle article;
  final KbSpace? space;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hue = space?.hue ?? 250;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(KbTokens.radiusCard),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(KbTokens.radiusCard),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      KbSpaceGlyph(
                        icon: space?.icon ?? 'file-text',
                        hue: hue,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          space?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w600,
                            color: KbTokens.spaceChipText(hue),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t(
                      'knowledge.updatedAgo',
                      variables: {'when': kbWhen(context, article.updatedAt)},
                    ),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkSoft,
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

class _SpacesGrid extends StatelessWidget {
  const _SpacesGrid({
    required this.repo,
    required this.onOpenSpace,
    required this.onNewSpace,
  });

  final KnowledgeRepository repo;
  final ValueChanged<String> onOpenSpace;
  final VoidCallback onNewSpace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // A phone lists the spaces as rows: a card per space was a screen
        // of scrolling before the first page that changed.
        if (c.maxWidth < KbTokens.bpPhone) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in repo.spaces)
                _SpaceRow(
                  space: s,
                  count: repo.articleCountInSpace(s.id),
                  onTap: () => onOpenSpace(s.id),
                ),
              _NewSpaceRow(onTap: onNewSpace),
            ],
          );
        }
        final cols = (c.maxWidth / 280).floor().clamp(2, 4);
        const gap = 14.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in repo.spaces)
              SizedBox(
                width: w,
                child: _SpaceCard(
                  space: s,
                  count: repo.articleCountInSpace(s.id),
                  updatedAt: repo
                      .recentlyUpdated(spaceId: s.id, limit: 1)
                      .firstOrNull
                      ?.updatedAt,
                  onTap: () => onOpenSpace(s.id),
                ),
              ),
            SizedBox(
              width: w,
              child: _NewSpaceCard(onTap: onNewSpace),
            ),
          ],
        );
      },
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.space,
    required this.count,
    required this.updatedAt,
    required this.onTap,
  });

  final KbSpace space;
  final int count;
  final DateTime? updatedAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(KbTokens.radiusCard),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(KbTokens.radiusCard),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KbSpaceGlyph(icon: space.icon, hue: space.hue, size: 42),
                  const SizedBox(height: 14),
                  Text(
                    space.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: AppType.title,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  if (space.desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      space.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.label,
                        height: 1.45,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    [
                      context.t(
                        'knowledge.articleCount',
                        count: count,
                        variables: {'count': '$count'},
                      ),
                      if (updatedAt != null)
                        context.t(
                          'knowledge.updatedAgo',
                          variables: {'when': kbWhen(context, updatedAt)},
                        ),
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkSoft,
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

class _NewSpaceCard extends StatelessWidget {
  const _NewSpaceCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KbTokens.radiusCard),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KbTokens.radiusCard),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.folderPlus,
                  size: 20,
                  color: AppColors.inkSoft,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.t('knowledge.newSpace'),
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A space as one row, for a phone.
class _SpaceRow extends StatelessWidget {
  const _SpaceRow({
    required this.space,
    required this.count,
    required this.onTap,
  });

  final KbSpace space;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KbTokens.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            children: [
              KbSpaceGlyph(icon: space.icon, hue: space.hue, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      space.name,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t(
                        'knowledge.articleCount',
                        count: count,
                        variables: {'count': '$count'},
                      ),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NewSpaceRow extends StatelessWidget {
  const _NewSpaceRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KbTokens.radiusControl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Icon(
                  LucideIcons.folderPlus,
                  size: 20,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                context.t('knowledge.newSpace'),
                style: TextStyle(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
