import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/progressive_blur.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hinata_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/markdown_toolbar.dart';
import '../../core/widgets/soft_card.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import 'comments/comment_attach.dart';
import 'comments/comment_thread.dart';
import 'comments/glass_comment_composer.dart';
import 'comments/voice/voice_recorder.dart' show VoiceRecording;
import '../git/widgets/deployment_panel.dart';
import '../git/widgets/development_summary.dart';
import '../knowledge/data/knowledge_models.dart' show KbArticle, lucideIcon;
import '../knowledge/data/knowledge_repository.dart';
import '../knowledge/knowledge_tokens.dart';
import '../knowledge/markdown/markdown_renderer.dart';
import '../knowledge/markdown/mention_field.dart';
import '../knowledge/markdown/smart_link_resolver.dart';
import '../sprint/modals/estimate_dialog.dart' show showStoryPointsDialog;
import '../sprint/modals/glass_modal.dart'
    show
        glassWoltSurface,
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassDatePicker,
        showGlassModal,
        showGlassOptions;
import 'attachments/attachments_section.dart';
import 'epic_search_popover.dart';
import 'issue_form.dart' show showIssueForm;
import 'issue_links_section.dart';
import 'issue_description_editor.dart';
import 'issue_labels.dart';
import 'issue_link_resolver.dart';
import 'work_log_sheet.dart';

/// Row height of the full-screen route's pinned top bar (below the status bar).
/// Shared so [IssueDetailScreen] can offset its scroll content by exactly this
/// much and the bar's blur region lines up with where the content begins.
const double kRouteTopBarHeight = 52;

/// The project's configured colour for a workflow-state name, or null to fall
/// back to the global state palette (`AppColors.stateColor`).
Color? _projStateColor(Project? project, String state) {
  final hue = project?.hueForState(state);
  return hue == null ? null : hueColor(hue);
}

/// A shareable, clean (non-`#`) URL that resolves to the issue — both as a
/// verified deep link into the app and as a normal web route. On web we use the
/// origin the app is served from; on native we derive the public web origin from
/// the configured API server ([apiBaseUrl]) using the convention that the API
/// lives at `api.<domain>` and the web app + App Links at `<domain>`.
String issueWebLink(String apiBaseUrl, String id) {
  if (kIsWeb) {
    try {
      return '${Uri.base.origin}/issues/$id';
    } catch (_) {
      return '/issues/$id';
    }
  }
  final api = Uri.tryParse(apiBaseUrl);
  if (api == null || api.host.isEmpty) return '/issues/$id';
  final host = api.host.startsWith('api.') ? api.host.substring(4) : api.host;
  final origin = Uri(
    scheme: api.scheme,
    host: host,
    port: api.hasPort ? api.port : null,
  );
  return '$origin/issues/$id';
}

/// Centered dialog that can grow much wider than the wolt default so the
/// two-column issue detail has room on desktop.
class _WideDialogType extends WoltDialogType {
  const _WideDialogType();

  @override
  BoxConstraints layoutModal(Size availableSize) {
    const pad = 48.0;
    final width = math.min(
      940.0,
      math.max(360.0, availableSize.width - pad * 2),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: 0,
      maxHeight: math.max(360, availableSize.height * 0.88),
    );
  }
}

/// Opens the issue detail as a responsive wolt modal sheet (bottom sheet on
/// phones, wide centered dialog on desktop). The readable id + actions live in
/// the modal's own top bar; [onChanged] fires whenever the issue is edited or
/// deleted so the caller can refresh its list.
Future<void> showIssueDetailSheet(
  BuildContext context, {
  required String issueId,
  VoidCallback? onChanged,
}) {
  final repository = context.read<HinataRepository>();
  final auth = context.read<AuthBloc>();
  final header = ValueNotifier<Issue?>(null);
  final bodyKey = GlobalKey<IssueDetailBodyState>();
  final apiBaseUrl = repository.apiBaseUrl;
  // Own the sheet's scroll controller so the body can animate the feed to the
  // newest comment after posting (phone: the whole sheet scrolls).
  final sheetScroll = ScrollController();
  // Bumped by the body whenever the sticky composer's appearance changes (e.g.
  // entering/leaving inline comment editing) so the sticky bar — a separate
  // subtree from the body — rebuilds to reflect it.
  final composerRev = ValueNotifier<int>(0);

  return WoltModalSheet.show<void>(
    context: context,
    // Push onto the root navigator so the sheet covers the floating glass
    // bottom-nav instead of rendering behind it (the shell nav is a Positioned
    // sibling inside the ShellRoute's nested navigator).
    useRootNavigator: true,
    useSafeArea: false,
    barrierDismissible: true,
    pageContentDecorator: glassWoltSurface,
    modalTypeBuilder: (ctx) => MediaQuery.sizeOf(ctx).width >= 760
        ? const _WideDialogType()
        : WoltModalType.bottomSheet(),
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrollController: sheetScroll,
        hasTopBarLayer: true,
        isTopBarLayerAlwaysVisible: true,
        leadingNavBarWidget: ValueListenableBuilder<Issue?>(
          valueListenable: header,
          builder: (_, issue, _) => issue == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: CopyLinkId(
                    type: issue.type,
                    readableId: issue.readableId,
                    link: issueWebLink(apiBaseUrl, issue.linkId),
                    glyphSize: 24,
                    fontSize: 16,
                  ),
                ),
        ),
        trailingNavBarWidget: _SheetActions(
          onMaximize: () {
            final router = GoRouter.of(modalContext);
            Navigator.of(modalContext).maybePop();
            router.push(
              '/issues/$issueId',
              extra: IssueRouteArgs(fromModal: true, onChanged: onChanged),
            );
          },
          onDelete: () => bodyKey.currentState?.confirmDeleteIssue(),
          onClose: () => Navigator.of(modalContext).maybePop(),
        ),
        // On a phone bottom sheet the comment composer floats here, pinned above
        // the scrolling feed; the wide dialog keeps it inline (returns nothing).
        // Providers are re-supplied because the sticky bar sits outside the
        // body's provider scope (the MentionField reads the repository).
        stickyActionBar: MultiRepositoryProvider(
          providers: [
            RepositoryProvider.value(value: repository),
            BlocProvider.value(value: auth),
          ],
          child: ValueListenableBuilder<Issue?>(
            valueListenable: header,
            builder: (ctx, issue, _) {
              final state = bodyKey.currentState;
              if (issue == null || state == null) {
                return const SizedBox.shrink();
              }
              // Rebuild on composer-state changes (edit banner, mode) too.
              return ValueListenableBuilder<int>(
                valueListenable: composerRev,
                builder: (ctx, _, _) => state.buildFloatingComposer(ctx),
              );
            },
          ),
        ),
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider.value(value: repository),
            BlocProvider.value(value: auth),
          ],
          child: IssueDetailBody(
            key: bodyKey,
            issueId: issueId,
            onChanged: onChanged,
            header: header,
            sheetScroll: sheetScroll,
            composerRev: composerRev,
            floatingComposer: true,
          ),
        ),
      ),
    ],
  ).whenComplete(() {
    header.dispose();
    // NOTE: do NOT dispose `sheetScroll` here — Wolt's animated switcher takes
    // ownership of the page's `scrollController` and disposes it itself
    // (WoltModalSheetAnimatedSwitcher.dispose). Disposing it again crashes with
    // "A ScrollController was used after being disposed", which then cascades
    // into a storm of null-check errors from the half-torn-down widget tree.
    composerRev.dispose();
  });
}

/// Arguments handed to the `/issues/:id` route via GoRouter `extra` when the
/// user promotes the modal sheet to the full-page view ("full screen"). They
/// let the page know it may shrink back to the modal ([fromModal]) and carry
/// the caller's refresh callback so list views still update from full screen.
class IssueRouteArgs {
  const IssueRouteArgs({this.fromModal = false, this.onChanged});

  final bool fromModal;
  final VoidCallback? onChanged;
}

/// Full-screen · delete · close — rendered in the wolt top bar. The copy-link
/// affordance now lives on the readable-id chip (see [CopyLinkId]); the leading
/// action here promotes the sheet to the full-page `/issues/:id` view.
class _SheetActions extends StatelessWidget {
  const _SheetActions({
    required this.onMaximize,
    required this.onDelete,
    required this.onClose,
  });

