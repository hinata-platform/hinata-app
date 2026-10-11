import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../data/knowledge_models.dart';
import '../data/knowledge_repository.dart';
import '../knowledge_tree.dart';
import '../widgets/knowledge_widgets.dart';

/// One space: what it is for, all its pages as a tree, and what changed.
///
/// A space opens even when it has no pages yet, and then offers the first
/// one. Labels on its pages filter the list, so a space with many pages can
/// still be read by topic.
class KnowledgeSpaceView extends StatelessWidget {
  const KnowledgeSpaceView({
    super.key,
    required this.repo,
    required this.space,
    required this.wide,
    required this.label,
    required this.onLabel,
    required this.onOpenArticle,
    required this.onNewPage,
    required this.onNewChild,
    required this.onMove,
    required this.onShift,
    required this.onDelete,
  });

  final KnowledgeRepository repo;
  final KbSpace space;

  /// A wide window: the tree and the changes sit side by side.
  final bool wide;

  /// The label the list is narrowed to, if any.
  final String? label;
  final ValueChanged<String?> onLabel;
  final ValueChanged<String> onOpenArticle;
  final VoidCallback onNewPage;
  final ValueChanged<String> onNewChild;
  final ArticleMove onMove;
  final void Function(String id, int delta) onShift;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final pages = repo.articlesInSpace(space.id);
    final labels = repo.labels(spaceId: space.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          space: space,
          count: pages.length,
          updatedAt: repo
              .recentlyUpdated(spaceId: space.id, limit: 1)
              .firstOrNull
              ?.updatedAt,
          onNewPage: wide ? onNewPage : null,
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            children: [
              for (final l in labels.take(12))
                KbLabelChip(
                  label: l.label,
                  count: l.count,
                  selected: l.label == label,
                  onTap: () => onLabel(l.label == label ? null : l.label),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        if (pages.isEmpty)
          HiveEmptyState(
            title: context.t('knowledge.spaceView.emptyTitle'),
            message: context.t('knowledge.spaceView.emptyMessage'),
            action: PrimaryButton(
              label: context.t('knowledge.spaceView.firstPage'),
              icon: LucideIcons.filePlus,
              onPressed: onNewPage,
            ),
          )
        else if (label != null)
          _Labelled(
            repo: repo,
            space: space,
            label: label!,
            onOpenArticle: onOpenArticle,
          )
        else if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _pagesPanel(context)),
              const SizedBox(width: 32),
              Expanded(flex: 4, child: _changesPanel(context)),
            ],
          )
        else ...[
          _pagesPanel(context),
          const SizedBox(height: 28),
          _changesPanel(context),
        ],
      ],
    );
  }

  Widget _pagesPanel(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KbSectionLabel(context.t('knowledge.spaceView.pages')),
      const SizedBox(height: 8),
      KnowledgeTree(
        repo: repo,
        spaceId: space.id,
        selectedId: null,
        onSelect: onOpenArticle,
        onNewChild: onNewChild,
        onMove: onMove,
        onShift: onShift,
        onDelete: onDelete,
      ),
    ],
  );

  Widget _changesPanel(BuildContext context) {
    final changed = repo.recentlyUpdated(spaceId: space.id, limit: 8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KbSectionLabel(context.t('knowledge.recentlyUpdated')),
        const SizedBox(height: 6),
        for (final a in changed)
          KbPageRow(
            article: a,
            space: space,
            meta: [
              context.t(
                'knowledge.updatedAgo',
                variables: {'when': kbWhen(context, a.updatedAt)},
              ),
              ?repo.userById(a.editorId)?.name,
            ].join(' · '),
            onTap: () => onOpenArticle(a.id),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.space,
    required this.count,
    required this.updatedAt,
    required this.onNewPage,
  });

  final KbSpace space;
  final int count;
  final DateTime? updatedAt;

  /// Drawn in the header on a wide window; a phone has it in the app bar.
  final VoidCallback? onNewPage;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KbSpaceGlyph(icon: space.icon, hue: space.hue, size: 56),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  space.name,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: AppType.display,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (space.desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  space.desc,
                  style: TextStyle(
                    fontSize: AppType.body,
                    height: 1.5,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
              const SizedBox(height: 8),
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
        if (onNewPage case final tap?) ...[
          const SizedBox(width: 16),
          PrimaryButton(
            label: context.t('knowledge.newArticle'),
            icon: LucideIcons.plus,
            onPressed: tap,
            collapseToIcon: true,
          ),
        ],
      ],
    );
  }
}

/// The pages of the space that carry [label], as a flat list with their path.
class _Labelled extends StatelessWidget {
  const _Labelled({
    required this.repo,
    required this.space,
    required this.label,
    required this.onOpenArticle,
  });

  final KnowledgeRepository repo;
  final KbSpace space;
  final String label;
  final ValueChanged<String> onOpenArticle;

  @override
  Widget build(BuildContext context) {
    final pages = repo
        .articlesInSpace(space.id)
        .where((a) => a.labels.contains(label))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: KbSectionLabel(
            context.t(
              'knowledge.spaceView.withLabel',
              variables: {'label': label, 'count': '${pages.length}'},
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (final a in pages)
          KbPageRow(
            article: a,
            space: space,
            meta: [
              ...repo.ancestorsOf(a.id).map((p) => p.title),
              context.t(
                'knowledge.updatedAgo',
                variables: {'when': kbWhen(context, a.updatedAt)},
              ),
            ].join(' · '),
            onTap: () => onOpenArticle(a.id),
          ),
      ],
    );
  }
}
