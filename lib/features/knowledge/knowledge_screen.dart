import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart' show ArticleVersion;
import '../../core/models/moderation_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_filter_bar.dart'
    show GlassSearchButton, GlassSearchDock, kGlassControlHeight, kGlassDockRow;
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../moderation/report/report_sheet.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassBottomSheet, showGlassConfirm, showGlassToast;
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_cubit.dart';
import 'knowledge_debouncer.dart';
import 'knowledge_editor.dart';
import 'knowledge_link_resolver.dart';
import 'knowledge_location.dart';
import 'knowledge_place_field.dart';
import 'knowledge_reader.dart';
import 'knowledge_scope.dart';
import 'knowledge_space_dialog.dart';
import 'knowledge_state.dart';
import 'knowledge_tokens.dart';
import 'knowledge_tree.dart';
import 'markdown/smart_link_resolver.dart';
import 'views/knowledge_history_view.dart';
import 'views/knowledge_home_view.dart';
import 'views/knowledge_space_view.dart';
import 'widgets/knowledge_widgets.dart' show KbLabelPill;

/// The knowledge base: a start page, a page per space, pages to read, edit
/// and look back through. What is on screen follows [location], which the
/// router reads from the address; moving around goes through the router too,
/// so back, reload and a shared link all land where the reader was.
///
/// Every knowledge route is built with the same page key, so moving between
/// them keeps this screen and its state — the open search, a collapsed tree —
/// instead of building a new one per address.
class KnowledgeScreen extends StatelessWidget {
  const KnowledgeScreen({super.key, required this.location});

  final KnowledgeLocation location;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => KnowledgeCubit(
      context.read<KnowledgeRepository>(),
      context.read<IssueRepository>(),
    )..load(),
    child: _KnowledgeBody(location: location),
  );
}

class _KnowledgeBody extends StatefulWidget {
  const _KnowledgeBody({required this.location});

  final KnowledgeLocation location;

  @override
  State<_KnowledgeBody> createState() => _KnowledgeBodyState();
}

enum _Bp { narrow, mid, wide }

class _KnowledgeBodyState extends State<_KnowledgeBody> {
  late final KnowledgeCubit _knowledge = context.read<KnowledgeCubit>();
  KnowledgeRepository get _store => _knowledge.store;

  KnowledgeLocation get _at => widget.location;

  // ── home search ──
  /// Kept here rather than in the home view because a phone docks it in the
  /// app bar and a wide window draws it in the body, and the query must survive
  /// a resize across that line.
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  /// Typing settles before the search runs; a cleared field shows the
  /// start page at once.
  final KbDebouncer _queryDebounce = KbDebouncer();

  // ── reading ──
  bool _treeCollapsed = false;
  bool _asideCollapsed = false;
  bool _placeBusy = false;

  /// Who worked on each page opened this visit, by page id.
  final Map<String, List<String>> _contributors = {};

  /// The page whose opening was last recorded, so a rebuild records nothing.
  String? _viewed;

  // ── space ──
  /// The label a space's list is narrowed to, by space.
  final Map<String, String> _labelFilter = {};

  // ── editing ──
  /// The open editor; a new one per address, so "new under A" and "new
  /// under B" are two drafts rather than one carried over.
  GlobalKey<KnowledgeEditorState> _editor = GlobalKey();
  bool _dirty = false;
  bool _saving = false;

  /// What the text check refused in the last save (HIN-176); the editor keeps
  /// the page and shows why.
  ContentRefusal? _refusal;

  // ── history ──
  PagedCubit<ArticleVersion>? _versions;
  String? _versionsOf;

  @override
  void initState() {
    super.initState();
    _arrived();
  }

  @override
  void didUpdateWidget(_KnowledgeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _dirty = false;
      _editor = GlobalKey();
      _arrived();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _queryDebounce.dispose();
    _versions?.close();
    super.dispose();
  }

  /// What a new address asks for beyond drawing it: noting the open page,
  /// fetching who worked on it, the history's first page.
  void _arrived() {
    switch (_at) {
      case KnowledgeArticleLocation(:final articleId):
        _opened(articleId);
      case KnowledgeHistoryLocation(:final articleId):
        _historyOf(articleId);
      default:
        break;
    }
  }