  final VoidCallback onMaximize;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.t('issues.maximize'),
          onPressed: onMaximize,
          icon: Icon(LucideIcons.maximize2, size: 19, color: AppColors.inkSoft),
        ),
        IconButton(
          tooltip: context.t('common.delete'),
          onPressed: onDelete,
          icon: const Icon(
            LucideIcons.trash2,
            size: 20,
            color: AppColors.danger,
          ),
        ),
        IconButton(
          tooltip: context.t('common.cancel'),
          onPressed: onClose,
          icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

/// The readable-id chip with a Jira-style "copy link" affordance.
///
/// Desktop / mouse: hovering near the id fades a copy icon in from the left;
/// clicking it (or the id) copies the shareable issue link and morphs the icon
/// into a green check with a "Copied!" tooltip, reverting after a moment.
///
/// Touch: a single tap on the id copies the link and floats a small hint chip
/// ("Link to HIN-39 copied") just below the id, since there is no hover state.
class CopyLinkId extends StatefulWidget {
  const CopyLinkId({
    super.key,
    required this.type,
    required this.readableId,
    required this.link,
    this.glyphSize = 22,
    this.fontSize = 13,
    this.color,
    this.showGlyph = true,
  });

  final String type;
  final String readableId;
  final String link;
  final double glyphSize;
  final double fontSize;
  final Color? color;

  /// Whether to render the leading type glyph before the id (the modal header
  /// shows it; the route top bar already has a back button and omits it).
  final bool showGlyph;

  @override
  State<CopyLinkId> createState() => _CopyLinkIdState();
}

class _CopyLinkIdState extends State<CopyLinkId> {
  final LayerLink _layerLink = LayerLink();
  bool _hovering = false;
  bool _copied = false;
  Timer? _revertTimer;
  OverlayEntry? _hintEntry;
  Timer? _hintTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    _hintTimer?.cancel();
    _removeHint();
    super.dispose();
  }

  void _removeHint() {
    _hintEntry?.remove();
    _hintEntry = null;
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.link));
    setState(() => _copied = true);
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    // No hover state means a touch device — surface the inline confirmation
    // chip below the id (desktop relies on the icon morph + tooltip instead).
    if (!_hovering) _showHint();
  }

  void _showHint() {
    _removeHint();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final id = widget.readableId;
    _hintEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 30),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CopiedHintChip(id: id),
          ),
        ),
      ),
    );
    overlay.insert(_hintEntry!);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 2000), _removeHint);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _hovering || _copied;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _copy,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showGlyph) ...[
                TypeGlyph(type: widget.type, size: widget.glyphSize),
                const SizedBox(width: 10),
              ],
              IdMono(
                widget.readableId,
                color: widget.color ?? AppColors.inkSoft,
                fontSize: widget.fontSize,
              ),
              // Reserved slot: the icon fades + slides in from the left on hover
              // (or once copied), so the row width never jumps.
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: visible ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    offset: visible ? Offset.zero : const Offset(-0.45, 0),
                    child: Tooltip(
                      message: context.t(
                        _copied ? 'issues.copied' : 'issues.copyLink',
                      ),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Center(
                          child: _copied
                              ? Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    LucideIcons.check,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  LucideIcons.link,
                                  size: 16,
                                  color: widget.color ?? AppColors.inkSoft,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating "Link to HIN-39 copied" chip shown under the id on touch.
class _CopiedHintChip extends StatelessWidget {
  const _CopiedHintChip({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      tween: Tween(begin: 0, end: 1),
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * -6),
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.link, size: 16, color: Colors.white),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  context.t('issues.linkCopiedFor', variables: {'id': id}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared editable issue detail — used both inside the sheet and by the
/// `/issues/:id` route. When [header] is supplied (sheet mode) the readable id
/// lives in the wolt top bar and the internal top bar is hidden.
class IssueDetailBody extends StatefulWidget {
  const IssueDetailBody({
    super.key,
    required this.issueId,
    this.onChanged,
    this.header,
    this.sheetScroll,
    this.composerRev,
    this.floatingComposer = false,
    this.canMinimize = false,
  });

  final String issueId;
  final VoidCallback? onChanged;
  final ValueNotifier<Issue?>? header;

  /// The host's scroll controller. Lets the body animate to the newest comment
  /// after posting (sheet: the wolt page scroll; route: the page scroll view).
  final ScrollController? sheetScroll;

  /// Bumped to force the host's floating composer (a separate subtree — the
  /// sheet's sticky bar or the route's Stack overlay) to rebuild when its
  /// appearance depends on body state (inline edit).
  final ValueNotifier<int>? composerRev;

  /// Whether the host renders the composer as a floating bar (via
  /// [buildFloatingComposer]) instead of inline in the activity card — true for
  /// both the modal sheet and the full-page route.
  final bool floatingComposer;

  /// Full-page (route) mode only: whether this view was promoted from the modal
  /// sheet and can therefore shrink back to it. Direct deep-links open the page
  /// with no modal underneath, so the "exit full screen" button is hidden.
  final bool canMinimize;

  @override
  State<IssueDetailBody> createState() => IssueDetailBodyState();
}

class IssueDetailBodyState extends State<IssueDetailBody> {
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  late final MarkdownEditingActions _commentActions = MarkdownEditingActions(
    _comment,
    _commentFocus,
  );

  /// When non-null, the composer is editing this existing comment inline (its
  /// text is loaded into [_comment]); submitting saves the edit instead of
  /// posting a new comment.
  IssueComment? _editingComment;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  // Lets the composer's "+" → Anhang drive the attachments section's own
  // (optimistic, live-updating) upload flow instead of a blind background POST.
  final _attachmentsKey = GlobalKey<AttachmentsSectionState>();

  Issue? _issue;
  // Comments are paginated newest-first server-side but displayed oldest-first
  // (chat style): each loaded page is reversed and older pages prepend above.
  // Activity stays newest-first; older pages append below.
  List<IssueComment> _comments = const [];
  List<IssueActivity> _activity = const [];
  int _commentsTotal = 0;
  int _commentsPage = 0;
  int _activityTotal = 0;
  int _activityPage = 0;
  bool _loadingMore = false;
  List<WorkItem> _workItems = const [];
  Project? _project;
  // Cross-feature smart-links: project issues (keyed by readable id) feed the
  // comment composer's `@`-menu and resolve `{{issue:…}}` chips; KB articles
  // that mention this issue are its "Documented in" backlinks.
  Map<String, Issue> _projectIssues = const {};
  // Breadcrumb ancestors + direct children (epic→stories, story→sub-tasks).
  IssueHierarchy _hierarchy = IssueHierarchy.empty;
  List<KbArticle> _documentedIn = const [];
  KnowledgeRepository get _knowledge => context.read<KnowledgeRepository>();
  // Labels deleted this session — guards against the stale _project list
  // re-suggesting a label that was just removed from the project.
  final Set<String> _deletedLabels = {};
  List<DirectoryUser> _users = const [];
  List<Sprint> _sprints = const [];
  Map<String, String> get _names => {
    for (final u in _users) u.id: u.displayName,
  };
  Map<String, String> get _avatars => {
    for (final u in _users)
      if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty) u.id: u.avatarUrl!,
  };
  Map<String, String> get _sprintNames => {
    for (final s in _sprints) s.id: s.name,
  };

  bool _loading = true;
  String? _error;
  bool _busy = false;

  // Inline editing + activity filter state.
  bool _editingTitle = false;
  bool _editingDesc = false;
  // Default the activity panel to the Comments tab so the conversation shows
  // up front when an issue is opened.
  _ActivityFilter _activityFilter = _ActivityFilter.comments;

  HinataRepository get _repo => context.read<HinataRepository>();

  @override
  void initState() {
    super.initState();
    _commentFocus.addListener(_onCommentFocusChanged);
    _load();
  }

  // Rebuild the floating composer (a separate subtree) when the comment field
  // gains/loses focus, so it can hide itself while the keyboard is up for some
  // *other* field (e.g. the sub-task or linked-issue inputs) — see
  // [buildFloatingComposer]. Focus transitions that don't move the keyboard
  // (tapping the comment field while another field's keyboard is already open)
  // wouldn't otherwise trigger a MediaQuery rebuild of the sticky bar.
  void _onCommentFocusChanged() => _bumpComposer();

  @override
  void dispose() {
    _commentFocus.removeListener(_onCommentFocusChanged);
    _comment.dispose();
    _commentFocus.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Nudges the sticky action bar (a subtree outside this body) to rebuild its
  /// floating composer — call after any state change the composer reflects.
  /// Guarded: `composerRev` is owned by the host and disposed when the sheet/
  /// route closes, so a late async caller must not touch it once unmounted.
  void _bumpComposer() {
    if (mounted) widget.composerRev?.value++;
  }

  /// Animates the modal down to the just-posted comment. Scoped to the
  /// chat-ordered Comments tab (newest last → bottom); the "All" tab is
  /// newest-first and mid-scroll, so a "scroll to bottom" wouldn't map there.
  /// Runs after the next frame so the new row is laid out and the max extent is
  /// current.
  void _revealNewestComment() {
    if (_activityFilter != _ActivityFilter.comments) return;
    final controller = widget.sheetScroll;
    if (controller == null || !controller.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final issue = await _repo.issue(widget.issueId);
      final results = await Future.wait([
        _repo.comments(widget.issueId),
        _repo.workItems(widget.issueId),
        _repo.projects(),
        _repo.users(),
        _repo.issueActivity(widget.issueId),
      ]);
      _issue = issue;
      final commentsPage =
          results[0] as ({List<IssueComment> items, int total});
      _comments = commentsPage.items.reversed.toList();
      _commentsTotal = commentsPage.total;
      _commentsPage = 0;
      _workItems = results[1] as List<WorkItem>;
      _project = (results[2] as List<Project>)
          .where((p) => p.id == issue.projectId)
          .firstOrNull;
      _users = results[3] as List<DirectoryUser>;
      final activityPage =
          results[4] as ({List<IssueActivity> items, int total});
      _activity = activityPage.items;
      _activityTotal = activityPage.total;
      _activityPage = 0;
      // Sprints come from the project's board(s); aggregate across every board
      // (a project may have both a Kanban and a Scrum board). Best-effort.
      try {
        _sprints = await _repo.sprintsForProject(issue.projectId);
      } catch (_) {
        _sprints = const [];
      }
      // Project issues power the comment `@`-menu + `{{issue:…}}` chip previews;
      // KB backlinks come from the shared seed. Both best-effort.
      try {
        final all = await _repo.allIssues(projectId: issue.projectId);
        _projectIssues = {for (final i in all) i.readableId: i};
      } catch (_) {
        _projectIssues = const {};
      }
      try {
        _hierarchy = await _repo.issueHierarchy(widget.issueId);
      } catch (_) {
        _hierarchy = IssueHierarchy.empty;
      }
      try {
        await _knowledge.init();
        _documentedIn = _knowledge.articlesForIssue(issue.readableId);
      } catch (_) {
        _documentedIn = const [];
      }
      // The sheet/route can close mid-load — the host then disposes `header` and
      // `composerRev`. `?.` guards null, NOT disposal, so writing them after an
      // await on a closed sheet throws "used after disposed" as an UNHANDLED
      // async error that takes the whole app down. Bail if we were unmounted
      // during any of the awaits above.
      if (!mounted) return;
      widget.header?.value = issue;
      setState(() => _loading = false);
      // Reveal the host's floating composer now that the issue is loaded (the
      // route overlay reads `hasIssue`, and its subtree is outside this body).
      _bumpComposer();
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = failure.message;
        });
      }
    }
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    setState(() => _busy = true);
    try {
      final updated = await _repo.updateIssue(widget.issueId, patch);
      if (!mounted) return;
      _issue = updated;
      widget.header?.value = updated;
      widget.onChanged?.call();
      // Refresh the change history so the new entry shows immediately (reset to
      // the newest page).
      try {
        final p = await _repo.issueActivity(widget.issueId);
        _activity = p.items;
        _activityTotal = p.total;
        _activityPage = 0;
      } catch (_) {
        // Non-critical; the next full load reflects server truth.
      }
      // A re-parent changes the breadcrumb ancestors — keep them in sync.
      await _reloadHierarchy();
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pulls the fresh ancestors + children so the breadcrumb and the child /
  /// sub-task panels reflect a re-parent, an inline add, or a state toggle.
  Future<void> _reloadHierarchy() async {
    try {
      final h = await _repo.issueHierarchy(widget.issueId);
      if (mounted) setState(() => _hierarchy = h);
    } catch (_) {
      // Non-critical; the next full load reflects server truth.
    }
  }

  // ── git integration ───────────────────────────────────────────────────────
  bool get _gitConnected => _project?.git != null;

  /// Reflects a server-applied transition triggered by a PR/MR action (merge /
  /// ready) in the Development summary.
  void _applyGitIssue(Issue updated) {
    if (!mounted) return;
    setState(() => _issue = updated);
    widget.header?.value = updated;
    widget.onChanged?.call();
    _refreshActivity();
  }

  /// Reflects a branch-template change made from the Deployment panel.
  void _applyGitProject(Project updated) {
    if (mounted) setState(() => _project = updated);
  }

  Future<void> _refreshActivity() async {
    try {
      final page = await _repo.issueActivity(widget.issueId);
      if (mounted) {
        setState(() {
          _activity = page.items;
          _activityTotal = page.total;
          _activityPage = 0;
        });
      }
    } catch (_) {
      // Non-critical; the next full load reflects server truth.
    }
  }

  void _openProjectSettings(String projectId) {
    final router = GoRouter.of(context);
    Navigator.of(context).maybePop();
    router.push('/projects/$projectId/settings');
  }

  Widget _developmentBlock(Issue issue) {
    final project = _project;
    if (project == null || project.git == null) return const SizedBox.shrink();
    return DevelopmentSummary(
      issue: issue,
      project: project,
      names: _names,
      avatars: _avatars,
      onIssueChanged: _applyGitIssue,
    );
  }

  Widget _deploymentPanel(Issue issue) {
    final project = _project;
    if (project == null) return const SizedBox.shrink();
    return DeploymentPanel(
      issue: issue,
      project: project,
      onConnectInSettings: () => _openProjectSettings(project.id),
      onProjectChanged: _applyGitProject,
    );
  }

  Future<void> _submitComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    // Editing an existing comment inline → save instead of posting a new one.
    final editing = _editingComment;
    if (editing != null) {
      final ok = await _editComment(editing, text);
      if (ok && mounted) {
        setState(() {
          _editingComment = null;
          _comment.clear();
        });
        _bumpComposer();
      }
      return;
    }
    try {
      await _repo.addComment(widget.issueId, text);
      _comment.clear();
      // Reset to the newest page so the just-posted comment shows at the bottom.
      final p = await _repo.comments(widget.issueId);
      _comments = p.items.reversed.toList();
      _commentsTotal = p.total;
      _commentsPage = 0;
      if (mounted) {
        setState(() {});
        _revealNewestComment();
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    }
  }

  /// Loads [comment] into the composer for inline editing (no separate dialog).
  void _promptEditComment(IssueComment comment) {
    setState(() {
      _editingComment = comment;
      _comment.text = comment.text;
      _comment.selection = TextSelection.collapsed(
        offset: _comment.text.length,
      );
    });
    _bumpComposer();
    _commentFocus.requestFocus();
  }

  /// Abandons an in-progress inline edit and clears the composer.
  void _cancelEditComment() {
    setState(() {
      _editingComment = null;
      _comment.clear();
    });
    _bumpComposer();
  }

  /// Saves an inline edit of the user's own [comment]. Returns true on success
  /// so the tile can close its editor; a no-op (unchanged/empty) also succeeds.
  Future<bool> _editComment(IssueComment comment, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == comment.text) return true;
    try {
      final updated = await _repo.editComment(
        widget.issueId,
        comment.id,
        trimmed,
      );
      if (mounted) {
        setState(() {
          _comments = [
            for (final c in _comments) c.id == updated.id ? updated : c,
          ];
        });
      }
      return true;
    } on ApiFailure catch (failure) {
      _toast(failure.message);
      return false;
    }
  }

  Future<void> _deleteComment(IssueComment comment) async {
    final confirmed = await showGlassModal<bool>(
      context,
      width: 420,
      builder: (_) => const _DeleteCommentConfirm(),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteComment(widget.issueId, comment.id);
      if (mounted) {
        setState(() {
          _comments = [
            for (final c in _comments)
              if (c.id != comment.id) c,
          ];
          if (_commentsTotal > 0) _commentsTotal--;
        });
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    }
  }

  bool get _hasMoreComments => _comments.length < _commentsTotal;
  bool get _hasMoreActivity => _activity.length < _activityTotal;

  /// Loads the previous (older) page of comments and prepends it above the
  /// thread, de-duplicating in case a row shifted across the page boundary.
  Future<void> _loadMoreComments() async {
    if (_loadingMore || !_hasMoreComments) return;
    setState(() => _loadingMore = true);
    try {
      final next = _commentsPage + 1;
      final p = await _repo.comments(widget.issueId, page: next);
      if (!mounted) return;
      final existing = {for (final c in _comments) c.id};
      final older = [
        for (final c in p.items.reversed)
          if (!existing.contains(c.id)) c,
      ];
      setState(() {
        _comments = [...older, ..._comments];
        _commentsTotal = p.total;
        _commentsPage = next;
      });
    } catch (_) {
      // Keep what we have; the user can retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Loads the next (older) page of change history and appends it below.
  Future<void> _loadMoreActivity() async {
    if (_loadingMore || !_hasMoreActivity) return;
    setState(() => _loadingMore = true);
    try {
      final next = _activityPage + 1;
      final p = await _repo.issueActivity(widget.issueId, page: next);
      if (!mounted) return;
      final existing = {for (final a in _activity) a.id};
      final older = [
        for (final a in p.items)
          if (!existing.contains(a.id)) a,
      ];
      setState(() {
        _activity = [..._activity, ...older];
        _activityTotal = p.total;
        _activityPage = next;
      });
    } catch (_) {
      // Keep what we have; the user can retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── inline editing + actions (driven by the top-bar / double-tap) ─────────

  /// Public entry points so the top-bar actions can drive the body.
  void beginTitleEdit() {
    final issue = _issue;
    if (issue == null) return;
    _titleCtrl.text = issue.title;
    setState(() => _editingTitle = true);
  }

  void _beginDescEdit() {
    final issue = _issue;
    if (issue == null) return;
    _descCtrl.text = issue.description ?? '';
    setState(() => _editingDesc = true);
  }

  Future<void> _saveTitle() async {
    final value = _titleCtrl.text.trim();
    setState(() => _editingTitle = false);
    if (value.isEmpty || value == _issue!.title) return;
    await _patch({'title': value});
  }

  Future<void> _saveDesc() async {
    final value = _descCtrl.text;
    setState(() => _editingDesc = false);
    if (value == (_issue!.description ?? '')) return;
    await _patch({'description': value});
  }

  /// The route back button (compact full-screen has no shell nav to fall back
  /// on): pop if there's a page underneath, otherwise — e.g. a cold-start deep
  /// link straight into the issue — go home so the user is never stranded.
  void _closeRoute() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      GoRouter.of(context).go('/dashboard');
    }
  }

  /// Full-page → modal: re-open the issue as a modal sheet and drop the route
  /// underneath it. The sheet is shown first (while this context is still
  /// mounted) so its provider reads succeed, then the route is popped away.
  void _minimizeToModal() {
    final navigator = Navigator.of(context);
    showIssueDetailSheet(
      context,
      issueId: widget.issueId,
      onChanged: widget.onChanged,
    );
    navigator.maybePop();
  }

  Future<void> confirmDeleteIssue() async {
    final issue = _issue;
    if (issue != null) await _confirmDelete(issue);
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading && _issue == null) {
      return const SizedBox(height: 260, child: Center(child: HiveLoader()));
    }
    if (_error != null && _issue == null) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t(_error!),
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: Text(context.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    final issue = _issue!;
    // The wolt sheet (header != null) owns the top bar; the route renders its
    // own. Both are intrinsically sized — the route wraps this in a scroll view,
    // the sheet scrolls its own content.
    final documented = _documentedInSection();
    return SmartLinkScope(
      resolver: _buildResolver(issue),
      // Tap anywhere on the body (feed bubbles, empty gaps between them and the
      // docked composer) to drop focus and dismiss the keyboard — there's no
      // other way out on a full-screen chat. The composer lives in a separate
      // subtree (sticky action bar / route overlay) so tapping it keeps focus,
      // and interactive children (buttons, links, menus) still win their taps.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // On the COMPACT full-screen route the top bar is not inline — it's
            // pinned as a scroll-reactive glass bar by IssueDetailScreen (see
            // [buildRouteTopBar]) so back/minimize stay reachable when the thread
            // gets long. The sheet uses Wolt's own nav bar. The WIDE route keeps
            // an inline bar (no overlap with the desktop shell's own top bar).
            if (widget.header == null && !context.isCompact)
              _RouteTopBar(
                issue: issue,
                busy: _busy,
                stateColor: _projStateColor(_project, issue.state),
                link: issueWebLink(_repo.apiBaseUrl, issue.linkId),
                onMinimize: widget.canMinimize ? _minimizeToModal : null,
                onDelete: () => _confirmDelete(issue),
                onClose: _closeRoute,
              ),
            Padding(
            // Extra bottom room when the composer floats, so the last comment
            // isn't hidden behind the docked input.
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              composerFloats(context) ? 128 : 24,
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final hierarchy = _hierarchyCard(issue);
                final left = <Widget>[
                  _contentCard(issue),
                  if (hierarchy != null) ...[
                    const SizedBox(height: 14),
                    hierarchy,
                  ],
                  // The Development block owns its own leading gap and hides
                  // entirely when no work is linked (Jira-style).
                  if (_gitConnected) _developmentBlock(issue),
                  const SizedBox(height: 14),
                  _linksSection(issue),
                  const SizedBox(height: 14),
                  _attachmentsSection(issue),
                  if (documented != null) ...[
                    const SizedBox(height: 14),
                    documented,
                  ],
                  const SizedBox(height: 14),
                  _activityCard(),
                ];
                final right = <Widget>[
                  _detailsCard(issue),
                  // Deployment sits between Details and Timeline.
                  if (_project != null) ...[
                    const SizedBox(height: 14),
                    _deploymentPanel(issue),
                  ],
                  const SizedBox(height: 14),
                  _timeCard(issue),
                  const SizedBox(height: 14),
                  _issueMeta(issue),
                ];
                if (c.maxWidth >= 680) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: left,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: right,
                        ),
                      ),
                    ],
                  );
                }
                // Stacked (phone): content, details, time, activity.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _contentCard(issue),
                    if (hierarchy != null) ...[
                      const SizedBox(height: 14),
                      hierarchy,
                    ],
                    if (_gitConnected) _developmentBlock(issue),
                    const SizedBox(height: 14),
                    _linksSection(issue),
                    const SizedBox(height: 14),
                    _attachmentsSection(issue),
                    if (documented != null) ...[
                      const SizedBox(height: 14),
                      documented,
                    ],
                    const SizedBox(height: 14),
                    _detailsCard(issue),
                    // Deployment sits between Details and Timeline.
                    if (_project != null) ...[
                      const SizedBox(height: 14),
                      _deploymentPanel(issue),
                    ],
                    const SizedBox(height: 14),
                    _timeCard(issue),
                    const SizedBox(height: 14),
                    _issueMeta(issue),
                    const SizedBox(height: 14),
                    _activityCard(),
                  ],
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  // ── smart-link wiring ────────────────────────────────────────────────────

  /// Resolver for the chips/`@`-menu: issues+people from the backend, articles
  /// from the shared KB seed. Rebuilt per frame (cheap) so it always reflects
  /// the freshly-loaded project issues / users.
  IssueLinkResolver _buildResolver(Issue issue) => IssueLinkResolver(
    issuesByReadable: {issue.readableId: issue, ..._projectIssues},
    users: _users,
    knowledgeRepo: _knowledge,
    stateColorFor: (s) =>
        _projStateColor(_project, s) ?? AppColors.stateColor(s),
    onOpenIssue: _openLinkedIssue,
    onOpenDoc: _openArticle,
  );

  /// Opens the real issue for a readable id (e.g. `HIV-208`): tries the loaded
  /// project issues first, then a backend search; toasts if there is no match.
  Future<void> _openLinkedIssue(String readableId) async {
    if (readableId == _issue?.readableId) return; // already open
    var match = _projectIssues[readableId];
    if (match == null) {
      try {
        final res = await _repo.issues(query: readableId, size: 20);
        match = res.issues.where((i) => i.readableId == readableId).firstOrNull;
      } on ApiFailure catch (failure) {
        _toast(failure.message);
        return;
      }
    }
    if (!mounted) return;
    if (match == null) {
      _toast('Issue $readableId not found');
      return;
    }
    await showIssueDetailSheet(context, issueId: match.id);
    // The nested issue may have been re-parented, edited or deleted (e.g. a
    // sub-task removed from here) — refresh so the breadcrumb and the child /
    // sub-task panel reflect it instead of listing a stale row.
    if (mounted) await _reloadHierarchy();
  }

  /// Opens a KB article (doc smart-link) on the `/knowledge/:id` route. When the
  /// issue is shown as a modal sheet, close it first so the article isn't buried.
  void _openArticle(String articleId) {
    final router = GoRouter.of(context);
    if (widget.header != null) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    router.push('/knowledge/$articleId');
  }

  /// "Documented in": KB articles that reference this issue, or null when none.
  Widget? _documentedInSection() {
    if (_documentedIn.isEmpty) return null;
    return _DocumentedIn(
      articles: _documentedIn,
      knowledge: _knowledge,
      onOpen: _openArticle,
    );
  }

  Widget _contentCard(Issue issue) {
    const titleStyle = TextStyle(
      fontFamily: AppTheme.fontBrand,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );

    return SoftCard(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: Colors.transparent),
      // Transparent, borderless card → no inset, so the description (and its
      // editor) use the full content width instead of losing 20px each side.
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Jira-style hierarchy breadcrumb: Epic / Story / Sub-task. Ancestors
          // are clickable; the current issue is the last, inert crumb.
          _breadcrumb(issue),
          // Title — double-tap to edit inline.
          if (_editingTitle)
            _InlineTitleEditor(
              controller: _titleCtrl,
              onSave: _saveTitle,
              onCancel: () => setState(() => _editingTitle = false),
            )
          else
            Tooltip(
              message: context.t('issues.editTitleHint'),
              waitDuration: const Duration(milliseconds: 700),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: beginTitleEdit,
                child: Text(issue.title, style: titleStyle),
              ),
            ),
          const SizedBox(height: 18),
          // Description — double-tap to edit as Markdown. While editing, the
          // section label rides on the editor's header row alongside the
          // Editor/Preview switcher, so it is rendered here only in view mode.
          if (_editingDesc)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IssueDescriptionEditor(
                  controller: _descCtrl,
                  label: _sectionLabel(context.t('issues.description')),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                      ),
                      onPressed: _saveDesc,
                      child: Text(context.t('common.save')),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => _editingDesc = false),
                      child: Text(
                        context.t('common.cancel'),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else ...[
            _sectionLabel(context.t('issues.description')),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _beginDescEdit,
              child: (issue.description ?? '').isNotEmpty
                  // KB parser so `{{issue}}`/`{{doc}}`/`{{user}}` smart-links
                  // render as chips alongside the markdown.
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: KbMarkdownParser(
                        fontSize: 14,
                      ).parse(issue.description!).nodes,
                    )
                  : Text(
                      context.t('issues.noDescription'),
                      style: TextStyle(
                        color: AppColors.inkFaint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.inkFaint,
    ),
  );

  Widget _attachmentsSection(Issue issue) => AttachmentsSection(
    key: _attachmentsKey,
    issueId: widget.issueId,
    initial: issue.attachments,
    userNames: _names,
    onChanged: widget.onChanged,
  );

  /// "Verknüpfte Vorgänge" — the Jira-style issue links (blocks / duplicates /
  /// relates to …), shown for every issue directly under the sub-tasks card.
  Widget _linksSection(Issue issue) => IssueLinksSection(
    issueId: widget.issueId,
    projectId: issue.projectId,
    project: _project,
    userNames: _names,
    userAvatars: _avatars,
    onOpenIssue: _openLinkedIssue,
    onChanged: widget.onChanged,
  );

  /// Hierarchy breadcrumb above the title (`⚡ HIV-12 / ☑ HIV-48`). Hidden for
  /// top-level issues with no ancestors. Ancestors open on tap; the trailing
  /// crumb is the current issue and stays inert.
  Widget _breadcrumb(Issue issue) {
    final crumbs = [..._hierarchy.ancestors, issue];
    if (crumbs.length < 2) return const SizedBox.shrink();
    final row = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final c = crumbs[i];
      final current = i == crumbs.length - 1;
      row.add(_breadcrumbCrumb(c, current: current));
      if (!current) {
        row.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '/',
              style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
            ),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: row,
      ),
    );
  }

  Widget _breadcrumbCrumb(Issue c, {required bool current}) {
    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TypeGlyph(type: c.type, size: 17),
        const SizedBox(width: 5),
        IdMono(
          c.readableId,
          fontSize: 12.5,
          color: current ? AppColors.ink : AppColors.stTodo,
        ),
      ],
    );
    if (current) return inner;
    return InkWell(
      onTap: () => _openLinkedIssue(c.readableId),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: inner,
      ),
    );
  }

  // ── child / sub-task panel ───────────────────────────────────────────────

  /// "Child issues" on an epic, "Sub-tasks" on a standard issue, nothing on a
  /// sub-task. Lists the direct children with a completion bar and an add
  /// affordance (a full create form for epics, an inline quick-add for tasks).
  /// Whether a child counts as "done". Authoritative on the project's resolved
  /// states — the issue's `resolvedAt` flag can go stale after a workflow change,
  /// which wrongly struck a still-open sub-task through.
  bool _childDone(Issue child) {
    final resolved = _project?.resolvedStates;
    if (resolved != null && resolved.isNotEmpty) {
      return resolved.contains(child.state);
    }
    return child.resolved;
  }

  Widget? _hierarchyCard(Issue issue) {
    if (issue.isSubtask) return null;
    final isEpic = issue.isEpic;
    final children = _hierarchy.children;
    final done = children.where(_childDone).length;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t(isEpic ? 'issues.childIssues' : 'issues.subtasks'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (children.isNotEmpty)
                Text(
                  context.t(
                    'issues.progressDone',
                    variables: {'done': '$done', 'total': '${children.length}'},
                  ),
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 10),
            HiveProgress(value: done / children.length),
          ],
          const SizedBox(height: 6),
          for (final c in children) _hierarchyRow(c, epic: isEpic),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                context.t(isEpic ? 'issues.noChildren' : 'issues.noSubtasks'),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (isEpic)
            _addChildButton(issue)
          else
            _SubtaskQuickAdd(onSubmit: (title) => _addSubtask(issue, title)),
        ],
      ),
    );
  }

  Widget _hierarchyRow(Issue child, {required bool epic}) {
    final assignee = child.assigneeId != null
        ? _names[child.assigneeId!]
        : null;
    return InkWell(
      onTap: () => _openLinkedIssue(child.readableId),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            // Sub-tasks get a quick "done" toggle; epic children open to edit.
            if (!epic)
              GestureDetector(
                onTap: () => _toggleChildState(child),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    _childDone(child)
                        ? LucideIcons.checkCheck
                        : LucideIcons.circle,
                    size: 17,
                    color: _childDone(child)
                        ? AppColors.success
                        : AppColors.inkFaint,
                  ),
                ),
              )
            else ...[
              TypeGlyph(type: child.type, size: 18),
              const SizedBox(width: 8),
            ],
            IdMono(child.readableId),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                child.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  decoration: _childDone(child)
                      ? TextDecoration.lineThrough
                      : null,
                  color: _childDone(child) ? AppColors.inkFaint : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            StateDotBadge(
              state: child.state,
              color: _projStateColor(_project, child.state),
            ),
            if (assignee != null) ...[
              const SizedBox(width: 10),
              HiveAvatar(name: assignee, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addChildButton(Issue epic) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => _addChild(epic),
      style: TextButton.styleFrom(foregroundColor: AppColors.stTodo),
      icon: const Icon(LucideIcons.plus, size: 16),
      label: Text(context.t('issues.addChild')),
    ),
  );

  Future<void> _addChild(Issue epic) async {
    final created = await showIssueForm(
      context,
      projectId: epic.projectId,
      parentId: epic.id,
      forcedType: 'STORY',
    );
    if (created != null) await _reloadHierarchy();
  }

  Future<void> _addSubtask(Issue parent, String title) async {
    if (title.trim().isEmpty) return;
    try {
      await _repo.createIssue({
        'projectId': parent.projectId,
        'title': title.trim(),
        'type': 'SUBTASK',
        'parentId': parent.id,
      });
      await _reloadHierarchy();
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    }
  }

  /// Flips a sub-task between its first resolved state and its first open state.
  Future<void> _toggleChildState(Issue child) async {
    final resolved = _project?.resolvedStates ?? const [];
    final states = _project?.stateNames ?? const [];
    final String target;
    if (child.resolved) {
      target = states.firstWhere(
        (s) => !resolved.contains(s),
        orElse: () => child.state,
      );
    } else {
      target = resolved.isNotEmpty ? resolved.first : child.state;
    }
    if (target == child.state) return;
    try {
      await _repo.updateIssue(child.id, {'state': target});
      await _reloadHierarchy();
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    }
  }

  Widget _detailsCard(Issue issue) {
    final multiAssignee =
        context.read<AppConfigBloc>().state.meta?.multiAssignee ?? false;
    final reporterName = issue.reporterId != null
        ? _names[issue.reporterId!]
        : null;
    final me = context.read<AuthBloc>().state.user;
    final sprintName = issue.sprintId != null
        ? _sprints.where((s) => s.id == issue.sprintId).firstOrNull?.name
        : null;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('issues.details'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          // Status
          _DetailRow(
            label: context.t('issues.status'),
            onTap: _pickStatus,
            child: StateDotBadge(
              state: issue.state,
              color: _projStateColor(_project, issue.state),
            ),
          ),
          // Assignee(s) + "assign to me"
          _DetailRow(
            label: context.t(
              issue.assigneeIds.length > 1
                  ? 'issues.assignees'
                  : 'issues.assignee',
            ),
            onTap: _pickAssignee,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (issue.assigneeIds.isEmpty)
                  _person(null, fallback: context.t('issues.unassigned'))
                else if (issue.assigneeIds.length == 1)
                  _person(
                    _names[issue.assigneeIds.first],
                    imageUrl: _avatars[issue.assigneeIds.first],
                    fallback: context.t('issues.unassigned'),
                  )
                else
                  // Multiple assignees: a compact stacked avatar group (matches
                  // the board/cards); the full list is in the picker on tap.
                  HiveAvatarStack(
                    names: [
                      for (final aid in issue.assigneeIds) _names[aid] ?? '?',
                    ],
                    imageUrls: [
                      for (final aid in issue.assigneeIds) _avatars[aid],
                    ],
                    size: 28,
                  ),
                if (me != null && !issue.assigneeIds.contains(me.id)) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _patch(
                      multiAssignee
                          ? {
                              'assigneeIds': [...issue.assigneeIds, me.id],
                            }
                          : {'assigneeId': me.id},
                    ),
                    child: Text(
                      context.t('issues.assignToMe'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.stTodo,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Priority
          _DetailRow(
            label: context.t('issues.priority'),
            onTap: _pickPriority,
            child: PriorityFlag(priority: issue.priority, withLabel: true),
          ),
          // Type — a sub-task's type is fixed; everything else is switchable.
          _DetailRow(
            label: context.t('issues.type'),
            onTap: issue.isSubtask ? null : _pickType,
            child: TypeBadge(type: issue.type),
          ),
          // Parent link — epics have no parent; standard issues attach to an
          // epic; sub-tasks attach to a standard issue.
          if (!issue.isEpic) _parentRow(issue),
          // Story points (Scrum estimate)
          _DetailRow(
            label: context.t('issues.storyPoints'),
            onTap: _pickStoryPoints,
            child: _pointsValue(issue.storyPoints),
          ),
          // Labels ("Stichwort")
          _DetailRow(
            label: context.t('issues.label'),
            onTap: _pickLabels,
            child: issue.tags.isEmpty
                ? Text(
                    context.t('issues.noLabels'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in issue.tags)
                        LabelTag(t, hue: _project?.hueForLabel(t)),
                    ],
                  ),
          ),
          // Sprint
          _DetailRow(
            label: context.t('issues.sprint'),
            onTap: _sprints.isEmpty ? null : _pickSprint,
            child: Text(
              sprintName ?? context.t('issues.noSprint'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sprintName != null
                    ? AppColors.stTodo
                    : AppColors.inkFaint,
              ),
            ),
          ),
          // Author / reporter (read-only)
          _DetailRow(
            label: context.t('issues.author'),
            last: true,
            child: _person(
              reporterName,
              imageUrl: issue.reporterId != null
                  ? _avatars[issue.reporterId!]
                  : null,
              fallback: context.t('issues.unassigned'),
            ),
          ),
        ],
      ),
    );
  }

  /// Read-only display of an issue's story-point estimate.
  Widget _pointsValue(int? points) {
    if (points == null) {
      return Text(
        context.t('issues.noValue'),
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Text(
      '$points',
      style: const TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _person(String? name, {required String fallback, String? imageUrl}) {
    if (name == null || name.isEmpty) {
      return Text(
        fallback,
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HiveAvatar(name: name, imageUrl: imageUrl, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _dateValue(DateTime? date, {required bool isStart}) {
    if (date == null) {
      return Text(
        context.t('issues.noValue'),
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          MaterialLocalizations.of(context).formatMediumDate(date),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () =>
              _patch({isStart ? 'clearStartDate' : 'clearDueDate': true}),
          child: Icon(LucideIcons.x, size: 15, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Widget _timeCard(Issue issue) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('issues.timeline'),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final logged = await showWorkLogSheet(context, issue.id);
                  if (logged == true) {
                    widget.onChanged?.call();
                    await _load();
                  }
                },
                child: Text(
                  context.t('issues.logTime'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Schedule (moved here from the Details panel).
          _DetailRow(
            label: context.t('issues.startDate'),
            onTap: (_) => _pickDate(isStart: true),
            child: _dateValue(issue.startDate, isStart: true),
          ),
          _DetailRow(
            label: context.t('issues.dueDate'),
            onTap: (_) => _pickDate(isStart: false),
            last: true,
            child: _dateValue(issue.dueDate, isStart: false),
          ),
          const SizedBox(height: 12),
          Text(
            context.t(
              'issues.spent',
              variables: {
                'spent': fmtDuration(issue.spentMinutes),
                'estimate': fmtDuration(issue.estimateMinutes),
              },
            ),
            style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
          ),
          for (final item in _workItems.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.timer,
                    size: 16,
                    color: AppColors.accentStrong,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${fmtDuration(item.durationMinutes)} · ${item.activityType}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (item.date != null)
                    Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatShortDate(item.date!),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Baseline issue provenance shown as a separate block directly beneath the
  /// Timeline card: when it was created and last touched, as short relative
  /// labels (e.g. "Created 2h ago" / "Updated 5m ago").
  Widget _issueMeta(Issue issue) {
    final created = issue.createdAt;
    // A brand-new issue has createdAt == updatedAt; showing "updated" then adds
    // no information, so only surface it once something was actually changed.
    final updated =
        (issue.updatedAt != null &&
            (created == null || !issue.updatedAt!.isAtSameMomentAs(created)))
        ? issue.updatedAt
        : null;
    if (created == null && updated == null) return const SizedBox.shrink();

    Widget line(IconData icon, String text) => Row(
      children: [
        Icon(icon, size: 13, color: AppColors.inkFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (created != null)
            line(LucideIcons.clock, _relLabel(created, created: true)),
          if (updated != null) ...[
            if (created != null) const SizedBox(height: 6),
            line(LucideIcons.history, _relLabel(updated, created: false)),
          ],
        ],
      ),
    );
  }

  /// "Created/Updated N units ago", fully written out (Jira-style) and
  /// localized with proper plurals; falls back to a "just …" phrasing under a
  /// minute.
  String _relLabel(DateTime at, {required bool created}) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) {
      return context.t(
        created ? 'issues.createdJustNow' : 'issues.updatedJustNow',
      );
    }

    final (String unitKey, int count) = switch (d) {
      _ when d.inMinutes < 60 => ('issues.relMinutes', d.inMinutes),
      _ when d.inHours < 24 => ('issues.relHours', d.inHours),
      _ when d.inDays < 7 => ('issues.relDays', d.inDays),
      _ when d.inDays < 30 => ('issues.relWeeks', d.inDays ~/ 7),
      _ when d.inDays < 365 => ('issues.relMonths', d.inDays ~/ 30),
      _ => ('issues.relYears', d.inDays ~/ 365),
    };

    final time = context.t(unitKey, count: count, variables: {'count': count});
    return context.t(
      created ? 'issues.createdAgo' : 'issues.updatedAgo',
      variables: {'time': time},
    );
  }

  /// True when the host floats the composer (sheet sticky bar / route overlay)
  /// rather than showing it inline in the activity card.
  bool composerFloats(BuildContext context) => widget.floatingComposer;

  /// Whether the issue has finished loading (so the host can defer the floating
  /// composer until there is something to comment on).
  bool get hasIssue => _issue != null;

  /// The full-screen route's pinned top bar (back · id/state · minimize · trash).
  /// Rendered by [IssueDetailScreen] as a top overlay — NOT inline in the body —
  /// so the actions stay reachable when the comment thread scrolls long. [glass]
  /// (0→1, driven by scroll offset) fades the shell-style progressive blur +
  /// scrim in as content scrolls up under it, so at the very top the bar is
  /// invisible chrome and only frosts once you start scrolling.
  Widget buildRouteTopBar(BuildContext context, {required double glass}) {
    final issue = _issue;
    if (issue == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final g = glass.clamp(0.0, 1.0);
    final scrimTop = (dark ? 0.5 : 0.16) * g;
    return SizedBox(
      height: topInset + kRouteTopBarHeight,
      child: Stack(
        children: [
          // Progressive blur, faded in by scaling maxSigma with scroll (0 → no
          // filter → perfectly sharp at the top of the page). Non-interactive.
          Positioned.fill(
            child: IgnorePointer(
              child: ProgressiveBlur(maxSigma: (dark ? 30.0 : 26.0) * g),
            ),
          ),
          // Darkening scrim (fades to transparent at the bottom edge so the bar
          // dissolves into the content instead of a hard cut-off).
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: scrimTop),
                      Colors.black.withValues(alpha: scrimTop * 0.4),
                      Colors.black.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // The bar row itself, pinned just below the status bar — always visible
          // and tappable regardless of [glass].
          Positioned(
            left: 0,
            right: 0,
            top: topInset,
            child: _RouteTopBar(
              issue: issue,
              busy: _busy,
              stateColor: _projStateColor(_project, issue.state),
              link: issueWebLink(_repo.apiBaseUrl, issue.linkId),
              onMinimize: widget.canMinimize ? _minimizeToModal : null,
              onDelete: () => _confirmDelete(issue),
              onClose: _closeRoute,
            ),
          ),
        ],
      ),
    );
  }

  /// The docked composer, pinned to the bottom by the host (sheet: sticky bar;
  /// route: Stack overlay). Phone/narrow: spans the whole width. Tablet/desktop
  /// (2-column): constrained to the comment column's width + left-aligned with
  /// the body, so it floats only over the comment section, never the details
  /// column. [deviceSafeArea] adds the home-indicator inset (sheet); the route
  /// instead positions above the nav via `bottomGutter`, so it passes false.
  Widget buildFloatingComposer(
    BuildContext context, {
    bool deviceSafeArea = true,
  }) {
    // The floating composer lives in a separate subtree (the sheet's sticky
    // action bar / the route's Stack overlay) from the body, so it must re-supply
    // the SmartLinkScope — otherwise the composer's MentionField can't resolve
    // `@`-mentions/smart-links (it reads the resolver from context).
    final issue = _issue;
    if (issue == null) return const SizedBox.shrink();
    // Wolt lifts the sticky action bar above the keyboard whenever *any* field
    // is focused. That's wrong for the comment composer: while the keyboard is
    // up for another input (sub-task / linked-issue / inline title-edit), the
    // composer would still ride above it. Only keep it mounted when the keyboard
    // is down or the comment field itself is the reason it's up.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardUp && !_commentFocus.hasFocus) return const SizedBox.shrink();
    return SmartLinkScope(
      resolver: _buildResolver(issue),
      child: LayoutBuilder(
        builder: (context, c) {
          // Content width mirrors the body's inner width (20px padding / side).
          final contentW = c.maxWidth - 40;
          if (contentW < 680) {
            // Phone / narrow: full-width dock over the whole area.
            return _composerDock(deviceSafeArea: deviceSafeArea, horizontal: 16);
          }
          // 2-column: match the left column (flex 3 of 3+2 with an 18px gutter),
          // aligned with the body's left padding.
          final leftW = (contentW - 18) * 3 / 5;
          return Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: leftW,
                child: _composerDock(
                  deviceSafeArea: deviceSafeArea,
                  horizontal: 0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The docked composer chrome: a bottom-up fade into the translucent modal
  /// surface (so the feed dissolves behind it) wrapping the glass composer.
  /// Bottom-anchored at the modal edge, so the inline format editor grows
  /// *upward* in place.
  Widget _composerDock({required bool deviceSafeArea, double horizontal = 16}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Fade INTO the *translucent* modal surface (glassWoltSurface floats content
    // on `canvas @ 0.88/0.84`), not full-opacity canvas — else it reads as a
    // lighter, hard-edged box instead of a seamless dissolve.
    final wash = _panelWashAlpha(dark);
    final padding = EdgeInsets.fromLTRB(
      horizontal,
      26,
      horizontal,
      deviceSafeArea
          ? (MediaQuery.viewPaddingOf(context).bottom <= 0
                ? 16
                : MediaQuery.viewPaddingOf(context).bottom)
          : 12,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            // Horizontal mask: taper the wash's alpha over the outer ~32px on
            // each side, so the left/right edges dissolve too instead of
            // showing a hard vertical seam against the feed.
            shaderCallback: (rect) {
              final f = (32 / rect.width).clamp(0.0, 0.5);
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0x00FFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0, f, 1 - f, 1],
              ).createShader(rect);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.canvas.withValues(alpha: 0),
                    AppColors.canvas.withValues(alpha: wash * 0.7),
                    AppColors.canvas.withValues(alpha: wash),
                    AppColors.canvas.withValues(alpha: wash),
                  ],
                  stops: const [0, 0.35, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: _commentComposer()),
      ],
    );
  }

  /// The modal surface's canvas alpha (see `glassWoltSurface`), so the composer
  /// dock's fade dissolves into the *actual* translucent surface instead of
  /// painting an opaque, mismatched box over it.
  double _panelWashAlpha(bool dark) => dark ? 0.84 : 0.88;

  Widget _activityCard() {
    final filter = _activityFilter;
    // Hide the inline composer when it floats (phone sheet) — it's rendered in
    // the sticky action bar instead; otherwise keep it inline.
    final showComposer =
        filter != _ActivityFilter.history && !composerFloats(context);
    return SoftCard(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: Colors.transparent),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('issues.activity'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          // Filter tabs: All · Comments · History
          _ActivityTabs(
            value: filter,
            onChanged: (f) => setState(() => _activityFilter = f),
          ),
          const SizedBox(height: 14),
          ..._activityItems(filter),
          if (showComposer) ...[const SizedBox(height: 4), _commentComposer()],
        ],
      ),
    );
  }

  /// Liquid-Glass comment composer (chat-style): `+` attachment menu, mic↔send
  /// morph, live voice recording and a Markdown format toolbar. Wraps a
  /// [MentionField] so `@`-smart-link autocomplete keeps working.
  Widget _commentComposer() {
    return GlassCommentComposer(
      controller: _comment,
      focusNode: _commentFocus,
      actions: _commentActions,
      editing: _editingComment != null,
      onCancelEdit: _cancelEditComment,
      onSubmitText: _submitComment,
      onSendVoice: _sendVoiceComment,
      onAttach: _onComposerAttach,
    );
  }

  /// Handles the `+` menu picks. Camera/gallery insert an inline Markdown photo
  /// into the comment (the body is Markdown, like the editor); "Anhang" uploads
  /// any file — including video/PDF — as an issue attachment.
  Future<void> _onComposerAttach(ComposerAttach kind) async {
    switch (kind) {
      case ComposerAttach.camera:
        await insertCommentPhoto(context, _commentActions, ImageSource.camera);
      case ComposerAttach.gallery:
        await insertCommentPhoto(context, _commentActions, ImageSource.gallery);
      case ComposerAttach.file:
        // Drive the attachments section's own optimistic upload so the new tile
        // appears live (no reload, no dependence on the SSE `added` event).
        final section = _attachmentsKey.currentState;
        if (section != null) {
          await section.pickFiles();
        } else {
          // Fallback (section not mounted): blind upload + list refresh.
          await attachFileToIssue(
            context,
            widget.issueId,
            onChanged: widget.onChanged,
          );
        }
    }
  }

  /// Uploads a recorded voice message as a comment, then refreshes to the newest
  /// page so the playable bubble appears at the bottom of the thread.
  Future<void> _sendVoiceComment(VoiceRecording recording) async {
    try {
      await _repo.addVoiceComment(
        widget.issueId,
        bytes: recording.bytes,
        mime: recording.mime,
        durationMs: recording.durationMs,
        peaks: recording.peaks,
      );
      final p = await _repo.comments(widget.issueId);
      if (!mounted) return;
      setState(() {
        _comments = p.items.reversed.toList();
        _commentsTotal = p.total;
        _commentsPage = 0;
      });
      _revealNewestComment();
      widget.onChanged?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.t('comments.voiceFailed'))),
      );
    }
  }

  /// Builds the activity feed for [filter]:
  ///  • comments → comments oldest-first (chat style)
  ///  • history  → change events newest-first
  ///  • all      → both, merged newest-first
  List<Widget> _activityItems(_ActivityFilter filter) {
    final me = context.read<AuthBloc>().state.user;
    final chat = CommentThread.chatMode(context);
    // Same bubble as the Comments tab, so comments look identical in every tab
    // (voice comments stay playable in the merged "All" feed too).
    Widget commentTile(IssueComment c) => CommentBubbleRow(
      comment: c,
      me: chat && me != null && c.authorId == me.id,
      name: _names[c.authorId] ?? c.authorId,
      avatarUrl: _avatars[c.authorId],
      loadVoice: () => _repo.voiceCommentAudio(widget.issueId, c.id),
      canManage: me != null && c.authorId == me.id,
      onEdit: () => _promptEditComment(c),
      onDelete: () => _deleteComment(c),
    );
    final issueIds = {
      for (final i in _projectIssues.values) i.id: i.readableId,
    };
    Widget activityTile(IssueActivity a) => _ActivityTile(
      activity: a,
      actorName: a.actorId != null
          ? (_names[a.actorId!] ?? a.actorId!)
          : context.t('issues.systemActor'),
      names: _names,
      sprintNames: _sprintNames,
      issueIds: issueIds,
    );

    Widget loadMore(String label, VoidCallback onTap) =>
        _LoadMoreTile(label: label, loading: _loadingMore, onTap: onTap);

    switch (filter) {
      case _ActivityFilter.comments:
        if (_comments.isEmpty) {
          return [_emptyActivity(context.t('issues.activityEmpty'))];
        }
        return [
          // Older comments live above (chat is oldest→newest), so the control
          // sits at the top of the thread.
          if (_hasMoreComments)
            loadMore(context.t('issues.loadEarlier'), _loadMoreComments),
          // Liquid-Glass chat thread (text + playable voice bubbles).
          CommentThread(
            comments: _comments,
            meId: me?.id,
            nameFor: (id) => _names[id] ?? id,
            avatarFor: (id) => _avatars[id],
            loadVoice: (c) =>
                () => _repo.voiceCommentAudio(widget.issueId, c.id),
            canManage: (c) => me != null && c.authorId == me.id,
            onEdit: _promptEditComment,
            onDelete: _deleteComment,
          ),
        ];
      case _ActivityFilter.history:
        if (_activity.isEmpty) {
          return [_emptyActivity(context.t('issues.historyEmpty'))];
        }
        return [
          for (final a in _activity) activityTile(a),
          if (_hasMoreActivity)
            loadMore(context.t('issues.loadMore'), _loadMoreActivity),
        ];
      case _ActivityFilter.all:
        // Merge by timestamp, newest first.
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        final merged = <({DateTime time, Widget tile})>[
          for (final c in _comments)
            (time: c.createdAt ?? epoch, tile: commentTile(c)),
          for (final a in _activity)
            (time: a.createdAt ?? epoch, tile: activityTile(a)),
        ]..sort((x, y) => y.time.compareTo(x.time));
        if (merged.isEmpty) {
          return [_emptyActivity(context.t('issues.activityEmpty'))];
        }
        return [
          for (final m in merged) m.tile,
          if (_hasMoreComments || _hasMoreActivity)
            loadMore(context.t('issues.loadMore'), _loadMoreAll),
        ];
    }
  }

  /// "All" tab: pull the next older page of whichever streams still have more.
  Future<void> _loadMoreAll() async {
    if (_loadingMore) return;
    if (_hasMoreComments) await _loadMoreComments();
    if (_hasMoreActivity) await _loadMoreActivity();
  }

  Widget _emptyActivity(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Center(
      child: Text(
        message,
        style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
      ),
    ),
  );

  // ── pickers ────────────────────────────────────────────────────────────

  Future<void> _pickStatus(Rect anchor) async {
    final states = _project?.stateNames ?? [_issue!.state];
    final chosen = await _showOptions<String>(
      title: context.t('issues.status'),
      anchorRect: anchor,
      options: [
        for (final s in states)
          (
            value: s,
            child: StateDotBadge(state: s, color: _projStateColor(_project, s)),
          ),
      ],
    );
    if (chosen != null) await _patch({'state': chosen});
  }

  Future<void> _pickPriority(Rect anchor) async {
    const priorities = ['SHOWSTOPPER', 'CRITICAL', 'MAJOR', 'NORMAL', 'MINOR'];
    final chosen = await _showOptions<String>(
      title: context.t('issues.priority'),
      anchorRect: anchor,
      options: [
        for (final p in priorities)
          (value: p, child: PriorityFlag(priority: p, withLabel: true)),
      ],
    );
    if (chosen != null) await _patch({'priority': chosen});
  }

  Future<void> _pickType(Rect anchor) async {
    // SUBTASK is never a free pick — it is created only via the sub-task panel.
    const types = ['STORY', 'TASK', 'BUG', 'FEATURE', 'EPIC'];
    final chosen = await _showOptions<String>(
      title: context.t('issues.type'),
      anchorRect: anchor,
      options: [for (final t in types) (value: t, child: TypeBadge(type: t))],
    );
    if (chosen != null) await _patch({'type': chosen});
  }

  /// The "Epic" (standard issues) / "Parent" (sub-tasks) detail row. Value is
  /// the immediate ancestor; tapping opens the parent picker.
  Widget _parentRow(Issue issue) {
    final parent = _hierarchy.ancestors.isNotEmpty
        ? _hierarchy.ancestors.last
        : null;
    return _DetailRow(
      label: issue.isSubtask
          ? context.t('issues.parent')
          : context.t('issues.epic'),
      onTap: (anchor) => _pickParent(issue, anchor),
      child: parent == null
          ? Text(
              issue.isSubtask ? '—' : context.t('issues.noEpic'),
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            )
          : _parentChip(parent),
    );
  }

  Widget _parentChip(Issue parent) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TypeGlyph(type: parent.type, size: 18),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          '${parent.readableId}  ${parent.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  Future<void> _pickParent(Issue issue, Rect anchor) async {
    // On-the-fly parent assignment: an inline popover with a debounced, paginated
    // server search (recent items first). Sub-tasks attach to a standard issue;
    // standard issues attach to an epic.
    final result = await showEpicSearchPopover(
      context,
      anchorRect: anchor,
      projectId: issue.projectId,
      currentIssueId: issue.id,
      forSubtask: issue.isSubtask,
      hasCurrentParent: _hierarchy.ancestors.isNotEmpty,
    );
    if (result == null || !mounted) return;
    // `_patch` → PATCH /issues/{id} → `_reloadHierarchy`, so the breadcrumb and
    // parent row refresh immediately after the write.
    await _patch({'parentId': result.clear ? '' : result.issue!.id});
  }

  Future<void> _pickLabels(Rect anchor) async {
    final issue = _issue;
    if (issue == null) return;
    final available = <String>{
      ...?_project?.labelNames,
      ...issue.tags,
    }.where((l) => !_deletedLabels.contains(l)).toList();
    var didDelete = false;
    final result = await showLabelPicker(
      context,
      anchor: anchor,
      available: available,
      selected: issue.tags.where((l) => !_deletedLabels.contains(l)).toList(),
      onDelete: (l) async {
        await _repo.deleteProjectLabel(issue.projectId, l);
        _deletedLabels.add(l);
        didDelete = true;
      },
    );
    if (result != null) {
      await _patch({'tags': result});
    } else if (didDelete && mounted) {
      // Dismissed without saving, but a label was deleted server-side — pull
      // the fresh issue so its tag chips reflect the removal.
      try {
        final fresh = await _repo.issue(widget.issueId);
        if (mounted) setState(() => _issue = fresh);
      } catch (_) {
        /* next full load reflects server truth */
      }
    }
  }

  static const _noSprint = '__none__';

  Future<void> _pickSprint(Rect anchor) async {
    final chosen = await _showOptions<String>(
      title: context.t('issues.sprint'),
      anchorRect: anchor,
      options: [
        (
          value: _noSprint,
          child: Text(
            context.t('issues.noSprint'),
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
        for (final s in _sprints) (value: s.id, child: Text(s.name)),
      ],
    );
    if (chosen != null) {
      // Empty string clears the sprint server-side (null is ignored by PATCH).
      await _patch({'sprintId': chosen == _noSprint ? '' : chosen});
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _issue!.startDate : _issue!.dueDate;
    final picked = await showGlassDatePicker(
      context,
      title: context.t(isStart ? 'issues.startDate' : 'issues.dueDate'),
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final iso = picked.toIso8601String().substring(0, 10);
      await _patch({isStart ? 'startDate' : 'dueDate': iso});
    }
  }

  // Anchor unused: estimate opens as a centered glass dialog, not a popover.
  Future<void> _pickStoryPoints(Rect anchor) async {
    final issue = _issue;
    if (issue == null) return;
    final result = await showStoryPointsDialog(
      context,
      current: issue.storyPoints,
      subtitle: '${issue.readableId} · ${issue.title}',
    );
    if (result != null) {
      await _patch(
        result.points == null
            ? {'clearStoryPoints': true}
            : {'storyPoints': result.points},
      );
    }
  }

  // Anchor unused: the people picker is a taller search list, kept as a sheet.
  Future<void> _pickAssignee(Rect anchor) async {
    final me = context.read<AuthBloc>().state.user;
    final multi =
        context.read<AppConfigBloc>().state.meta?.multiAssignee ?? false;
    // Tablet/desktop: an anchored, searchable popover beside the field (like the
    // board filter). Phone: the bottom sheet. Both reuse _PeoplePicker.
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    Widget picker(BuildContext sheetContext) => _PeoplePicker(
      anchored: wide,
      users: _users,
      meId: me?.id,
      multiSelect: multi,
      initialSelected: (_issue?.assigneeIds ?? const []).toSet(),
      // Multi mode: stay open, persist the whole set on every toggle.
      onSelectionChanged: (ids) => _patch({'assigneeIds': ids.toList()}),
      onUnassign: () {
        Navigator.of(sheetContext).pop();
        // Empty string clears the assignee (PATCH ignores null).
        _patch({'assigneeId': ''});
      },
      onAssignMe: me == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              _patch({'assigneeId': me.id});
            },
      onSelect: (id) {
        Navigator.of(sheetContext).pop();
        _patch({'assigneeId': id});
      },
    );

    if (wide) {
      await showGlassAnchoredPopover<void>(
        context,
        anchorRect: anchor,
        width: 340,
        maxHeight: 520,
        builder: picker,
      );
      return;
    }
    // _PeoplePicker draws its own grab handle, so suppress the helper's.
    await showGlassBottomSheet<void>(
      context,
      showHandle: false,
      builder: picker,
    );
  }

  Future<T?> _showOptions<T>({
    required String title,
    required List<({T value, Widget child})> options,
    Rect? anchorRect,
  }) {
    return showGlassOptions<T>(
      context,
      title: title,
      options: options,
      anchorRect: anchorRect,
    );
  }

  Future<void> _confirmDelete(Issue issue) async {
    final confirmed = await showGlassModal<bool>(
      context,
      width: 420,
      builder: (_) => _DeleteIssueConfirm(issue: issue),
    );
    if (confirmed == true) {
      try {
        await _repo.deleteIssue(issue.id);
        widget.onChanged?.call();
        if (mounted) Navigator.of(context).maybePop();
      } on ApiFailure catch (failure) {
        _toast(failure.message);
      }
    }
  }
}

// ─────────────────────── Delete confirmation ───────────────────────────────

/// Destructive confirm presented on the app's Liquid-Glass modal material
/// (matches the Teams `ModalShell`/`ModalFooter` language: danger icon chip,
/// brand-font title, hairline-divided footer with a red primary action).
class _DeleteIssueConfirm extends StatelessWidget {
  const _DeleteIssueConfirm({required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.trash2,
                  size: 20,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('issues.deleteTitle'),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t(
                        'issues.deleteBody',
                        variables: {'id': issue.readableId},
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    context.t('common.cancel'),
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: Text(context.t('common.delete')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Destructive confirm for deleting one's own comment. Mirrors the issue
/// delete confirm's Liquid-Glass language (danger chip, hairline footer).
class _DeleteCommentConfirm extends StatelessWidget {
  const _DeleteCommentConfirm();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.trash2,
                  size: 20,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('issues.deleteCommentTitle'),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('issues.deleteCommentBody'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    context.t('common.cancel'),
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: Text(context.t('common.delete')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Detail row ────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.child,
    this.onTap,
    this.last = false,
  });

  final String label;
  final Widget child;

  /// Tapped to edit the field. Receives the row's global rect so the picker can
  /// anchor a dropdown popover beside it on wide screens.
  final void Function(Rect anchorRect)? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return InkWell(
      onTap: tap == null
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              final rect = (box != null && box.hasSize)
                  ? box.localToGlobal(Offset.zero) & box.size
                  : Rect.zero;
              tap(rect);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: AppColors.hairline2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
            if (onTap != null)
              Icon(
                LucideIcons.chevronsUpDown,
                size: 16,
                color: AppColors.inkFaint,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Sub-task quick-add ────────────────────────────

/// "Add a sub-task" affordance — collapsed to a single "+" row by default so it
/// takes no vertical space, then expands into an inline title field on tap. The
/// field submits on Enter or via the "+" button and stays open for rapid entry;
/// it collapses again on Escape or when left empty.
class _SubtaskQuickAdd extends StatefulWidget {
  const _SubtaskQuickAdd({required this.onSubmit});

  final Future<void> Function(String title) onSubmit;

  @override
  State<_SubtaskQuickAdd> createState() => _SubtaskQuickAddState();
}

class _SubtaskQuickAddState extends State<_SubtaskQuickAdd> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _open = true);
    _focus.requestFocus();
  }

  void _collapse() {
    _ctrl.clear();
    setState(() => _open = false);
  }

  Future<void> _submit() async {
    final value = _ctrl.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.onSubmit(value);
    if (!mounted) return;
    _ctrl.clear();
    setState(() => _busy = false);
    // Keep the field open + focused so several sub-tasks can be added quickly.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return InkWell(
        onTap: _expand,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(LucideIcons.plus, size: 16, color: AppColors.stTodo),
              const SizedBox(width: 8),
              Text(
                context.t('issues.addSubtask'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.stTodo,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        // The "+" is the submit button while the field is open.
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: HiveLoader(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            onPressed: _submit,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(LucideIcons.plus, size: 18, color: AppColors.stTodo),
          ),
        const SizedBox(width: 4),
        Expanded(
          child: Focus(
            onKeyEvent: (_, event) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _collapse();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) {
                if (_ctrl.text.trim().isEmpty) _collapse();
              },
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: context.t('issues.subtaskHint'),
                hintStyle: TextStyle(fontSize: 13.5, color: AppColors.inkFaint),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _collapse,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(LucideIcons.x, size: 16, color: AppColors.inkFaint),
        ),
      ],
    );
  }
}

// ─────────────────────────── Option picker ─────────────────────────────────

/// Single-choice picker shared by the create body. Delegates to the responsive
/// [showGlassOptions]: an anchored dropdown beside the field on wide screens, a
/// bottom sheet on phones.
Future<T?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required List<({T value, Widget child})> options,
  Rect? anchorRect,
}) {
  return showGlassOptions<T>(
    context,
    title: title,
    options: options,
    anchorRect: anchorRect,
  );
}

// ─────────────────────────── Create body ───────────────────────────────────

/// Lifecycle of the create-issue save button, shared between the body (which
/// drives it) and the wolt sticky action bar (which renders it).
enum IssueCreatePhase { idle, saving, success }

/// Bridges [IssueCreateBody] and the sticky save bar: the body publishes the
/// current [phase] and the bar reads it; the bar calls [submit] on tap, which
/// runs the form validation (so the button stays pressable to surface errors).
class IssueCreateController extends ChangeNotifier {
  IssueCreatePhase _phase = IssueCreatePhase.idle;
  IssueCreatePhase get phase => _phase;
  set phase(IssueCreatePhase value) {
    if (value != _phase) {
      _phase = value;
      notifyListeners();
    }
  }

  /// Wired by the body in initState; invoked by the sticky save button.
  Future<void> Function()? submit;
}

/// The same two-column layout as [IssueDetailBody], but for CREATING an issue:
/// title + Markdown description on the left, an editable details card
/// (project · status · assignee · priority · type · sprint · dates) on the
/// right. The save button lives in the wolt sticky action bar and is driven via
/// [IssueCreateController]. Hosted by `showIssueForm`.
class IssueCreateBody extends StatefulWidget {
  const IssueCreateBody({
    super.key,
    required this.controller,
    this.projectId,
    this.initialState,
    this.initialSprintId,
    this.parentId,
    this.forcedType,
    required this.onCreated,
  });

  final IssueCreateController controller;
  final String? projectId;
  final String? initialState;
  final String? initialSprintId;

  /// Pre-selected parent issue (an epic for child issues, a standard issue for
  /// sub-tasks). When set, the parent row is locked.
  final String? parentId;

  /// Forces and locks the issue type (e.g. `STORY` for an epic's child,
  /// `SUBTASK` for a sub-task). When set, the Type row is locked.
  final String? forcedType;

  final ValueChanged<Issue> onCreated;

  @override
  State<IssueCreateBody> createState() => IssueCreateBodyState();
}

class IssueCreateBodyState extends State<IssueCreateBody> {
  HinataRepository get _repo => context.read<HinataRepository>();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  List<Project> _projects = const [];
  List<DirectoryUser> _users = const [];
  List<Sprint> _sprints = const [];
  // Project issues (keyed by readable id) feed the description editor's
  // `@`-menu and resolve `{{issue:…}}` chips in the preview; KB articles come
  // from the shared seed. Reloaded whenever the selected project changes.
  Map<String, Issue> _projectIssues = const {};
  KnowledgeRepository get _knowledge => context.read<KnowledgeRepository>();

  String? _projectId;
  String? _state;
  final List<String> _assigneeIds = [];
  String _priority = 'NORMAL';
  String _type = 'TASK';
  String? _parentId;
  String? _sprintId;
  int? _storyPoints;
  DateTime? _startDate;
  DateTime? _dueDate;
  List<String> _labels = const [];
  final Set<String> _deletedLabels = {};

  bool _loading = true;
  String? _error;

  // Validation stays silent until the first save attempt, then switches to
  // live (onUserInteraction) validation — Flutter's standard form pattern.
  final _formKey = GlobalKey<FormState>();
  bool _autovalidate = false;

  static const _none = '__none__';

  Project? get _project =>
      _projects.where((p) => p.id == _projectId).firstOrNull;
  Map<String, String> get _names => {
    for (final u in _users) u.id: u.displayName,
  };

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _state = widget.initialState;
    _sprintId = widget.initialSprintId;
    _parentId = widget.parentId;
    if (widget.forcedType != null) _type = widget.forcedType!;
    widget.controller.submit = _save;
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_repo.projects(), _repo.users()]);
      _projects = results[0] as List<Project>;
      _users = results[1] as List<DirectoryUser>;
      _projectId ??= _projects.firstOrNull?.id;
      await _loadProjectScoped();
      if (mounted) setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = failure.message;
        });
      }
    }
  }

  /// Loads sprints, project issues (for the `@`-menu / smart-links) + a default
  /// status for the selected project.
  Future<void> _loadProjectScoped() async {
    _state ??= _project?.stateNames.firstOrNull;
    _sprints = const [];
    _projectIssues = const {};
    final pid = _projectId;
    if (pid == null) return;
    try {
      _sprints = await _repo.sprintsForProject(pid);
    } catch (_) {
      _sprints = const [];
    }
    // Project issues power the description `@`-menu + `{{issue:…}}` chips; the
    // shared KB seed backs `{{doc:…}}`. Both best-effort.
    try {
      final all = await _repo.allIssues(projectId: pid);
      _projectIssues = {for (final i in all) i.readableId: i};
    } catch (_) {
      _projectIssues = const {};
    }
    try {
      await _knowledge.init();
    } catch (_) {
      /* smart-link doc resolution falls back to "not found" */
    }
  }

  Future<void> _onProjectChanged(String id) async {
    setState(() {
      _projectId = id;
      _state = null; // reset to the new project's default
      _sprintId = null;
    });
    await _loadProjectScoped();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    // Run the form validators; from now on validate live as the user types.
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!_autovalidate) setState(() => _autovalidate = true);
    if (!formValid || _projectId == null) {
      if (_projectId == null) {
        setState(() => _error = context.t('errors.required'));
      }
      return;
    }
    final title = _titleCtrl.text.trim();
    widget.controller.phase = IssueCreatePhase.saving;
    setState(() => _error = null);
    try {
      final created = await _repo.createIssue({
        'projectId': _projectId,
        'title': title,
        'description': _descCtrl.text,
        'type': _type,
        'priority': _priority,
        if (_state != null) 'state': _state,
        if (_assigneeIds.isNotEmpty) 'assigneeIds': _assigneeIds,
        if (_parentId != null) 'parentId': _parentId,
        if (_sprintId != null) 'sprintId': _sprintId,
        if (_storyPoints != null) 'storyPoints': _storyPoints,
        if (_startDate != null)
          'startDate': _startDate!.toIso8601String().substring(0, 10),
        if (_dueDate != null)
          'dueDate': _dueDate!.toIso8601String().substring(0, 10),
        if (_labels.isNotEmpty) 'tags': _labels,
      });
      if (!mounted) return;
      // Hold on the green check briefly before handing off to the detail view.
      widget.controller.phase = IssueCreatePhase.success;
      await Future<void>.delayed(const Duration(milliseconds: 750));
      widget.onCreated(created);
    } on ApiFailure catch (failure) {
      if (mounted) {
        widget.controller.phase = IssueCreatePhase.idle;
        setState(() => _error = failure.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: HiveLoader()),
      );
    }
    return SmartLinkScope(
      resolver: _buildResolver(),
      child: Form(
        key: _formKey,
        autovalidateMode: _autovalidate
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Padding(
          // Bottom clearance for the pinned save bar (which overlays the content):
          // ~save button + its padding + the device safe-area inset.
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            88 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final left = _contentCard();
                  final right = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _detailsCard(),
                      const SizedBox(height: 14),
                      _timelineCard(),
                    ],
                  );
                  if (c.maxWidth >= 680) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 18),
                        Expanded(flex: 2, child: right),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 14), right],
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── smart-link wiring (mirrors IssueDetailBody) ──────────────────────────

  /// Resolver for the description editor's `@`-menu + preview chips: issues +
  /// people from the backend (project issues + directory users), articles from
  /// the shared KB seed. Rebuilt per frame (cheap) so it tracks the freshly
  /// loaded project issues / users.
  IssueLinkResolver _buildResolver() => IssueLinkResolver(
    issuesByReadable: _projectIssues,
    users: _users,
    knowledgeRepo: _knowledge,
    stateColorFor: (s) =>
        _projStateColor(_project, s) ?? AppColors.stateColor(s),
    onOpenIssue: _openLinkedIssue,
    onOpenDoc: _openArticle,
  );

  /// Opens the real issue for a readable id (e.g. `HIN-12`): tries the loaded
  /// project issues first, then a backend search; silently ignores no match.
  Future<void> _openLinkedIssue(String readableId) async {
    var match = _projectIssues[readableId];
    if (match == null) {
      try {
        final res = await _repo.issues(query: readableId, size: 20);
        match = res.issues.where((i) => i.readableId == readableId).firstOrNull;
      } on ApiFailure {
        return;
      }
    }
    if (!mounted || match == null) return;
    await showIssueDetailSheet(context, issueId: match.id);
  }

  /// Opens a KB article (doc smart-link) on the `/knowledge/:id` route. The
  /// create modal stays mounted underneath so the draft isn't lost.
  void _openArticle(String articleId) =>
      GoRouter.of(context).push('/knowledge/$articleId');

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.inkFaint,
    ),
  );

  Widget _contentCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.t('issues.title')),
        const SizedBox(height: 8),
        TextFormField(
          controller: _titleCtrl,
          maxLines: null,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            // height: 1.25,
          ),
          decoration: InputDecoration(
            hintText: context.t('issues.title'),
            errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? context.t('errors.required')
              : null,
        ),
        const SizedBox(height: 18),
        // Same authoring power as the issue detail + KB: shared MarkdownToolbar,
        // `@`-smart-links (issues · articles · people), Editor/Preview tabs.
        IssueDescriptionEditor(
          controller: _descCtrl,
          label: _sectionLabel(context.t('issues.description')),
        ),
      ],
    );
  }

  Widget _detailsCard() {
    final sprintName = _sprints
        .where((s) => s.id == _sprintId)
        .firstOrNull
        ?.name;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('issues.details'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _DetailRow(
            label: context.t('issues.project'),
            onTap: _pickProject,
            child: Text(
              _project != null
                  ? '${_project!.key} – ${_project!.name}'
                  : context.t('errors.required'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          _DetailRow(
            label: context.t('issues.status'),
            onTap: (_project?.workflowStates.isEmpty ?? true)
                ? null
                : _pickStatus,
            child: _state != null
                ? StateDotBadge(
                    state: _state!,
                    color: _projStateColor(_project, _state!),
                  )
                : Text(
                    context.t('issues.noValue'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  ),
          ),
          _DetailRow(
            label: context.t(
              _assigneeIds.length > 1 ? 'issues.assignees' : 'issues.assignee',
            ),
            onTap: _pickAssignee,
            child: _assigneeIds.isEmpty
                ? _person(null, fallback: context.t('issues.unassigned'))
                : _assigneeIds.length == 1
                ? _person(
                    _names[_assigneeIds.first],
                    fallback: context.t('issues.unassigned'),
                  )
                : HiveAvatarStack(
                    names: [for (final aid in _assigneeIds) _names[aid] ?? '?'],
                    size: 28,
                  ),
          ),
          _DetailRow(
            label: context.t('issues.priority'),
            onTap: _pickPriority,
            child: PriorityFlag(priority: _priority, withLabel: true),
          ),
          _DetailRow(
            // A forced type (epic child / sub-task) is locked.
            label: context.t('issues.type'),
            onTap: widget.forcedType != null ? null : _pickType,
            child: TypeBadge(type: _type),
          ),
          // Epic link for standard issues; sub-tasks arrive with a fixed parent.
          if (_type.toUpperCase() != 'EPIC') _createParentRow(),
          _DetailRow(
            label: context.t('issues.storyPoints'),
            onTap: _pickStoryPoints,
            child: _pointsValue(_storyPoints),
          ),
          _DetailRow(
            label: context.t('issues.label'),
            onTap: _pickLabels,
            child: _labels.isEmpty
                ? Text(
                    context.t('issues.noLabels'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in _labels)
                        LabelTag(t, hue: _project?.hueForLabel(t)),
                    ],
                  ),
          ),
          _DetailRow(
            label: context.t('issues.sprint'),
            onTap: _sprints.isEmpty ? null : _pickSprint,
            last: true,
            child: Text(
              sprintName ?? context.t('issues.noSprint'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sprintName != null
                    ? AppColors.stTodo
                    : AppColors.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The "Timeline" card for the create form: schedule (start / due dates).
  Widget _timelineCard() {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('issues.timeline'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _DetailRow(
            label: context.t('issues.startDate'),
            onTap: (_) => _pickDate(isStart: true),
            child: _dateValue(_startDate, isStart: true),
          ),
          _DetailRow(
            label: context.t('issues.dueDate'),
            onTap: (_) => _pickDate(isStart: false),
            last: true,
            child: _dateValue(_dueDate, isStart: false),
          ),
        ],
      ),
    );
  }

  /// Read-only display of the chosen story-point estimate.
  Widget _pointsValue(int? points) {
    if (points == null) {
      return Text(
        context.t('issues.noValue'),
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Text(
      '$points',
      style: const TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _person(String? name, {required String fallback, String? imageUrl}) {
    if (name == null || name.isEmpty) {
      return Text(
        fallback,
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HiveAvatar(name: name, imageUrl: imageUrl, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _dateValue(DateTime? date, {required bool isStart}) {
    if (date == null) {
      return Text(
        context.t('issues.noValue'),
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          MaterialLocalizations.of(context).formatMediumDate(date),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() {
            if (isStart) {
              _startDate = null;
            } else {
              _dueDate = null;
            }
          }),
          child: Icon(LucideIcons.x, size: 15, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Future<void> _pickProject(Rect anchor) async {
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.project'),
      anchorRect: anchor,
      options: [
        for (final p in _projects)
          (
            value: p.id,
            child: Text(
              '${p.key} – ${p.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    if (chosen != null && chosen != _projectId) await _onProjectChanged(chosen);
  }

  Future<void> _pickStatus(Rect anchor) async {
    final states = _project?.stateNames ?? const <String>[];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.status'),
      anchorRect: anchor,
      options: [
        for (final s in states)
          (
            value: s,
            child: StateDotBadge(state: s, color: _projStateColor(_project, s)),
          ),
      ],
    );
    if (chosen != null) setState(() => _state = chosen);
  }

  Future<void> _pickPriority(Rect anchor) async {
    const priorities = ['SHOWSTOPPER', 'CRITICAL', 'MAJOR', 'NORMAL', 'MINOR'];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.priority'),
      anchorRect: anchor,
      options: [
        for (final p in priorities)
          (value: p, child: PriorityFlag(priority: p, withLabel: true)),
      ],
    );
    if (chosen != null) setState(() => _priority = chosen);
  }

  Future<void> _pickType(Rect anchor) async {
    const types = ['STORY', 'TASK', 'BUG', 'FEATURE', 'EPIC'];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.type'),
      anchorRect: anchor,
      options: [for (final t in types) (value: t, child: TypeBadge(type: t))],
    );
    if (chosen != null) {
      setState(() {
        _type = chosen;
        // Epics never have a parent — drop any epic link when switching to one.
        if (chosen.toUpperCase() == 'EPIC') _parentId = null;
      });
    }
  }

  /// Epic (standard issue) / Parent (sub-task) row in the create form. Locked
  /// when the parent was forced by the launching panel.
  Widget _createParentRow() {
    final isSubtask = _type.toUpperCase() == 'SUBTASK';
    final pid = _parentId;
    final parent = pid == null
        ? null
        : _projectIssues.values.where((i) => i.id == pid).firstOrNull;
    final locked = widget.parentId != null;
    return _DetailRow(
      label: isSubtask ? context.t('issues.parent') : context.t('issues.epic'),
      onTap: (locked || isSubtask) ? null : _pickParent,
      child: parent == null
          ? Text(
              isSubtask ? '—' : context.t('issues.noEpic'),
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            )
          : _createParentChip(parent),
    );
  }

  Future<void> _pickParent(Rect anchor) async {
    final epics = _projectIssues.values.where((i) => i.isEpic).toList()
      ..sort((a, b) => a.readableId.compareTo(b.readableId));
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.epic'),
      anchorRect: anchor,
      options: [
        (
          value: _none,
          child: Text(
            context.t('issues.noEpic'),
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
        for (final e in epics) (value: e.id, child: _createParentChip(e)),
      ],
    );
    if (chosen != null) {
      setState(() => _parentId = chosen == _none ? null : chosen);
    }
  }

  Widget _createParentChip(Issue parent) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TypeGlyph(type: parent.type, size: 18),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          '${parent.readableId}  ${parent.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  Future<void> _pickLabels(Rect anchor) async {
    final pid = _projectId;
    final available = <String>{
      ...?_project?.labelNames,
      ..._labels,
    }.where((l) => !_deletedLabels.contains(l)).toList();
    final result = await showLabelPicker(
      context,
      anchor: anchor,
      available: available,
      selected: _labels.where((l) => !_deletedLabels.contains(l)).toList(),
      onDelete: pid == null
          ? null
          : (l) async {
              await _repo.deleteProjectLabel(pid, l);
              _deletedLabels.add(l);
              if (mounted) {
                setState(() => _labels = _labels.where((x) => x != l).toList());
              }
            },
    );
    if (result != null) setState(() => _labels = result);
  }

  Future<void> _pickSprint(Rect anchor) async {
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.sprint'),
      anchorRect: anchor,
      options: [
        (
          value: _none,
          child: Text(
            context.t('issues.noSprint'),
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
        for (final s in _sprints) (value: s.id, child: Text(s.name)),
      ],
    );
    if (chosen != null) {
      setState(() => _sprintId = chosen == _none ? null : chosen);
    }
  }

  // Reuses the detail view's searchable people picker so assigning while
  // creating an issue scales past a handful of users: an anchored popover beside
  // the field on tablet/desktop, the bottom sheet on phones.
  Future<void> _pickAssignee(Rect anchor) async {
    final me = context.read<AuthBloc>().state.user;
    final multi =
        context.read<AppConfigBloc>().state.meta?.multiAssignee ?? false;
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    Widget picker(BuildContext sheetContext) => _PeoplePicker(
      anchored: wide,
      users: _users,
      meId: me?.id,
      multiSelect: multi,
      initialSelected: _assigneeIds.toSet(),
      onSelectionChanged: (ids) => setState(() {
        _assigneeIds
          ..clear()
          ..addAll(ids);
      }),
      onUnassign: () {
        Navigator.of(sheetContext).pop();
        setState(_assigneeIds.clear);
      },
      onAssignMe: me == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              setState(
                () => _assigneeIds
                  ..clear()
                  ..add(me.id),
              );
            },
      onSelect: (id) {
        Navigator.of(sheetContext).pop();
        setState(
          () => _assigneeIds
            ..clear()
            ..add(id),
        );
      },
    );

    if (wide) {
      await showGlassAnchoredPopover<void>(
        context,
        anchorRect: anchor,
        width: 340,
        maxHeight: 520,
        builder: picker,
      );
      return;
    }
    await showGlassBottomSheet<void>(
      context,
      showHandle: false,
      builder: picker,
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _dueDate;
    final picked = await showGlassDatePicker(
      context,
      title: context.t(isStart ? 'issues.startDate' : 'issues.dueDate'),
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  // Anchor unused: estimate opens as a centered glass dialog, not a popover.
  Future<void> _pickStoryPoints(Rect anchor) async {
    final title = _titleCtrl.text.trim();
    final result = await showStoryPointsDialog(
      context,
      current: _storyPoints,
      subtitle: title.isEmpty ? context.t('issues.new') : title,
    );
    if (result != null) {
      setState(() => _storyPoints = result.points);
    }
  }
}

// ─────────────────────────── Top bar ───────────────────────────────────────

class _RouteTopBar extends StatelessWidget {
  const _RouteTopBar({
    required this.issue,
    required this.busy,
    this.stateColor,
    required this.link,
    this.onMinimize,
    required this.onDelete,
    required this.onClose,
  });

  final Issue issue;
  final bool busy;
  final Color? stateColor;
  final String link;

  /// Shrink back to the modal sheet — only when this page was promoted from it
  /// (null for direct deep-links, which have no modal to return to).
  final VoidCallback? onMinimize;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kRouteTopBarHeight,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(
              LucideIcons.arrowLeft,
              size: 20,
              color: AppColors.inkSoft,
            ),
          ),
          // The leading cluster consumes the free space (so the action buttons
          // stay hard-right); the state badge ellipsises inside it if tight.
          Expanded(
            child: Row(
              children: [
                CopyLinkId(
                  type: issue.type,
                  readableId: issue.readableId,
                  link: link,
                  showGlyph: false,
                  color: AppColors.inkSoft,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: StateDotBadge(state: issue.state, color: stateColor),
                ),
                if (busy) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: HiveLoader(strokeWidth: 2, color: AppColors.accent),
                  ),
                ],
              ],
            ),
          ),
          if (onMinimize != null)
            IconButton(
              tooltip: context.t('issues.minimize'),
              onPressed: onMinimize,
              icon: Icon(
                LucideIcons.minimize2,
                size: 19,
                color: AppColors.inkSoft,
              ),
            ),
          IconButton(
            tooltip: context.t('common.delete'),
            onPressed: onDelete,
            icon: const Icon(
              LucideIcons.trash2,
              size: 20,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────── Inline title editor ───────────────────────────

/// Inline title field with a green-check (save) / red-cross (cancel) row.
class _InlineTitleEditor extends StatelessWidget {
  const _InlineTitleEditor({
    required this.controller,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController controller;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (_) => onSave(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SquareButton(
              icon: LucideIcons.check,
              color: AppColors.success,
              onTap: onSave,
            ),
            const SizedBox(width: 8),
            _SquareButton(
              icon: LucideIcons.x,
              color: AppColors.danger,
              onTap: onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

/// Small bordered square action button (✓ / ✕).
class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────── Activity tabs + comment tile ──────────────────

/// A centered "Load earlier / Load more" control for the paginated comment and
/// activity streams; shows the standard [HiveLoader] while a page is fetching.
class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: TextButton.icon(
          onPressed: loading ? null : onTap,
          icon: loading
              ? const HiveLoader(size: 14, strokeWidth: 2)
              : Icon(
                  LucideIcons.chevronDown,
                  size: 15,
                  color: AppColors.inkSoft,
                ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

enum _ActivityFilter { all, comments, history }

class _ActivityTabs extends StatelessWidget {
  const _ActivityTabs({required this.value, required this.onChanged});

  final _ActivityFilter value;
  final ValueChanged<_ActivityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(context, _ActivityFilter.all, context.t('issues.filterAll')),
          _seg(
            context,
            _ActivityFilter.comments,
            context.t('issues.filterComments'),
          ),
          _seg(
            context,
            _ActivityFilter.history,
            context.t('issues.filterHistory'),
          ),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, _ActivityFilter filter, String label) {
    final active = value == filter;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? AppColors.hairline : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.ink : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// History row: actor avatar + "[name] changed [field]" + optional from→to.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.activity,
    required this.actorName,
    required this.names,
    required this.sprintNames,
    this.issueIds = const {},
  });

  final IssueActivity activity;
  final String actorName;
  final Map<String, String> names;
  final Map<String, String> sprintNames;

  /// Issue id → readable id, so a PARENT change reads as `HIV-12`, not a raw id.
  final Map<String, String> issueIds;

  // Fields where a before→after value pair is worth showing as chips.
  static const _chipFields = {
    'STATE',
    'ASSIGNEE',
    'PRIORITY',
    'TYPE',
    'SPRINT',
    'PARENT',
    'START_DATE',
    'DUE_DATE',
    'ESTIMATE',
    'TAGS',
  };

  @override
  Widget build(BuildContext context) {
    final action = activity.field == 'CREATED'
        ? context.t('issues.act.created')
        : context.t(
            'issues.act.changed',
            variables: {'field': _fieldLabel(context, activity.field)},
          );
    final showChips = _chipFields.contains(activity.field);

    final dark = AppColors.brightness == Brightness.dark;
    // System-note bubble: same rounded hairline shell as the "other" comment
    // bubble (so all three activity tabs read as one feed), just a flatter,
    // more muted fill to distinguish change events from real messages.
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1D29) : AppColors.surfaceMuted,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: actorName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                TextSpan(text: ' $action'),
              ],
            ),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
          if (showChips) ...[const SizedBox(height: 7), _changeRow(context)],
          if (activity.createdAt != null) ...[
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                MaterialLocalizations.of(
                  context,
                ).formatShortDate(activity.createdAt!.toLocal()),
                style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          HiveAvatar(
            name: actorName,
            size: 30,
            glyph: activity.actorId == null ? const HexMark(size: 18) : null,
            background: activity.actorId == null ? AppColors.accentSoft : null,
          ),
          const SizedBox(width: 9),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _changeRow(BuildContext context) {
    final from = _displayValue(context, activity.fromValue);
    final to = _displayValue(context, activity.toValue);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (from != null) _ChangeChip(from),
        if (from != null)
          Icon(LucideIcons.arrowRight, size: 14, color: AppColors.inkFaint),
        if (to != null) _ChangeChip(to),
      ],
    );
  }

  /// Humanises a raw stored value for the activity's field.
  String? _displayValue(BuildContext context, String? raw) {
    final field = activity.field;
    if (raw == null || raw.isEmpty) {
      // Assignee / sprint cleared → show an explicit "none" chip.
      return switch (field) {
        'ASSIGNEE' => context.t('issues.unassigned'),
        'SPRINT' => context.t('issues.noSprint'),
        'PARENT' => context.t('issues.noEpic'),
        _ => null,
      };
    }
    return switch (field) {
      'ASSIGNEE' => names[raw] ?? raw,
      'SPRINT' => sprintNames[raw] ?? raw,
      'PARENT' => issueIds[raw] ?? raw,
      'STATE' => stateLabel(raw),
      'PRIORITY' => context.t('priority.${raw.toLowerCase()}'),
      'TYPE' => context.t('type.${raw.toLowerCase()}'),
      'ESTIMATE' => fmtDuration(int.tryParse(raw)),
      'START_DATE' || 'DUE_DATE' => _fmtDate(context, raw),
      _ => raw,
    };
  }

  String _fmtDate(BuildContext context, String raw) {
    final parsed = DateTime.tryParse(raw);
    return parsed != null
        ? MaterialLocalizations.of(context).formatMediumDate(parsed)
        : raw;
  }

  String _fieldLabel(BuildContext context, String field) => switch (field) {
    'TITLE' => context.t('issues.field.title'),
    'DESCRIPTION' => context.t('issues.field.description'),
    'STATE' => context.t('issues.field.state'),
    'ASSIGNEE' => context.t('issues.field.assignee'),
    'PRIORITY' => context.t('issues.field.priority'),
    'TYPE' => context.t('issues.field.type'),
    'SPRINT' => context.t('issues.field.sprint'),
    'PARENT' => context.t('issues.field.parent'),
    'START_DATE' => context.t('issues.field.startDate'),
    'DUE_DATE' => context.t('issues.field.dueDate'),
    'ESTIMATE' => context.t('issues.field.estimate'),
    'TAGS' => context.t('issues.field.tags'),
    _ => field.toLowerCase(),
  };
}

/// Small bordered pill used for before/after values in the history.
class _ChangeChip extends StatelessWidget {
  const _ChangeChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

// ─────────────────── "Documented in" cross-reference ───────────────────────

/// Knowledge-base backlinks: the KB articles whose body references this issue
/// (`{{issue:<readableId>}}`). Each row opens the article.
class _DocumentedIn extends StatelessWidget {
  const _DocumentedIn({
    required this.articles,
    required this.knowledge,
    required this.onOpen,
  });

  final List<KbArticle> articles;
  final KnowledgeRepository knowledge;
  final void Function(String articleId) onOpen;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(lucideIcon('link-2'), size: 16, color: KbTokens.accent),
              const SizedBox(width: 8),
              Text(
                context.t('knowledge.documentedIn'),
                style: const TextStyle(
                  fontSize: 14.5,
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
                  '${articles.length}',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final a in articles) _row(a),
        ],
      ),
    );
  }

  Widget _row(KbArticle a) {
    final sp = knowledge.spaceById(a.spaceId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(KbTokens.radiusControl),
        child: InkWell(
          onTap: () => onOpen(a.id),
          borderRadius: BorderRadius.circular(KbTokens.radiusControl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KbTokens.radiusControl),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Icon(lucideIcon(a.icon), size: 17, color: KbTokens.accent),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (sp != null)
                        Text(
                          sp.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  lucideIcon('chevron-right'),
                  size: 16,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── People picker ─────────────────────────────────

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({
    required this.users,
    required this.meId,
    required this.onSelect,
    required this.onUnassign,
    required this.onAssignMe,
    this.anchored = false,
    this.multiSelect = false,
    this.initialSelected = const {},
    this.onSelectionChanged,
  });

  final List<DirectoryUser> users;
  final String? meId;
  final ValueChanged<String> onSelect;
  final VoidCallback onUnassign;
  final VoidCallback? onAssignMe;

  /// When `true`, the picker stays open and toggles a set of people (checkmarks)
  /// instead of selecting one and closing. [onSelectionChanged] fires with the
  /// full updated set after every toggle / clear / assign-me.
  final bool multiSelect;
  final Set<String> initialSelected;
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// When `true`, the picker renders for a wide-screen anchored popover: no grab
  /// handle and a height that flexes to its host's constraints instead of the
  /// fixed tall sheet used on phones.
  final bool anchored;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  String _query = '';
  late final Set<String> _selected = {...widget.initialSelected};

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
    widget.onSelectionChanged?.call(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.users
        : widget.users
              .where(
                (u) =>
                    u.displayName.toLowerCase().contains(q) ||
                    u.username.toLowerCase().contains(q),
              )
              .toList();
    final searchField = Padding(
      padding: widget.anchored
          ? const EdgeInsets.fromLTRB(12, 12, 12, 8)
          : const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          hintText: context.t('issues.searchPeople'),
          filled: true,
          fillColor: AppColors.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
        ),
      ),
    );

    final list = ListView(
      padding: EdgeInsets.only(bottom: widget.anchored ? 6 : 16),
      shrinkWrap: widget.anchored,
      children: [
        if (widget.onAssignMe != null && q.isEmpty)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.accentSoft,
              child: Icon(
                LucideIcons.user,
                color: AppColors.accentStrong,
                size: 18,
              ),
            ),
            title: Text(
              context.t('issues.assignToMe'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: widget.multiSelect && widget.meId != null
                ? () {
                    if (!_selected.contains(widget.meId)) _toggle(widget.meId!);
                  }
                : widget.onAssignMe,
          ),
        if (q.isEmpty)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.canvas2,
              child: Icon(LucideIcons.ban, color: AppColors.inkSoft, size: 18),
            ),
            title: Text(
              context.t(
                widget.multiSelect
                    ? 'issues.clearAssignees'
                    : 'issues.unassign',
              ),
            ),
            onTap: widget.multiSelect
                ? () {
                    setState(_selected.clear);
                    widget.onSelectionChanged?.call(_selected);
                  }
                : widget.onUnassign,
          ),
        if (q.isEmpty) const Divider(height: 1),
        for (final u in filtered)
          ListTile(
            leading: HiveAvatar(
              name: u.displayName,
              imageUrl: u.avatarUrl,
              size: 34,
            ),
            title: Text(
              u.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '@${u.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: widget.multiSelect
                ? Icon(
                    _selected.contains(u.id)
                        ? LucideIcons.checkSquare
                        : LucideIcons.square,
                    size: 20,
                    color: _selected.contains(u.id)
                        ? AppColors.accent
                        : AppColors.inkFaint,
                  )
                : (u.id == widget.meId
                      ? const Icon(
                          LucideIcons.star,
                          size: 16,
                          color: AppColors.accent,
                        )
                      : null),
            onTap: widget.multiSelect
                ? () => _toggle(u.id)
                : () => widget.onSelect(u.id),
          ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                context.t('issues.noPeopleFound'),
                style: TextStyle(color: AppColors.inkFaint),
              ),
            ),
          ),
      ],
    );

    // Anchored popover: no grab handle, and the list flexes to the host panel's
    // constraints (the popover already sizes/clamps itself on-screen).
    if (widget.anchored) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          searchField,
          Flexible(child: list),
        ],
      );
    }

    // The glass bottom-sheet wrapper already rides above the keyboard, so this
    // picker only needs to size itself; no extra viewInsets padding.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hairline,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          searchField,
          Expanded(child: list),
        ],
      ),
    );
  }
}
