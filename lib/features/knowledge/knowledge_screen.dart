import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_filter_bar.dart'
    show GlassSearchButton, GlassSearchDock, kGlassControlHeight, kGlassDockRow;
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassBottomSheet, showGlassConfirm, showGlassToast;
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_cubit.dart';
import 'knowledge_editor.dart';
import 'knowledge_home.dart';
import 'knowledge_space_dialog.dart';
import 'knowledge_link_resolver.dart';
import 'knowledge_place_field.dart';
import 'knowledge_reader.dart';
import 'knowledge_scope.dart';
import 'knowledge_tokens.dart';
import 'knowledge_tree.dart';
import 'markdown/smart_link_resolver.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/theme/app_type.dart';

/// Confluence-style Knowledge Base shell: spaces home, nested article tree,
/// reader with TOC/aside/linked-issues, and a full markdown editor with
/// `@`-smart-links. Self-contained (seed data + local persistence); a 1:1 port
/// of the design reference `view_knowledge.jsx`. Internal navigation between
/// home/space/article/edit/new is managed here (not via the router).
class KnowledgeScreen extends StatelessWidget {
  const KnowledgeScreen({super.key, this.initialArticleId});

  /// Deep link from `/knowledge/:id` — open straight into this article.
  final String? initialArticleId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => KnowledgeCubit(
      context.read<KnowledgeRepository>(),
      context.read<IssueRepository>(),
      context.read<UserRepository>(),
    ),
    child: _KnowledgeBody(initialArticleId: initialArticleId),
  );
}

class _KnowledgeBody extends StatefulWidget {
  const _KnowledgeBody({this.initialArticleId});

  final String? initialArticleId;

  @override
  State<_KnowledgeBody> createState() => _KnowledgeScreenState();
}

enum _Mode { home, article, edit, newDoc }

class _KnowledgeScreenState extends State<_KnowledgeBody> {
  late final KnowledgeCubit _knowledge = context.read<KnowledgeCubit>();

  // Shared app-wide store (provided in app.dart), read synchronously while
  // the page builds.
  late final KnowledgeRepository _store = _knowledge.store;
  bool _ready = false;

  // Real backend issues + member names so `{{issue:…}}` tokens and the `@`-menu
  // resolve against genuine issues (keyed by readable id), not seed data.
  Map<String, Issue> _issuesByReadable = const {};
  Map<String, String> _userNames = const {};

  _Mode _mode = _Mode.home;
  String? _selectedId;
  // Empty when the knowledge base has no spaces yet (fresh workspace); the
  // create-space flow sets it once the first space exists.
  late String _spaceId = _store.spaces.isNotEmpty ? _store.spaces.first.id : '';
  final _scrollKey = GlobalKey();

  // Reader panel collapse (desktop fullscreen reading) + pending parent for the
  // "new sub-page" create flow.
  bool _treeCollapsed = false;
  bool _asideCollapsed = false;
  String? _pendingParentId;

  /// A place change of the open page is on its way to the server.
  bool _placeBusy = false;