  void _opened(String id) {
    if (_viewed == id) return;
    // Wait for the pages: a deep link arrives before they are loaded.
    if (_knowledge.state.status != KnowledgeStatus.ready) return;
    if (_store.articleById(id) == null) return;
    _viewed = id;
    _knowledge.recordView(id);
    _knowledge.contributors(id).then((ids) {
      if (mounted) setState(() => _contributors[id] = ids);
    }, onError: (_) {});
  }

  /// Opens the version list of [id]. Called when an address is reached, never
  /// while building: it starts a request.
  void _historyOf(String id) {
    if (_versionsOf == id) return;
    _versions?.close();
    _versionsOf = id;
    _versions = PagedCubit<ArticleVersion>(
      (page, size) => _knowledge.versions(id, page: page, size: size),
      pageSize: 20,
      keyOf: (v) => '${v.number}',
    )..load();
  }

  // ── navigation ──

  void _go(KnowledgeLocation to) {
    // A refusal belongs to the page it was about.
    _refusal = null;
    context.go(to.path);
  }

  void _openArticle(String id) => _go(KnowledgeArticleLocation(id));
  void _openSpace(String id) => _go(KnowledgeSpaceLocation(id));

  /// Where back leads from here: up the page tree, then to the space, then
  /// home. An editor with unsaved changes asks first.
  Future<void> _back() async {
    switch (_at) {
      case KnowledgeHomeLocation():
        return;
      case KnowledgeSpaceLocation():
        _go(const KnowledgeHomeLocation());
      case KnowledgeArticleLocation(:final articleId):
        final a = _store.articleById(articleId);
        if (a?.parentId case final parent?
            when _store.articleById(parent) != null) {
          _openArticle(parent);
        } else if (a != null && a.spaceId.isNotEmpty) {
          _openSpace(a.spaceId);
        } else {
          _go(const KnowledgeHomeLocation());
        }
      case KnowledgeEditLocation(:final articleId):
        if (await _mayLeaveEditor()) _openArticle(articleId);
      case KnowledgeNewLocation(:final spaceId, :final parentId):
        if (!await _mayLeaveEditor()) return;
        if (parentId != null) {
          _openArticle(parentId);
        } else if (spaceId != null && _store.spaceById(spaceId) != null) {
          _openSpace(spaceId);
        } else {
          _go(const KnowledgeHomeLocation());
        }
      case KnowledgeHistoryLocation(:final articleId, :final version):
        // A phone shows one version at a time; back returns to the list.
        if (version != null && context.isCompact) {
          _go(KnowledgeHistoryLocation(articleId));
        } else {
          _openArticle(articleId);
        }
    }
  }

  Future<bool> _mayLeaveEditor() async {
    if (!_dirty) return true;
    final ok = await showGlassConfirm(
      context,
      icon: LucideIcons.fileWarning,
      title: context.t('knowledge.editor.discardTitle'),
      message: context.t('knowledge.editor.discardMessage'),
      confirmLabel: context.t('knowledge.editor.discard'),
      destructive: true,
    );
    return ok == true;
  }

  // ── writes ──

  void _toast(String msg, {GlassToastKind kind = GlassToastKind.info}) =>
      showGlassToast(context, context.t(msg), kind: kind);

  Future<void> _attempt(Future<void> Function() write) async {
    try {
      await write();
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    }
  }

