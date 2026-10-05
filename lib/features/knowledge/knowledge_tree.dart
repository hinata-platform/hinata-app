import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassConfirm;
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_tokens.dart';
import '../../core/theme/app_type.dart';

/// Re-parent callback: move [id] under [parentId] (null = space root) within
/// [spaceId].
typedef ArticleMove =
    void Function(String id, {String? parentId, required String spaceId});

/// Space switcher + nested, folder-style article tree. Pages can be dragged onto
/// one another to nest (Confluence-style), dropped on the root zone to un-nest,
/// and each row offers add-sub-page / move-under / move-to-root / delete, so
/// every move dragging does is also a tap away (WCAG 2.5.7). Rendered in the
/// reader's left sidebar (≥ 720 px) and inside the phone drawer.
class KnowledgeTree extends StatelessWidget {
  const KnowledgeTree({
    super.key,
    required this.repo,
    required this.spaceId,
    required this.selectedId,
    required this.onSelect,
    required this.onSpaceChange,
    required this.onNewChild,
    required this.onMove,
    required this.onDelete,
  });

  final KnowledgeRepository repo;
  final String spaceId;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onSpaceChange;

  /// Create a new sub-page under [parentId].
  final ValueChanged<String> onNewChild;
  final ArticleMove onMove;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final inSpace = repo.articlesInSpace(spaceId);
    // Includes pages whose parent this person cannot read: they are roots
    // here rather than lost.
    final roots = repo.rootsInSpace(spaceId);
    // Each page's subpages, gathered once for the whole tree: every row
    // reads its own and the move picker walks them, so a row never scans the
    // space for them again.
    final children = <String?, List<KbArticle>>{};
    for (final a in inSpace) {
      children.putIfAbsent(a.parentId, () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassPopupMenu<String>(
            value: spaceId,
            onSelected: onSpaceChange,
            items: [
              for (final s in repo.spaces)
                GlassMenuItem(
                  value: s.id,
                  label: s.name,
                  leading: Icon(
                    lucideIcon(s.icon),
                    size: 16,
                    color: KbTokens.accent,
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      repo.spaceById(spaceId)?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    lucideIcon('chevron-down'),
                    size: 16,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Root drop zone — drop a page here to move it to the top level.
        _RootDropZone(spaceId: spaceId, repo: repo, onMove: onMove),
        for (final root in roots)
          _TreeBranch(
            repo: repo,
            article: root,
            inSpace: inSpace,
            children: children,
            depth: 0,
            selectedId: selectedId,
            onSelect: onSelect,
            onNewChild: onNewChild,
            onMove: onMove,
            onDelete: onDelete,
          ),
        // The server stops at its cap. Said once, quietly, under the tree, so a
        // subpage standing at the top is not read as "its parent is hidden
        // from me" when the parent is merely past the cut.
        if (repo.listTruncated) const _TruncatedNote(),
      ],
    );
  }
}

class _TruncatedNote extends StatelessWidget {
  const _TruncatedNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(LucideIcons.info, size: 13, color: AppColors.inkFaint),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.t('knowledge.tree.truncated'),
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RootDropZone extends StatefulWidget {
  const _RootDropZone({
    required this.spaceId,
    required this.repo,
    required this.onMove,
  });

  final String spaceId;
  final KnowledgeRepository repo;
  final ArticleMove onMove;

  @override
  State<_RootDropZone> createState() => _RootDropZoneState();
}

class _RootDropZoneState extends State<_RootDropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        final article = widget.repo.articleById(d.data);
        // Only meaningful if it isn't already a root in this space.
        final already =
            article?.parentId == null && article?.spaceId == widget.spaceId;
        if (!already) setState(() => _hover = true);
        return !already;
      },
      onLeave: (_) => setState(() => _hover = false),
      onAcceptWithDetails: (d) {
        setState(() => _hover = false);
        widget.onMove(d.data, parentId: null, spaceId: widget.spaceId);
      },
      builder: (context, candidate, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: _hover ? 30 : 8,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: _hover ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: _hover ? Border.all(color: AppColors.accentLine) : null,
        ),
        alignment: Alignment.center,
        child: _hover
            ? Text(
                context.t('knowledge.moveToTopLevel'),
                style: TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: KbTokens.accent,
                ),
              )
            : null,
      ),
    );
  }
}

