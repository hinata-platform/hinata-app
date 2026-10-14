import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/lexical/hinata_document.dart';
import '../../core/lexical/hinata_lexical.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../../core/lexical/hinata_outline.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_place_field.dart';
import 'knowledge_scope.dart';
import 'knowledge_tokens.dart';
import 'markdown/smart_link_resolver.dart';
import 'widgets/knowledge_widgets.dart';
import '../../core/theme/app_type.dart';

enum AsideMode { side, below, none }

/// Article reader: breadcrumb · title · byline (contributor stack · updated ·
/// reads) · labels · rendered body · *Linked issues* grid, plus an aside with
/// Table-of-contents, Contributors, Related articles and Details.
class KnowledgeReader extends StatefulWidget {
  const KnowledgeReader({
    super.key,
    required this.article,
    required this.asideMode,
    required this.starred,
    required this.onToggleStar,
    required this.onOpenSpace,
    required this.onOpenHistory,
    this.contributors,
    this.onPlace,
    this.placeBusy = false,
  });

  final KbArticle article;
  final AsideMode asideMode;

  /// Whether the reader keeps this page among their favourites.
  final bool starred;
  final VoidCallback onToggleStar;
  final ValueChanged<String> onOpenSpace;
  final VoidCallback onOpenHistory;

  /// Who worked on the page, most recent first; null while it loads.
  final List<String>? contributors;

  /// Moves the page (a top-level one; subpages follow their parent) into a
  /// project, a team or back to its author. Null hides the "visible to" row.
  final ValueChanged<KbPlaceChoice>? onPlace;

  /// A place change is on its way to the server.
  final bool placeBusy;

  @override
  State<KnowledgeReader> createState() => _KnowledgeReaderState();
}

class _KnowledgeReaderState extends State<KnowledgeReader> {
  /// Publishes the mounted blocks so the outline can scroll to one.
  final BlockRegistry _blocks = BlockRegistry();

  /// The document's headings. Empty until the document has been opened, which
  /// is a frame later — node keys are assigned at parse time, not stored.
  List<OutlineEntry> _outline = const [];

  /// Issues the article links to — read from the document's smart links, which
  /// is where a reference lives now that it is a node.
  List<String> _linkedIssueIds = const [];
  NodeKey? _activeToc;