  Future<void> _save(EditorResult r) async {
    if (_saving) return;
    final title = r.title.trim().isEmpty
        ? context.t('knowledge.untitled')
        : r.title.trim();
    setState(() {
      _saving = true;
      _refusal = null;
    });
    try {
      switch (_at) {
        case KnowledgeNewLocation(:final parentId):
          final a = await _knowledge.createArticle(
            title: title,
            doc: r.doc,
            spaceId: r.spaceId,
            parentId: parentId,
            projectId: r.projectId,
            teamId: r.teamId,
            organization: r.organization,
            labels: r.labels,
          );
          if (!mounted) return;
          _dirty = false;
          _toast('knowledge.published', kind: GlassToastKind.success);
          _openArticle(a.id);
        case KnowledgeEditLocation(:final articleId):
          await _knowledge.saveEdit(
            articleId,
            title: title,
            doc: r.doc,
            spaceId: r.spaceId,
            labels: r.labels,
          );
          if (!mounted) return;
          _dirty = false;
          _contributors.remove(articleId);
          _viewed = null;
          _toast('knowledge.saved', kind: GlassToastKind.success);
          _openArticle(articleId);
        default:
          break;
      }
    } on ApiFailure catch (failure) {
      final refusal = ContentRefusal.of(failure);
      if (!mounted) return;
      if (refusal != null) {
        setState(() => _refusal = refusal);
      } else {
        _toast(failure.message, kind: GlassToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _move(String id, {String? parentId, required String spaceId}) =>
      _attempt(
        () => _knowledge.moveArticle(id, parentId: parentId, spaceId: spaceId),
      );

  Future<void> _shift(String id, int delta) =>
      _attempt(() => _knowledge.shift(id, delta));

  Future<void> _place(String id, KbPlaceChoice place) async {
    setState(() => _placeBusy = true);
    try {
      await _knowledge.placeArticle(
        id,
        projectId: place.projectId,
        teamId: place.teamId,
        organization: place.organization,
      );
      if (mounted) {
        _toast('knowledge.place.saved', kind: GlassToastKind.success);
      }
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    } finally {
      if (mounted) setState(() => _placeBusy = false);
    }
  }

  Future<void> _toggleStar(String id) async {
    final starred = !_store.isStarred(id);
    await _attempt(() => _knowledge.setStarred(id, starred: starred));
  }

  /// Confirms, then deletes [id]. The tree and the page menu both go here,
  /// so the destructive action always asks first.
  Future<void> _confirmDelete(String id) async {
    final article = _store.articleById(id);
    if (article == null) return;
    if (_store.childrenOf(id).isNotEmpty) {
      _toast('knowledge.deleteHasChildren', kind: GlassToastKind.error);
      return;
    }
    final confirmed = await showGlassConfirm(
      context,
      icon: lucideIcon('trash-2'),
      title: context.t('knowledge.deleteArticleTitle'),
      message: context.t(
        'knowledge.deleteArticleConfirm',
        variables: {'title': article.title},
      ),
      confirmLabel: context.t('knowledge.delete'),
      destructive: true,
      confirmIcon: lucideIcon('trash-2'),
    );
    if (confirmed != true || !mounted) return;
    await _attempt(() async {
      await _knowledge.deleteArticle(id);
      if (!mounted) return;
      _toast('knowledge.deleted', kind: GlassToastKind.success);
      final open = switch (_at) {
        KnowledgeArticleLocation(:final articleId) => articleId,
        _ => null,
      };
      if (open == id) {
        article.parentId != null &&
                _store.articleById(article.parentId!) != null
            ? _openArticle(article.parentId!)
            : _openSpace(article.spaceId);
      }
    });
  }

  Future<void> _restore(String id, int number) async {
    final ok = await showGlassConfirm(
      context,
      icon: LucideIcons.history,
      title: context.t('knowledge.history.restoreTitle'),
      message: context.t(
        'knowledge.history.restoreMessage',
        variables: {'number': '$number'},
      ),
      confirmLabel: context.t('knowledge.history.restore'),
    );
    if (ok != true || !mounted) return;
    await _attempt(() async {
      await _knowledge.restoreVersion(id, number);
      if (!mounted) return;
      _contributors.remove(id);
      // The restored state is the newest version now.
      _versions?.load();
      _toast('knowledge.history.restored', kind: GlassToastKind.success);
      _openArticle(id);
    });
  }

  Future<void> _copyLink(String id) async {
    final base = Uri.base;
    final link =
        base.hasAuthority && (base.scheme == 'http' || base.scheme == 'https')
        ? base
              .replace(
                path: KnowledgePaths.article(id),
                query: null,
                fragment: null,
              )
              .toString()
        : KnowledgePaths.article(id);
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      _toast('knowledge.reader.linkCopied', kind: GlassToastKind.success);
    }
  }

  // ── spaces ──

  Future<void> _createSpace() async {
    String? createdId;
    final created = await showCreateSpaceDialog(
      context,
      onCreate:
          ({
            required name,
            required icon,
            required hue,
            required description,
          }) async {
            try {
              createdId = (await _knowledge.createSpace(
                name: name,
                icon: icon,
                hue: hue,
                description: description,
              )).id;
              return null;
            } on ApiFailure catch (failure) {
              return failure.message;
            }
          },
    );
    if (created != null && createdId != null && mounted) {
      _toast('knowledge.spaceCreated', kind: GlassToastKind.success);
      _openSpace(createdId!);
    }
  }

  Future<void> _editSpace(KbSpace space) async {
    String? renamed;
    final saved = await showCreateSpaceDialog(
      context,
      editing: space,
      onCreate:
          ({
            required name,
            required icon,
            required hue,
            required description,
          }) async {
            try {
              renamed = (await _knowledge.updateSpace(
                space.id,
                name: name,
                icon: icon,
                hue: hue,
                description: description,
              )).id;
              return null;
            } on ApiFailure catch (failure) {
              return failure.message;
            }
          },
    );
    if (saved != null && mounted) {
      _toast('knowledge.spaceSaved', kind: GlassToastKind.success);
      if (renamed != null && renamed != space.id) _openSpace(renamed!);
    }
  }

  Future<void> _deleteSpace(KbSpace space) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: lucideIcon('trash-2'),
      title: context.t('knowledge.deleteSpaceTitle'),
      message: context.t(
        'knowledge.deleteSpaceConfirm',
        variables: {'name': space.name},
      ),
      confirmLabel: context.t('knowledge.delete'),
      destructive: true,
      confirmIcon: lucideIcon('trash-2'),
    );
    if (confirmed != true || !mounted) return;
    await _attempt(() async {
      await _knowledge.deleteSpace(space.id);
      if (!mounted) return;
      _toast('knowledge.spaceDeleted', kind: GlassToastKind.success);
      _go(const KnowledgeHomeLocation());
    });
  }

  // ── menus ──

  /// Somebody else's page that is still there, on a server that knows
  /// reporting (HIN-173).
  bool _reportable(KbArticle a) => canReport(
    context,
    authorId: a.authorId,
    removed: a.isRemoved('title') && a.isRemoved('content'),
  );

  Future<void> _report(KbArticle a, Rect anchor) => showReportSheet(
    context,
    anchorRect: anchor,
    subject: ReportSubject(
      target: TargetRef(ContentKind.article, a.id),
      title: context.t('moderation.report.titleArticle'),
      subtitle: a.title,
    ),
  );

  Future<void> _pageMenu(KbArticle a, Rect? anchor) async {
    final rect = anchor ?? _fallbackAnchor();
    final canDelete = _store.childrenOf(a.id).isEmpty;
    final reportable = _reportable(a);
    final chosen = await showGlassMenu<String>(
      context: context,
      anchorRect: rect,
      value: '',
      items: [
        GlassMenuItem(
          value: 'history',
          label: context.t('knowledge.history.open'),
          leading: Icon(
            LucideIcons.history,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
        GlassMenuItem(
          value: 'child',
          label: context.t('knowledge.addSubPage'),
          leading: Icon(
            LucideIcons.filePlus,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
        GlassMenuItem(
          value: 'link',
          label: context.t('knowledge.reader.copyLink'),
          leading: Icon(LucideIcons.link, size: 16, color: AppColors.inkSoft),
        ),
        if (reportable)
          GlassMenuItem(
            value: 'report',
            dividerAbove: true,
            label: context.t('moderation.report.action'),
            leading: Icon(LucideIcons.flag, size: 16, color: AppColors.inkSoft),
          ),
        GlassMenuItem(
          value: 'delete',
          dividerAbove: true,
          enabled: canDelete,
          label: context.t(
            canDelete ? 'knowledge.delete' : 'knowledge.deleteHasChildren',
          ),
          color: AppColors.danger,
          leading: Icon(
            lucideIcon('trash-2'),
            size: 16,
            color: AppColors.danger,
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (chosen) {
      case 'history':
        _go(KnowledgeHistoryLocation(a.id));
      case 'child':
        _go(KnowledgeNewLocation(spaceId: a.spaceId, parentId: a.id));
      case 'link':
        await _copyLink(a.id);
      case 'report':
        await _report(a, rect);
      case 'delete':
        await _confirmDelete(a.id);
    }
  }

  Future<void> _spaceMenu(KbSpace space, Rect? anchor) async {
    final manage = _store.canManageSpace(space.id);
    final empty = _store.articleCountInSpace(space.id) == 0;
    final chosen = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor ?? _fallbackAnchor(),
      value: '',
      items: [
        GlassMenuItem(
          value: 'edit',
          enabled: manage,
          disabledReason: manage
              ? null
              : context.t('knowledge.spaceView.notYours'),
          label: context.t('knowledge.editSpace'),
          leading: Icon(LucideIcons.pencil, size: 16, color: AppColors.inkSoft),
        ),
        GlassMenuItem(
          value: 'delete',
          dividerAbove: true,
          enabled: manage && empty,
          disabledReason: !manage
              ? context.t('knowledge.spaceView.notYours')
              : empty
              ? null
              : context.t('knowledge.spaceView.notEmpty'),
          label: context.t('knowledge.deleteSpace'),
          color: AppColors.danger,
          leading: Icon(
            lucideIcon('trash-2'),
            size: 16,
            color: AppColors.danger,
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (chosen) {
      case 'edit':
        await _editSpace(space);
      case 'delete':
        await _deleteSpace(space);
    }
  }

  Rect _fallbackAnchor() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(
      size.width - 60,
      MediaQuery.paddingOf(context).top + 8,
      44,
      44,
    );
  }

  void _openTreeSheet(KbArticle a) {
    showGlassBottomSheet<void>(
      context,
      builder: (sheetCtx) {
        // Closes this sheet even while a row's action menu still sits above
        // it: the menu answers as it starts folding away, and a plain pop
        // would close the menu and leave the sheet over the page it opened.
        void close() {
          final sheet = ModalRoute.of(sheetCtx);
          final navigator = Navigator.of(sheetCtx);
          if (sheet == null || !sheet.isActive) return;
          navigator.popUntil((route) => route == sheet);
          navigator.pop();
        }

        return SizedBox(
          height: MediaQuery.sizeOf(sheetCtx).height * 0.72,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            // The sheet is a route of its own, outside the page's builder:
            // without this a move or a reorder changed the pages but not the
            // tree on screen.
            child: BlocBuilder<KnowledgeCubit, KnowledgeState>(
              bloc: _knowledge,
              buildWhen: (a, b) => a.revision != b.revision,
              builder: (_, _) => KnowledgeTree(
                repo: _store,
                spaceId: a.spaceId,
                selectedId: a.id,
                onOpenSpace: () {
                  close();
                  _openSpace(a.spaceId);
                },
                onSelect: (id) {
                  close();
                  _openArticle(id);
                },
                onNewChild: (pid) {
                  close();
                  _go(KnowledgeNewLocation(spaceId: a.spaceId, parentId: pid));
                },
                onMove: _move,
                onShift: _shift,
                onDelete: _confirmDelete,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── build ──

  SmartLinkResolver _resolver(KnowledgeState state) => KnowledgeLinkResolver(
    repo: _store,
    issuesByReadable: state.issuesByReadable,
    stateColorFor: AppColors.stateColor,
    nameFor: (id) => id == null ? null : state.userNames[id],
    onOpenArticle: _openArticle,
    onOpenIssue: _openIssue,
  );

  Future<void> _openIssue(String readableId) async {
    try {
      final match = await _knowledge.findIssue(readableId);
      if (!mounted) return;
      if (match == null) {
        _toast(
          context.t('knowledge.issueNotFound', variables: {'id': readableId}),
          kind: GlassToastKind.error,
        );
        return;
      }
      await showIssueDetailSheet(context, issueId: match.id);
    } on ApiFailure catch (failure) {
      if (mounted) _toast(failure.message, kind: GlassToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<KnowledgeCubit, KnowledgeState>(
      listenWhen: (a, b) =>
          a.status != b.status && b.status == KnowledgeStatus.ready,
      // A deep link to a page arrives before the pages; note it once they are in.
      listener: (context, _) => _arrived(),
      builder: (context, state) {
        switch (state.status) {
          case KnowledgeStatus.loading when state.revision == 0:
            return PageChrome(
              title: context.t('knowledge.title'),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: HiveLoader(),
                ),
              ),
            );
          case KnowledgeStatus.failure:
            return PageChrome(
              title: context.t('knowledge.title'),
              child: _scroll(
                HiveEmptyState(
                  title: context.t('knowledge.loadFailedTitle'),
                  message: context.t('knowledge.loadFailedMessage'),
                  action: PrimaryButton(
                    label: context.t('common.retry'),
                    icon: LucideIcons.refreshCw,
                    onPressed: _knowledge.reload,
                  ),
                ),
              ),
            );
          default:
            return KnowledgeScope(
              repo: _store,
              openArticle: _openArticle,
              openUser: (_) {},
              child: SmartLinkScope(
                resolver: _resolver(state),
                child: _located(context),
              ),
            );
        }
      },
    );
  }

  Widget _located(BuildContext context) => switch (_at) {
    KnowledgeHomeLocation() => _home(context),
    KnowledgeSpaceLocation(:final spaceId) => _space(context, spaceId),
    KnowledgeArticleLocation(:final articleId) => _article(context, articleId),
    KnowledgeEditLocation(:final articleId) => _edit(context, articleId),
    KnowledgeNewLocation(:final spaceId, :final parentId) => _create(
      context,
      spaceId,
      parentId,
    ),
    KnowledgeHistoryLocation(:final articleId, :final version) => _history(
      context,
      articleId,
      version,
    ),
  };

  /// The page's scroll: gutters inside it, so content runs under the glass bars.
  Widget _scroll(Widget child, {double top = 24}) {
    final compact = context.isCompact;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        (compact ? context.pageGutter : top) + context.topGutter,
        context.pageGutter,
        context.pageGutter + context.bottomGutter + 24,
      ),
      child: child,
    );
  }

  Widget _missing(BuildContext context, String titleKey) => PageChrome(
    title: context.t('knowledge.title'),
    onBack: () => _go(const KnowledgeHomeLocation()),
    child: _scroll(
      HiveEmptyState(
        title: context.t(titleKey),
        message: context.t('knowledge.notFoundMessage'),
        action: GhostButton(
          label: context.t('knowledge.allSpaces'),
          icon: LucideIcons.layoutGrid,
          onPressed: () => _go(const KnowledgeHomeLocation()),
        ),
      ),
    ),
  );

  // ── home ──

  Widget _home(BuildContext context) {
    final compact = context.isCompact;
    return PageChrome(
      title: context.t('knowledge.title'),
      actions: compact
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('knowledge.newArticle'),
                primary: true,
                onTap: _newPageAction,
              ),
            ]
          : const [],
      bottom: compact ? _dockedSearch(context) : null,
      bottomHeight: compact ? kGlassDockRow : 0,
      child: _scroll(
        KnowledgeHomeView(
          repo: _store,
          search: _search,
          query: _query,
          onQueryChanged: _onQueryChanged,
          wide: !compact,
          onOpenArticle: _openArticle,
          onOpenSpace: _openSpace,
          onNewSpace: _createSpace,
          onNewPage: () => _newPageAction(null),
        ),
      ),
    );
  }

  void _onQueryChanged(String value) => _queryDebounce.run(() {
    if (mounted) setState(() => _query = value);
  }, immediately: value.trim().isEmpty);

  /// A tear-off for the bar's action, so it compares equal between builds.
  void _newPageAction(Rect? _) => _go(const KnowledgeNewLocation());

  Widget _dockedSearch(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: GlassSearchDock(
        searching: _searching,
        controller: _search,
        hint: context.t('knowledge.searchHint'),
        onChanged: _onQueryChanged,
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

  // ── space ──

  Widget _space(BuildContext context, String spaceId) {
    final space = _store.spaceById(spaceId);
    if (space == null) return _missing(context, 'knowledge.spaceNotFound');
    final compact = context.isCompact;
    final labels = _store.labels(spaceId: space.id);
    void newPage([Rect? _]) => _go(KnowledgeNewLocation(spaceId: space.id));
    return PageChrome(
      title: space.name,
      onBack: _back,
      onTitleTap: compact ? (rect) => _spaceMenu(space, rect) : null,
      actions: [
        if (!compact)
          PageAction(
            icon: LucideIcons.ellipsis,
            label: context.t('knowledge.spaceView.actions'),
            onTap: (rect) => _spaceMenu(space, rect),
          ),
        PageAction(
          icon: LucideIcons.plus,
          label: context.t('knowledge.newArticle'),
          primary: true,
          onTap: newPage,
        ),
      ],
      bottom: compact && labels.isNotEmpty
          ? _dockedLabels(space, labels)
          : null,
      bottomHeight: compact && labels.isNotEmpty ? kGlassDockRow : 0,
      child: _scroll(
        KnowledgeSpaceView(
          repo: _store,
          space: space,
          wide: !compact,
          label: _labelFilter[space.id],
          onLabel: (label) => setState(() {
            label == null
                ? _labelFilter.remove(space.id)
                : _labelFilter[space.id] = label;
          }),
          onOpenArticle: _openArticle,
          onNewPage: newPage,
          onNewChild: (pid) =>
              _go(KnowledgeNewLocation(spaceId: space.id, parentId: pid)),
          onMove: _move,
          onShift: _shift,
          onDelete: _confirmDelete,
        ),
      ),
    );
  }

  /// A phone's one docked row on a space: its labels as glass pills, the
  /// row scrolling sideways when they do not fit.
  Widget _dockedLabels(
    KbSpace space,
    List<({String label, int count})> labels,
  ) {
    final current = _labelFilter[space.id];
    return SizedBox(
      height: kGlassDockRow,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final l = labels[i];
          return Center(
            child: KbLabelPill(
              label: l.label,
              count: l.count,
              selected: l.label == current,
              onTap: () => setState(() {
                l.label == current
                    ? _labelFilter.remove(space.id)
                    : _labelFilter[space.id] = l.label;
              }),
            ),
          );
        },
      ),
    );
  }

  // ── article ──

  Widget _article(BuildContext context, String id) {
    final a = _store.articleById(id);
    if (a == null) return _missing(context, 'knowledge.pageNotFound');
    final compact = context.isCompact;
    void edit([Rect? _]) => _go(KnowledgeEditLocation(a.id));
    return PageChrome(
      title: a.title,
      onBack: _back,
      onTitleTap: compact ? (rect) => _pageMenu(a, rect) : null,
      actions: [
        if (!compact)
          PageAction(
            icon: LucideIcons.ellipsis,
            label: context.t('knowledge.more'),
            onTap: (rect) => _pageMenu(a, rect),
          ),
        PageAction(
          icon: LucideIcons.pencil,
          label: context.t('knowledge.editShort'),
          primary: true,
          onTap: edit,
        ),
      ],
      child: LayoutBuilder(
        builder: (context, c) {
          final bp = c.maxWidth < KbTokens.bpMid
              ? _Bp.narrow
              : c.maxWidth < KbTokens.bpWide
              ? _Bp.mid
              : _Bp.wide;
          return _scroll(_articleLayout(a, bp), top: 16);
        },
      ),
    );
  }

  Widget _articleLayout(KbArticle a, _Bp bp) {
    final reader = KnowledgeReader(
      // Keyed by page: everything the reader derived from the previous
      // document — outline, linked issues, the active heading — must not
      // carry over to the next one.
      key: ValueKey(a.id),
      article: a,
      asideMode: _asideCollapsed && bp == _Bp.wide
          ? AsideMode.none
          : bp == _Bp.wide
          ? AsideMode.side
          : AsideMode.below,
      starred: _store.isStarred(a.id),
      onToggleStar: () => _toggleStar(a.id),
      onOpenSpace: _openSpace,
      onOpenHistory: () => _go(KnowledgeHistoryLocation(a.id)),
      contributors: _contributors[a.id],
      onPlace: (place) => _place(a.id, place),
      placeBusy: _placeBusy,
    );
    if (bp == _Bp.narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GhostButton(
              label: context.t('knowledge.reader.pages'),
              icon: LucideIcons.panelLeft,
              onPressed: () => _openTreeSheet(a),
            ),
          ),
          const SizedBox(height: 8),
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
              spaceId: a.spaceId,
              selectedId: a.id,
              onOpenSpace: () => _openSpace(a.spaceId),
              onSelect: _openArticle,
              onNewChild: (pid) =>
                  _go(KnowledgeNewLocation(spaceId: a.spaceId, parentId: pid)),
              onMove: _move,
              onShift: _shift,
              onDelete: _confirmDelete,
            ),
          ),
          const SizedBox(width: 28),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PanelToggle(
                    icon: _treeCollapsed
                        ? LucideIcons.panelLeftOpen
                        : LucideIcons.panelLeftClose,
                    tooltip: context.t(
                      _treeCollapsed
                          ? 'knowledge.showPages'
                          : 'knowledge.hidePages',
                    ),
                    onTap: () =>
                        setState(() => _treeCollapsed = !_treeCollapsed),
                  ),
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
                      onTap: () =>
                          setState(() => _asideCollapsed = !_asideCollapsed),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              reader,
            ],
          ),
        ),
      ],
    );
  }

  // ── editing ──

  Widget _edit(BuildContext context, String id) {
    final a = _store.articleById(id);
    if (a == null) return _missing(context, 'knowledge.pageNotFound');
    return _editorPage(
      context,
      title: context.t('knowledge.edit'),
      saveLabel: context.t('common.save'),
      editor: KnowledgeEditor(
        key: _editor,
        isNew: false,
        initialTitle: a.title,
        initialDoc: a.doc,
        // The legacy markdown, so a row the backfill skipped opens with its
        // content rather than blank over it.
        initialBody: a.body,
        initialLabels: a.labels,
        spaceId: a.spaceId,
        onSave: _save,
        onDirtyChanged: (dirty) => _dirty = dirty,
        bottomPadding: 32 + context.bottomGutter,
        refusal: _refusal,
      ),
    );
  }

  Widget _create(BuildContext context, String? spaceId, String? parentId) {
    final parent = parentId == null ? null : _store.articleById(parentId);
    final space =
        parent?.spaceId ??
        (spaceId != null && _store.spaceById(spaceId) != null
            ? spaceId
            : null) ??
        _store.spaces.firstOrNull?.id ??
        '';
    return _editorPage(
      context,
      title: context.t('knowledge.newArticle'),
      saveLabel: context.t('knowledge.publish'),
      editor: KnowledgeEditor(
        key: _editor,
        isNew: true,
        initialTitle: '',
        initialDoc: null,
        spaceId: space,
        // A new top-level page chooses where it lives (only its author by
        // default); a subpage lives where its parent lives.
        choosePlace: parent == null,
        onSave: _save,
        onDirtyChanged: (dirty) => _dirty = dirty,
        bottomPadding: 32 + context.bottomGutter,
        refusal: _refusal,
      ),
    );
  }

  Widget _editorPage(
    BuildContext context, {
    required String title,
    required String saveLabel,
    required Widget editor,
  }) {
    return PageChrome(
      title: title,
      onBack: _back,
      actions: [
        PageAction(
          icon: LucideIcons.check,
          label: saveLabel,
          primary: true,
          busy: _saving,
          onTap: _saveAction,
        ),
      ],
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.pageGutter,
          (context.isCompact ? context.pageGutter : 16) + context.topGutter,
          context.pageGutter,
          0,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: KbTokens.readerMaxWidth + 120,
            ),
            child: editor,
          ),
        ),
      ),
    );
  }

  void _saveAction(Rect? _) => _editor.currentState?.save();

  // ── history ──

  Widget _history(BuildContext context, String id, int? version) {
    final a = _store.articleById(id);
    if (a == null) return _missing(context, 'knowledge.pageNotFound');
    // Opened by [_arrived] when this address was reached.
    final versions = _versions;
    if (versions == null || _versionsOf != id) {
      return PageChrome(
        title: context.t('knowledge.title'),
        onBack: _back,
        child: const Center(child: HiveLoader()),
      );
    }
    return BlocBuilder<PagedCubit<ArticleVersion>, PagedState<ArticleVersion>>(
      bloc: versions,
      builder: (context, state) {
        final latest = state.items.firstOrNull?.number;
        final canRestore =
            version != null && latest != null && version != latest;
        return PageChrome(
          title: context.t(
            'knowledge.history.title',
            variables: {'title': a.title},
          ),
          onBack: _back,
          actions: [
            if (canRestore)
              PageAction(
                icon: LucideIcons.rotateCcw,
                label: context.t('knowledge.history.restore'),
                primary: true,
                onTap: (_) => _restore(id, version),
              ),
          ],
          child: _scroll(
            KnowledgeHistoryView(
              repo: _store,
              article: a,
              versions: versions,
              loadVersion: (n) => _knowledge.version(id, n),
              selected: version,
              onSelect: (n) => _go(KnowledgeHistoryLocation(id, version: n)),
              wide: !context.isCompact,
            ),
            top: 16,
          ),
        );
      },
    );
  }
}

/// Hides or shows a reader panel: a round theme button, so it takes the
/// app's glass capsule like every other secondary action.
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
  Widget build(BuildContext context) =>
      GhostButton(label: tooltip, icon: icon, iconOnly: true, onPressed: onTap);
}