class _TreeBranch extends StatefulWidget {
  const _TreeBranch({
    required this.repo,
    required this.article,
    required this.inSpace,
    required this.children,
    required this.depth,
    required this.selectedId,
    required this.onSelect,
    required this.onNewChild,
    required this.onMove,
    required this.onDelete,
  });

  final KnowledgeRepository repo;
  final KbArticle article;
  final List<KbArticle> inSpace;

  /// The subpages of each page in the space, by parent id.
  final Map<String?, List<KbArticle>> children;
  final int depth;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onNewChild;
  final ArticleMove onMove;
  final ValueChanged<String> onDelete;

  @override
  State<_TreeBranch> createState() => _TreeBranchState();
}

class _TreeBranchState extends State<_TreeBranch> {
  bool _open = true;

  /// The pages [widget.article] may move under, in tree order: everything in
  /// its space except itself, its own subpages and its current parent.
  ///
  /// Worked out when the picker opens, not per row per build: one walk over
  /// the space, which steps over the page's own subtree instead of asking of
  /// every page whether it lies below this one.
  List<({KbArticle page, int depth})> _parentCandidates() {
    final article = widget.article;
    final out = <({KbArticle page, int depth})>[];
    void walk(Iterable<KbArticle> level, int depth) {
      for (final a in level) {
        // A page's own subtree is no place for it, and so not offered.
        if (a.id == article.id) continue;
        if (a.id != article.parentId) out.add((page: a, depth: depth));
        walk(widget.children[a.id] ?? const [], depth + 1);
      }
    }

    walk(widget.repo.rootsInSpace(article.spaceId), 0);
    return out;
  }

  /// Moves [id] under [parent], first asking when that changes who can read
  /// it: a subtree takes the place of the page it moves under, so a private
  /// page moved under a project page is read by the whole project.
  Future<void> _moveUnderConfirmed(String id, KbArticle parent) async {
    final moving = widget.repo.articleById(id);
    if (moving != null &&
        (moving.projectId != parent.projectId ||
            moving.teamId != parent.teamId)) {
      final placeName =
          widget.repo.placeName(parent.projectId ?? parent.teamId) ??
          context.t(KbPlaceGlyph.labelKeyFor(parent.place));
      final ok = await showGlassConfirm(
        context,
        icon: KbPlaceGlyph.iconFor(parent.place),
        title: context.t('knowledge.moveUnderConfirm.title'),
        message: context.t(
          'knowledge.moveUnderConfirm.message',
          variables: {'page': moving.title, 'place': placeName},
        ),
        confirmLabel: context.t('knowledge.moveUnderConfirm.confirm'),
      );
      if (ok != true || !mounted) return;
    }
    widget.onMove(id, parentId: parent.id, spaceId: parent.spaceId);
  }

  /// The tap alternative to dropping this page onto another one.
  Future<void> _moveUnder(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    final panel = _ParentPickerPanel(rows: _parentCandidates());
    final parentId = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint
        ? await showGlassAnchoredPopover<String>(
            context,
            anchorRect: anchor,
            width: 320,
            builder: (_) => panel,
          )
        : await showGlassBottomSheet<String>(
            context,
            builder: (_) => SizedBox(height: 420, child: panel),
          );
    final parent = parentId == null ? null : widget.repo.articleById(parentId);
    if (parent == null || !context.mounted) return;
    await _moveUnderConfirmed(widget.article.id, parent);
  }