  /// The page's subpages and related pages, worked out once per page and
  /// change of the cache rather than on every frame the reader rebuilds.
  List<KbArticle> _children = const [];
  List<KbArticle> _related = const [];
  (String, int)? _derivedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _derive();
  }

  @override
  void didUpdateWidget(KnowledgeReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _derive();
  }

  void _derive() {
    final repo = KnowledgeScope.of(context).repo;
    final key = (widget.article.id, repo.revision);
    if (key == _derivedFor) return;
    _derivedFor = key;
    _children = repo.childrenOf(widget.article.id);
    _related = repo.relatedArticles(widget.article);
  }

  @override
  void dispose() {
    _blocks.dispose();
    super.dispose();
  }

  /// Takes the outline and the linked issues from the document that is on
  /// screen — including when there is none.
  ///
  /// The reader has no key, so its State is reused when a different article is
  /// opened. Leaving the previous article's headings up because the new one
  /// could not be read is not a smaller failure than showing nothing: the
  /// entries point at node keys from a document that is gone, so every one of
  /// them is a button that does nothing.
  void _onDocument(LexicalEditor? editor) {
    final outline = editor == null
        ? const <OutlineEntry>[]
        : documentOutline(editor);
    final linked = editor == null
        ? const <String>[]
        : documentSmartLinks(editor, SmartLinkKind.issue);
    if (!mounted) return;
    setState(() {
      _outline = outline;
      _linkedIssueIds = linked;
      _activeToc = null;
    });
  }

  void _jump(OutlineEntry entry) {
    final position = Scrollable.maybeOf(context)?.position;
    // A heading the renderer has culled has no render object yet; marking it
    // active without moving would be a button that lies.
    if (position != null &&
        revealBlock(_blocks, position, entry.nodeKey, alignment: 0.02)) {
      setState(() => _activeToc = entry.nodeKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = KnowledgeScope.of(context).repo;
    final article = _article(repo);
    final aside = _aside(repo, _outline);

    switch (widget.asideMode) {
      case AsideMode.side:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: KbTokens.readerMaxWidth,
                  ),
                  child: article,
                ),
              ),
            ),
            const SizedBox(width: KbTokens.asideGap),
            SizedBox(width: KbTokens.asideWidth, child: aside),
          ],
        );
      case AsideMode.below:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KbTokens.readerMaxWidth,
              ),
              child: article,
            ),
            const SizedBox(height: 30),
            aside,
          ],
        );
      case AsideMode.none:
        return article;
    }
  }

  // ── article column ──
  Widget _article(KnowledgeRepository repo) {
    final a = widget.article;
    final sp = repo.spaceById(a.spaceId);
    final editor = repo.userById(a.editorId);
    final ancestors = repo.ancestorsOf(a.id);
    final children = _children;
    final linkedIds = _linkedIssueIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Breadcrumbs(
          space: sp,
          ancestors: ancestors,
          onOpenSpace: widget.onOpenSpace,
          onOpenArticle: KnowledgeScope.of(context).openArticle,
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            a.title,
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: AppType.hero,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.7,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            AppAvatar(
              name: editor?.name ?? '?',
              pronouns: editor?.pronouns,
              radius: 14,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.t(
                  'knowledge.reader.lastEdited',
                  variables: {
                    'name':
                        editor?.name ?? context.t('knowledge.reader.someone'),
                    'when': kbWhen(context, a.updatedAt),
                  },
                ),
                style: TextStyle(
                  fontSize: AppType.label,
                  height: 1.4,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            const SizedBox(width: 8),
            KbStarPill(
              starred: widget.starred,
              tooltip: context.t(
                widget.starred
                    ? 'knowledge.reader.unstar'
                    : 'knowledge.reader.star',
              ),
              onTap: widget.onToggleStar,
            ),
          ],
        ),
        if (a.labels.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final l in a.labels) KbLabelChip(label: l)],
          ),
        ],
        if (widget.onPlace != null) ...[
          const SizedBox(height: 8),
          KnowledgePlaceField(
            repo: repo,
            projectId: a.projectId,
            teamId: a.teamId,
            organization: a.organization,
            followsParent: !repo.isTopLevel(a),
            // Only the author may make a page private; a page that already is
            // private can only be the author's own.
            allowPrivate:
                a.authorId == repo.me.id || a.place == KbPlace.private,
            canChange: () => repo.mayChangePlace(a),
            busy: widget.placeBusy,
            onChanged: widget.onPlace!,
          ),
        ],
        const SizedBox(height: 20),
        Divider(height: 1, color: AppColors.hairline),
        const SizedBox(height: 8),
        // The stored document, rendered. Not scrollable: the page around it
        // already scrolls, and the outline reveals blocks through that same
        // position.
        HinataDocument(
          // An article the backfill could not convert still has its markdown;
          // rendering that beats rendering an empty page.
          doc: documentOrLegacy(widget.article.doc, widget.article.body),
          registry: _blocks,
          onDocument: _onDocument,
        ),
        if (children.isNotEmpty) _subpages(children),
        if (linkedIds.isNotEmpty) _linkedIssues(linkedIds),
      ],
    );
  }

  /// The pages filed under this one, so a reader can go deeper without the tree.
  Widget _subpages(List<KbArticle> children) {
    return Container(
      margin: const EdgeInsets.only(top: 38),
      padding: const EdgeInsets.only(top: 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KbSectionLabel(context.t('knowledge.subpages')),
          const SizedBox(height: 6),
          for (final c in children)
            MergeSemantics(
              child: Semantics(
                link: true,
                child: InkWell(
                  onTap: () => KnowledgeScope.of(context).openArticle(c.id),
                  borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            lucideIcon(c.icon),
                            size: 17,
                            color: KbTokens.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.title,
                              style: TextStyle(
                                fontSize: AppType.body,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: AppColors.inkSoft,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linkedIssues(List<String> linkedIds) {
    return Container(
      margin: const EdgeInsets.only(top: 38),
      padding: const EdgeInsets.only(top: 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(lucideIcon('link-2'), size: 16, color: KbTokens.accent),
              const SizedBox(width: 8),
              Text(
                context.t('knowledge.linkedIssues'),
                style: const TextStyle(
                  fontSize: AppType.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(
                  '${linkedIds.length}',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: AppType.caption,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth < KbTokens.bpPhone
                  ? 1
                  : (c.maxWidth / 290).floor().clamp(1, 3);
              const gap = 10.0;
              final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final id in linkedIds)
                    SizedBox(
                      width: tileW,
                      child: _IssueCard(id: id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── aside ──
  Widget _aside(KnowledgeRepository repo, List<OutlineEntry> toc) {
    final a = widget.article;
    final sp = repo.spaceById(a.spaceId);
    final related = _related;
    final contributors = widget.contributors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (toc.length > 1) ...[
          _asideHeader(context.t('knowledge.onThisPage')),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.hairline, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final t in toc) _tocRow(t)],
            ),
          ),
          const SizedBox(height: 24),
        ],
        _asideHeader(context.t('knowledge.details')),
        const SizedBox(height: 6),
        _detail(context.t('knowledge.space'), sp?.name ?? '—'),
        _detail(context.t('knowledge.created'), kbDate(context, a.createdAt)),
        _detail(
          context.t('knowledge.reader.changed'),
          kbWhen(context, a.updatedAt),
        ),
        _detail(
          context.t('knowledge.reader.author'),
          repo.userById(a.authorId)?.name ?? '—',
        ),
        Semantics(
          button: true,
          child: InkWell(
            onTap: widget.onOpenHistory,
            borderRadius: BorderRadius.circular(KbTokens.radiusControl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Icon(LucideIcons.history, size: 15, color: KbTokens.accent),
                  const SizedBox(width: 8),
                  Text(
                    context.t('knowledge.history.open'),
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (contributors != null && contributors.isNotEmpty) ...[
          const SizedBox(height: 22),
          _asideHeader(context.t('knowledge.contributors')),
          const SizedBox(height: 8),
          for (final id in contributors.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  AppAvatar(
                    name: repo.userById(id)?.name ?? '?',
                    pronouns: repo.userById(id)?.pronouns,
                    radius: 13,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      repo.userById(id)?.name ??
                          context.t('knowledge.reader.someone'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.label,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (related.isNotEmpty) ...[
          const SizedBox(height: 22),
          _asideHeader(context.t('knowledge.relatedArticles')),
          const SizedBox(height: 6),
          for (final d in related)
            MergeSemantics(
              child: Semantics(
                link: true,
                child: InkWell(
                  onTap: () => KnowledgeScope.of(context).openArticle(d.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Row(
                      children: [
                        Icon(
                          lucideIcon(d.icon),
                          size: 15,
                          color: KbTokens.accent,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            d.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.label,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _asideHeader(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: AppType.caption,
      letterSpacing: 0.9,
      fontWeight: FontWeight.w700,
      color: AppColors.inkFaint,
    ),
  );

  Widget _tocRow(OutlineEntry t) {
    final on = _activeToc == t.nodeKey;
    // The heading text names the entry; `selected` marks the one in view.
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        onTap: () => _jump(t),
        child: Transform.translate(
          offset: const Offset(-2, 0),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              t.level == 1 ? 12.0 : (t.level == 2 ? 22.0 : 32.0),
              5,
              8,
              5,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: on ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              t.text,
              style: TextStyle(
                fontSize: t.level == AppType.badge
                    ? AppType.caption
                    : AppType.label,
                height: 1.35,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? KbTokens.accent : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppType.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One "Linked issues" card: type glyph · id · state · title · assignee.
/// Resolves [id] (a readable id) against the real backend via [SmartLinkScope];
/// falls back to an id-only card while issues are still loading / not found.
class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final resolver = SmartLinkScope.of(context);
    final it = resolver.issue(id);
    final color = it?.typeColor ?? KbTokens.accent;
    // The issue id and title inside name the card.
    return Semantics(
      button: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        child: InkWell(
          onTap: () => resolver.openIssue(id),
          borderRadius: BorderRadius.circular(KbTokens.radiusCard),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KbTokens.radiusCard),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    lucideIcon(it?.typeIcon ?? 'circle-check'),
                    size: 16,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            id,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          if (it != null) ...[
                            const SizedBox(width: 9),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: it.stateColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                it.stateName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppType.caption,
                                  fontWeight: FontWeight.w600,
                                  color: it.stateColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        it?.title ?? context.t('knowledge.openIssue'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppType.label,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (it?.assigneeName != null)
                  AppAvatar(name: it!.assigneeName!, radius: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the page sits: its space, then every page above it. Each step opens.
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({
    required this.space,
    required this.ancestors,
    required this.onOpenSpace,
    required this.onOpenArticle,
  });

  final KbSpace? space;
  final List<KbArticle> ancestors;
  final ValueChanged<String> onOpenSpace;
  final ValueChanged<String> onOpenArticle;

  @override
  Widget build(BuildContext context) {
    final sp = space;
    final steps = <Widget>[
      if (sp != null)
        _Crumb(
          label: sp.name,
          leading: Icon(
            lucideIcon(sp.icon),
            size: 14,
            color: KbTokens.spaceChipText(sp.hue),
          ),
          color: KbTokens.spaceChipText(sp.hue),
          onTap: () => onOpenSpace(sp.id),
        ),
      for (final a in ancestors)
        _Crumb(
          label: a.title,
          color: AppColors.inkSoft,
          onTap: () => onOpenArticle(a.id),
        ),
    ];
    return Semantics(
      container: true,
      label: context.t('knowledge.reader.breadcrumb'),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, step) in steps.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 14,
                  color: AppColors.inkSoft,
                ),
              ),
            step,
          ],
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.color,
    required this.onTap,
    this.leading,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          // 24 is the floor for an inline link; the band keeps the line low.
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading case final icon?) ...[
                  icon,
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
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