  /// The home's search. Kept here rather than in [KnowledgeHome] because a
  /// phone docks it in the app bar and a wide window draws it in the body, and
  /// the query must survive a resize across that line.
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The shared repo is init'd at app start; re-run is idempotent and ensures
    // persisted edits are overlaid before we gate the first frame.
    _knowledge.init().then((_) {
      if (!mounted) return;
      final initial = widget.initialArticleId;
      if (initial != null && _store.articleById(initial) != null) {
        final a = _store.articleById(initial)!;
        _selectedId = initial;
        _spaceId = a.spaceId;
        _mode = _Mode.article;
      }
      setState(() => _ready = true);
    });
    _loadBackendIssues();
  }

  /// Pulls real issues (across all visible projects) and member names so smart
  /// links and the `@`-mention menu resolve to genuine backend issues.
  Future<void> _loadBackendIssues() async {
    try {
      // allIssues pages through the whole backend result set so smart links and
      // the `@`-mention menu resolve against every issue, not just the first 100.
      final (:issues, :users) = await _knowledge.linkTargets();
      if (!mounted) return;
      setState(() {
        // Keyed by every id an issue ever carried, so a KB article linking a
        // moved issue under its old key keeps resolving.
        _issuesByReadable = {
          for (final i in issues)
            for (final key in i.allReadableIds) key: i,
        };
        _userNames = {for (final u in users) u.id: u.displayName};
      });
    } catch (_) {
      // Best-effort: the menu simply shows no issues until a retry/navigation.
    }
  }

  SmartLinkResolver _buildResolver() => KnowledgeLinkResolver(
    repo: _store,
    issuesByReadable: _issuesByReadable,
    stateColorFor: AppColors.stateColor,
    nameFor: (id) => id == null ? null : _userNames[id],
    onOpenArticle: _openArticle,
    onOpenIssue: _openRealIssue,
  );

  KbArticle? get _current =>
      _selectedId == null ? null : _store.articleById(_selectedId!);

  // ── navigation ──
  void _openArticle(String id) {
    final a = _store.articleById(id);
    if (a == null) return;
    setState(() {
      _selectedId = id;
      _spaceId = a.spaceId;
      _mode = _Mode.article;
    });
  }

  void _openSpace(String id) {
    // Roots include pages whose parent this person cannot read.
    final first = _store.rootsInSpace(id);
    setState(() {
      _spaceId = id;
      if (first.isNotEmpty) {
        _selectedId = first.first.id;
        _mode = _Mode.article;
      }
    });
  }

  /// Resolves a readable id (e.g. `HIV-208`) to the backend issue and opens the
  /// real issue sheet; toasts if there is no matching issue.
  Future<void> _openRealIssue(String readableId) async {
    try {
      final match = await _knowledge.findIssue(readableId);
      if (!mounted) return;
      if (match == null) {
        _toast('Issue $readableId not found', kind: GlassToastKind.error);
        return;
      }
      await showIssueDetailSheet(context, issueId: match.id);
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    }
  }

  void _home() => setState(() {
    _mode = _Mode.home;
    _selectedId = null;
  });

  // ── folder-style tree actions ─────────────────────────────────────────────

  /// Start a new sub-page under [parentId] (Confluence-style nesting).
  void _newChild(String parentId) {
    setState(() {
      _pendingParentId = parentId;
      _spaceId = _store.articleById(parentId)?.spaceId ?? _spaceId;
      _mode = _Mode.newDoc;
    });
  }

  Future<void> _moveArticle(
    String id, {
    String? parentId,
    required String spaceId,
  }) async {
    try {
      await _knowledge.moveArticle(id, parentId: parentId, spaceId: spaceId);
      if (mounted) setState(() => _spaceId = spaceId);
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    }
  }

  /// Moves the open top-level page, and everything below it, to [place].
  Future<void> _placeArticle(String id, KbPlaceChoice place) async {
    setState(() => _placeBusy = true);
    try {
      await _knowledge.placeArticle(
        id,
        projectId: place.projectId,
        teamId: place.teamId,
      );
      if (mounted) {
        _toast(
          context.t('knowledge.place.saved'),
          kind: GlassToastKind.success,
        );
      }
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    } finally {
      if (mounted) setState(() => _placeBusy = false);
    }
  }

  /// Confirms, then deletes [id]. Used by both the tree row menu and the
  /// reader's delete button so the destructive action always asks first.
  Future<void> _confirmDeleteArticle(String id) async {
    final article = _store.articleById(id);
    final confirmed = await showGlassConfirm(
      context,
      icon: lucideIcon('trash-2'),
      title: context.t('knowledge.deleteArticleTitle'),
      message: context.t(
        'knowledge.deleteArticleConfirm',
        variables: {'title': article?.title ?? ''},
      ),
      confirmLabel: context.t('knowledge.delete'),
      destructive: true,
      confirmIcon: lucideIcon('trash-2'),
    );
    if (confirmed == true) await _deleteArticle(id);
  }

  Future<void> _deleteArticle(String id) async {
    try {
      await _knowledge.deleteArticle(id);
      if (!mounted) return;
      setState(() {
        if (_selectedId == id) {
          _selectedId = null;
          _mode = _Mode.home;
        }
      });
      _toast(context.t('knowledge.deleted'), kind: GlassToastKind.success);
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    }
  }

  // ── space actions ─────────────────────────────────────────────────────────

  Future<void> _createSpace() async {
    final created = await showCreateSpaceDialog(
      context,
      onCreate:
          ({
            required String name,
            required String icon,
            required int hue,
            required String description,
          }) async {
            try {
              final space = await _knowledge.createSpace(
                name: name,
                icon: icon,
                hue: hue,
                description: description,
              );
              if (mounted) _spaceId = space.id;
              return null;
            } on ApiFailure catch (failure) {
              return failure.message;
            }
          },
    );
    if (created != null && mounted) {
      setState(() {});
      _toast(context.t('knowledge.spaceCreated'), kind: GlassToastKind.success);
    }
  }

  Future<void> _deleteSpace(String id) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: lucideIcon('trash-2'),
      title: context.t('knowledge.deleteSpaceTitle'),
      message: context.t(
        'knowledge.deleteSpaceConfirm',
        variables: {'name': id},
      ),
      confirmLabel: context.t('knowledge.delete'),
      destructive: true,
      confirmIcon: lucideIcon('trash-2'),
    );
    if (confirmed != true) return;
    try {
      await _knowledge.deleteSpace(id);
      if (!mounted) return;
      setState(() {});
      _toast(context.t('knowledge.spaceDeleted'), kind: GlassToastKind.success);
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    }
  }

  Future<void> _save(EditorResult r) async {
    final title = r.title.trim().isEmpty
        ? context.t('knowledge.untitled')
        : r.title.trim();
    try {
      if (_mode == _Mode.newDoc) {
        final parentId = _pendingParentId;
        final a = await _knowledge.createArticle(
          title: title,
          doc: r.doc,
          spaceId: r.spaceId,
          parentId: parentId,
          projectId: r.projectId,
          teamId: r.teamId,
        );
        if (!mounted) return;
        setState(() {
          _pendingParentId = null;
          _selectedId = a.id;
          _spaceId = a.spaceId;
          _mode = _Mode.article;
        });
        _toast(context.t('knowledge.published'), kind: GlassToastKind.success);
      } else if (_current != null) {
        await _knowledge.saveEdit(
          _current!.id,
          title: title,
          doc: r.doc,
          spaceId: r.spaceId,
        );
        if (!mounted) return;
        setState(() => _mode = _Mode.article);
        _toast(context.t('knowledge.saved'), kind: GlassToastKind.success);
      }
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    }
  }

  void _toast(String msg, {GlassToastKind kind = GlassToastKind.info}) =>
      showGlassToast(context, context.t(msg), kind: kind);

  void _openTreeDrawer() {
    showGlassBottomSheet<void>(
      context,
      builder: (sheetCtx) => SizedBox(
        height: MediaQuery.sizeOf(sheetCtx).height * 0.7,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: KnowledgeTree(
            repo: _store,
            spaceId: _spaceId,
            selectedId: _selectedId,
            onSelect: (id) {
              Navigator.of(sheetCtx).pop();
              _openArticle(id);
            },
            onSpaceChange: (id) {
              Navigator.of(sheetCtx).pop();
              _openSpace(id);
            },
            onNewChild: (pid) {
              Navigator.of(sheetCtx).pop();
              _newChild(pid);
            },
            onMove: _moveArticle,
            onDelete: _confirmDeleteArticle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(40), child: HiveLoader()),
      );
    }
    // On the deep-link sub-route (/knowledge/:id) the shell paints a back +
    // title bar; publish the open article's title so it doesn't just repeat
    // the in-page "knowledge.title" head.
    final chromeTitle = _mode == _Mode.article
        ? (_current?.title ?? context.t('knowledge.title'))
        : context.t('knowledge.title');
    final compact = context.isCompact;
    final editing = _mode == _Mode.edit || _mode == _Mode.newDoc;
    final dockSearch = compact && _mode == _Mode.home;
    return PageChrome(
      title: chromeTitle,
      // A phone's bar has room for one action, and the page's one is a new
      // article. The editor brings its own back and save, so it has none.
      actions: compact && !editing
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('knowledge.newArticle'),
                primary: true,
                onTap: _newArticle,
              ),
            ]
          : const [],
      // The search rides in the bar's blur as a pill, the way it does on the
      // projects page; as a full-width field down the page it was a third row
      // under a title the bar already showed.
      bottom: dockSearch ? _dockedSearch(context) : null,
      bottomHeight: dockSearch ? kGlassDockRow : 0,
      child: KnowledgeScope(
        repo: _store,
        openArticle: _openArticle,
        openUser: (_) {},
        child: SmartLinkScope(
          resolver: _buildResolver(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final bp = w < KbTokens.bpMid
                  ? _Bp.narrow
                  : w < KbTokens.bpWide
                  ? _Bp.mid
                  : _Bp.wide;
              if (_mode == _Mode.edit || _mode == _Mode.newDoc) {
                return _editorView(constraints.maxHeight);
              }
              return _mainView(bp);
            },
          ),
        ),
      ),
    );
  }

  Widget _head() {
    return PageHead(
      title: context.t('knowledge.title'),
      subtitle: context.t(
        'knowledge.subtitle',
        variables: {
          'articles': '${_store.articles.length}',
          'spaces': '${_store.spaces.length}',
        },
      ),
      actions: [
        if (_mode != _Mode.home)
          GhostButton(
            label: context.t('knowledge.allSpaces'),
            icon: lucideIcon('layout-grid'),
            onPressed: _home,
            collapseToIcon: true,
          ),
        PrimaryButton(
          label: context.t('knowledge.newArticle'),
          icon: lucideIcon('plus'),
          onPressed: () => _newArticle(null),
          collapseToIcon: true,
        ),
      ],
    );
  }

  /// A tear-off for the bar's action, so it compares equal from one build to
  /// the next and the chrome is not re-published every frame.
  void _newArticle(Rect? _) => setState(() {
    _pendingParentId = null;
    _mode = _Mode.newDoc;
  });

  /// The phone's one docked row: the search pill, which takes the row over
  /// while somebody types and hands it back on close.
  Widget _dockedSearch(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
    // The bar hands the reserved height down as a tight constraint; the Align
    // lets the pill come in under it.
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: GlassSearchDock(
        searching: _searching,
        controller: _search,
        hint: context.t('knowledge.searchHint'),
        onChanged: (value) => setState(() => _query = value),
        onClose: () => setState(() => _searching = false),
        controls: SizedBox(
          height: kGlassControlHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: GlassSearchButton(
              tooltip: context.t('knowledge.searchHint'),
              active: _query.isNotEmpty,
              onTap: () => setState(() => _searching = true),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mainView(_Bp bp) {
    final showTree = _mode == _Mode.article && bp != _Bp.narrow;
    final compact = context.isCompact;
    return SingleChildScrollView(
      key: _scrollKey,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        (compact ? context.pageGutter : 24) + context.topGutter,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // On a phone the bar names the page and carries "New article", so
          // the body does not say either again. Inside an article the way back
          // to all spaces still needs a place, and the bar has no room for it.
          if (!compact) ...[
            _head(),
            const SizedBox(height: 20),
          ] else if (_mode != _Mode.home) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GhostButton(
                label: context.t('knowledge.allSpaces'),
                icon: lucideIcon('layout-grid'),
                onPressed: _home,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_mode == _Mode.home)
            KnowledgeHome(
              repo: _store,
              search: _search,
              query: _query,
              onQueryChanged: (value) => setState(() => _query = value),
              showSearchField: !compact,
              onOpenArticle: _openArticle,
              onOpenSpace: _openSpace,
              onNewSpace: _createSpace,
              onDeleteSpace: _deleteSpace,
            )
          else if (_current != null)
            _articleLayout(bp, showTree),
        ],
      ),
    );
  }

  Widget _articleLayout(_Bp bp, bool showTree) {
    // Aside collapses to none when the user wants a wider/fullscreen read.
    final asideMode = _asideCollapsed
        ? AsideMode.none
        : switch (bp) {
            _Bp.wide => AsideMode.side,
            _Bp.mid => AsideMode.below,
            _Bp.narrow => AsideMode.none,
          };
    final reader = KnowledgeReader(
      // Keyed by article: without it Flutter reuses the same State across a
      // navigation, and everything the reader derived from the *previous*
      // document — outline, linked issues, the active heading — starts out
      // pointing at a document that is no longer on screen.
      key: ValueKey(_current!.id),
      article: _current!,
      asideMode: asideMode,
      onEdit: () => setState(() => _mode = _Mode.edit),
      onDelete: () => _confirmDeleteArticle(_current!.id),
      onPlace: (place) => _placeArticle(_current!.id, place),
      placeBusy: _placeBusy,
    );

    if (!showTree) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // narrow bar with tree drawer trigger
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              // The space name inside names the drawer trigger.
              child: Semantics(
                button: true,
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                    onTap: _openTreeDrawer,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          KbTokens.radiusControl,
                        ),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            lucideIcon('panel-left'),
                            size: 16,
                            color: AppColors.inkSoft,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _store.spaceById(_spaceId)?.name ?? '',
                            style: const TextStyle(
                              fontSize: AppType.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          reader,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_treeCollapsed) ...[
          SizedBox(
            width: KbTokens.treeWidth,
            child: KnowledgeTree(
              repo: _store,
              spaceId: _spaceId,
              selectedId: _selectedId,
              onSelect: _openArticle,
              onSpaceChange: _openSpace,
              onNewChild: _newChild,
              onMove: _moveArticle,
              onDelete: _confirmDeleteArticle,
            ),
          ),
          const SizedBox(width: 28),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_readerControls(bp), const SizedBox(height: 4), reader],
          ),
        ),
      ],
    );
  }

  /// Collapse/expand controls flanking the reader: the left "pages" toggle sits
  /// on the left edge (next to the tree it hides), the right "details" toggle on
  /// the right edge (next to the aside) — so an article can be read full-bleed.
  Widget _readerControls(_Bp bp) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _PanelToggle(
          icon: _treeCollapsed
              ? LucideIcons.panelLeftOpen
              : LucideIcons.panelLeftClose,
          tooltip: context.t(
            _treeCollapsed ? 'knowledge.showPages' : 'knowledge.hidePages',
          ),
          onTap: () => setState(() => _treeCollapsed = !_treeCollapsed),
        ),
        // Right edge: only the wide layout has a side aside to collapse.
        if (bp == _Bp.wide)
          _PanelToggle(
            icon: _asideCollapsed
                ? LucideIcons.panelRightOpen
                : LucideIcons.panelRightClose,
            tooltip: context.t(
              _asideCollapsed
                  ? 'knowledge.showDetails'
                  : 'knowledge.hideDetails',
            ),
            onTap: () => setState(() => _asideCollapsed = !_asideCollapsed),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _editorView(double maxHeight) {
    final isNew = _mode == _Mode.newDoc;
    final current = _current;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        16 + context.topGutter,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: context.t('common.back'),
                child: Semantics(
                  button: true,
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        KbTokens.radiusControl,
                      ),
                      onTap: () => setState(() {
                        _pendingParentId = null;
                        _mode = isNew ? _Mode.home : _Mode.article;
                      }),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            KbTokens.radiusControl,
                          ),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Icon(
                          lucideIcon('arrow-left'),
                          size: 18,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isNew
                    ? context.t('knowledge.newArticle')
                    : context.t('knowledge.editing'),
                style: const TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: AppType.title,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: KnowledgeEditor(
              isNew: isNew,
              initialTitle: isNew ? '' : current?.title ?? '',
              initialDoc: isNew ? null : current?.doc,
              // The legacy markdown, so a row the backfill skipped opens with
              // its content rather than blank over it.
              initialBody: isNew ? '' : current?.body ?? '',
              spaceId: _spaceId,
              // A new top-level page chooses where it lives (only its author
              // by default); a subpage lives where its parent lives.
              choosePlace: isNew && _pendingParentId == null,
              onSave: _save,
              onCancel: () => setState(() {
                _pendingParentId = null;
                _mode = isNew ? _Mode.home : _Mode.article;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Bp { narrow, mid, wide }

/// Compact bordered icon button used by the reader's panel-collapse controls.
class _PanelToggle extends StatelessWidget {
  const _PanelToggle({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        // The outer detector catches the 7-point ring around the 34-point
        // face, which brings the target to 48×48; a tap on the face itself is
        // won by the InkWell below, so it fires once and still ripples.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(KbTokens.radiusControl),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Icon(icon, size: 17, color: AppColors.inkSoft),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