  /// Glass action menu for a tree row: move-under, move-to-root + delete.
  Widget _rowMenu(BuildContext context, bool canDelete, {required bool shown}) {
    // Cheap on purpose, since every row builds its menu: another page in the
    // space is enough to offer the move; the picker lists the actual choices.
    final canMoveUnder = widget.inSpace.length > 1;
    return GlassPopupMenu<String>(
      value: '',
      width: 240,
      onSelected: (v) {
        if (v == 'under') {
          _moveUnder(context);
        } else if (v == 'root') {
          widget.onMove(
            widget.article.id,
            parentId: null,
            spaceId: widget.article.spaceId,
          );
        } else if (v == 'delete' && canDelete) {
          widget.onDelete(widget.article.id);
        }
      },
      items: [
        if (canMoveUnder)
          GlassMenuItem(
            value: 'under',
            label: context.t('knowledge.moveUnder'),
            leading: Icon(
              LucideIcons.cornerDownRight,
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
        if (widget.article.parentId != null)
          GlassMenuItem(
            value: 'root',
            label: context.t('knowledge.moveToTopLevel'),
            leading: Icon(
              lucideIcon('panel-left'),
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
        GlassMenuItem(
          value: 'delete',
          label: canDelete
              ? context.t('knowledge.delete')
              : context.t('knowledge.deleteHasChildren'),
          enabled: canDelete,
          color: AppColors.danger,
          dividerAbove: canMoveUnder || widget.article.parentId != null,
          leading: Icon(
            lucideIcon('trash-2'),
            size: 16,
            color: AppColors.danger,
          ),
        ),
      ],
      child: Tooltip(
        message: context.t('knowledge.pageActions'),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            lucideIcon('ellipsis'),
            size: 15,
            color: shown ? AppColors.inkFaint : Colors.transparent,
          ),
        ),
      ),
    );
  }

  bool _hover = false;
  bool _dropHover = false;

  static bool get _mouseConnected =>
      RendererBinding.instance.mouseTracker.mouseIsConnected;

  @override
  Widget build(BuildContext context) {
    final kids = widget.children[widget.article.id] ?? const <KbArticle>[];
    final selected = widget.selectedId == widget.article.id;

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      // The page title inside names the row; `selected` marks the open page.
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: _dropHover
              ? AppColors.accentSoft
              : selected
              ? AppColors.accentSoft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => widget.onSelect(widget.article.id),
            child: Container(
              decoration: _dropHover
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accentLine),
                    )
                  : null,
              padding: EdgeInsets.fromLTRB(8 + widget.depth * 14, 5, 4, 5),
              child: Row(
                children: [
                  if (kids.isNotEmpty)
                    Semantics(
                      button: true,
                      expanded: _open,
                      label: context.t('knowledge.subpages'),
                      child: InkWell(
                        onTap: () => setState(() => _open = !_open),
                        borderRadius: BorderRadius.circular(4),
                        child: Icon(
                          lucideIcon(_open ? 'chevron-down' : 'chevron-right'),
                          size: 15,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 15),
                  const SizedBox(width: 6),
                  Icon(
                    lucideIcon(widget.article.icon),
                    size: 15,
                    color: selected ? KbTokens.accent : AppColors.inkSoft,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? AppColors.ink : AppColors.inkSoft,
                      ),
                    ),
                  ),
                  // Where a top-level page lives; its subpages live there too, so
                  // repeating it on every row would only add noise.
                  if (widget.depth == 0)
                    KbPlaceGlyph(place: widget.article.place),
                  // Row actions: shown on hover and on the open page with a
                  // mouse, always without one, since a finger cannot hover.
                  // Kept in the tree while hidden, so a screen reader and the
                  // keyboard reach them on every row.
                  // Hidden by colour rather than an Opacity, which would give
                  // every row a compositing layer of its own. A pointer that
                  // could click them is over the row, and then they show.
                  Builder(
                    builder: (context) {
                      final shown = _hover || selected || !_mouseConnected;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _RowAction(
                            icon: 'plus',
                            tooltip: context.t('knowledge.addSubPage'),
                            shown: shown,
                            onTap: () => widget.onNewChild(widget.article.id),
                          ),
                          _rowMenu(context, kids.isEmpty, shown: shown),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Drag the page; drop another page onto it to nest.
    final draggable = Draggable<String>(
      data: widget.article.id,
      dragAnchorStrategy: childDragAnchorStrategy,
      feedback: _DragChip(
        title: widget.article.title,
        icon: widget.article.icon,
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) {
          // Reject self / moving a page into its own subtree.
          final ok =
              d.data != widget.article.id &&
              !widget.repo.isSelfOrAncestor(d.data, widget.article.id);
          if (ok) setState(() => _dropHover = true);
          return ok;
        },
        onLeave: (_) => setState(() => _dropHover = false),
        onAcceptWithDetails: (d) {
          setState(() => _dropHover = false);
          _moveUnderConfirmed(d.data, widget.article);
        },
        builder: (context, _, _) => row,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        draggable,
        if (_open)
          for (final c in kids)
            _TreeBranch(
              repo: widget.repo,
              article: c,
              inSpace: widget.inSpace,
              children: widget.children,
              depth: widget.depth + 1,
              selectedId: widget.selectedId,
              onSelect: widget.onSelect,
              onNewChild: widget.onNewChild,
              onMove: widget.onMove,
              onDelete: widget.onDelete,
            ),
      ],
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.shown = true,
  });

  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Whether the glyph is drawn; a hidden action stays in the tree for
  /// screen readers and the keyboard.
  final bool shown;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              lucideIcon(icon),
              size: 15,
              color: shown ? AppColors.inkFaint : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

/// The pages a page can move under, indented as in the tree. Tapping one
/// closes the picker with its id.
class _ParentPickerPanel extends StatelessWidget {
  const _ParentPickerPanel({required this.rows});

  final List<({KbArticle page, int depth})> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            context.t('knowledge.moveUnderTitle'),
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: AppType.body,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              return Semantics(
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pop(row.page.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        8 + row.depth * 14,
                        8,
                        8,
                        8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            lucideIcon(row.page.icon),
                            size: 15,
                            color: AppColors.inkSoft,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              row.page.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppType.label,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          // Where the page lives: moving under it hands the
                          // subtree that place, and with it its readers.
                          KbPlaceGlyph(place: row.page.place),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DragChip extends StatelessWidget {
  const _DragChip({required this.title, required this.icon});
  final String title;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accentLine),
          boxShadow: [
            BoxShadow(
              color: AppColors.navyDeep.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(lucideIcon(icon), size: 15, color: KbTokens.accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                title,
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
      ),
    );
  }
}

/// The small glyph saying where a page lives: a lock for "only me", people for
/// a team, a folder for a project. Shape carries the meaning, the tooltip names
/// it, so it never rests on colour.
class KbPlaceGlyph extends StatelessWidget {
  const KbPlaceGlyph({super.key, required this.place, this.size = 13});

  final KbPlace place;
  final double size;

  static IconData iconFor(KbPlace place) => switch (place) {
    KbPlace.private => LucideIcons.lock,
    KbPlace.team => LucideIcons.users,
    KbPlace.project => LucideIcons.folder,
  };

  static String labelKeyFor(KbPlace place) => switch (place) {
    KbPlace.private => 'knowledge.place.private',
    KbPlace.team => 'knowledge.place.team',
    KbPlace.project => 'knowledge.place.project',
  };

  @override
  Widget build(BuildContext context) {
    final label = context.t(labelKeyFor(place));
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 6, end: 2),
          child: Icon(iconFor(place), size: size, color: AppColors.inkFaint),
        ),
      ),
    );
  }
}
