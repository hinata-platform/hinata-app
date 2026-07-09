import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../core/api/api_client.dart';
import '../../core/api/hinata_repository.dart';
import '../../core/api/sse.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../search/search_tokens.dart';
import '../sprint/modals/glass_modal.dart' show showGlassOptions;
import 'issue_form.dart' show showIssueForm;

/// Jira-style "Verknüpfte Vorgänge" panel: the directed relationships between
/// this issue and others (blocks / is blocked by / duplicates / relates to …).
///
/// Shown under the sub-tasks card on the issue detail. Loads its own links,
/// stays live via SSE (a link added on the other end of a relationship appears
/// here in real time), and offers an inline, animated editor to add new links —
/// a relationship-type dropdown on the left and a searchable, multi-select
/// issue field (with selected chips) on the right.
class IssueLinksSection extends StatefulWidget {
  const IssueLinksSection({
    super.key,
    required this.issueId,
    required this.projectId,
    required this.project,
    required this.userNames,
    required this.userAvatars,
    this.onOpenIssue,
    this.onChanged,
  });

  final String issueId;
  final String projectId;

  /// The issue's project — supplies per-project workflow-state colours.
  final Project? project;
  final Map<String, String> userNames;
  final Map<String, String?> userAvatars;

  /// Opens a linked issue (by readable id) — reuses the detail-sheet navigator.
  final void Function(String readableId)? onOpenIssue;

  /// Fired after any link change so the host can refresh dependent surfaces.
  final VoidCallback? onChanged;

  @override
  State<IssueLinksSection> createState() => _IssueLinksSectionState();
}

class _IssueLinksSectionState extends State<IssueLinksSection> {
  HinataRepository get _repo => context.read<HinataRepository>();

  List<IssueLink> _links = const [];
  bool _loading = true;
  bool _adding = false;

  // SSE live sync (mirrors AttachmentsSection): a payload-free `changed` ping
  // triggers a re-fetch, with exponential-backoff reconnect.
  StreamSubscription<SseEvent>? _sseSub;
  CancelToken? _sseCancel;
  Timer? _reconnect;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
    _connectSse();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _sseSub?.cancel();
    _sseCancel?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final links = await _repo.issueLinks(widget.issueId);
      if (mounted) {
        setState(() {
          _links = links;
          _loading = false;
        });
      }
    } on ApiFailure {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── SSE live sync ──────────────────────────────────────────────────────────
  Future<void> _connectSse() async {
    if (_disposed) return;
    _sseCancel = CancelToken();
    try {
      final bytes = await _repo.issueLinkEventStream(
        widget.issueId,
        cancelToken: _sseCancel,
      );
      // Disposed WHILE opening → tear down the just-opened connection instead of
      // subscribing (else the subscription + its HTTP connection leak; enough
      // leaked SSE connections exhaust the server's slots and every request
      // starts timing out until an app restart drops the sockets).
      if (_disposed) {
        _sseCancel?.cancel();
        return;
      }
      _reconnectAttempts = 0;
      _sseSub = parseSse(bytes).listen(
        (_) => _load(),
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _sseSub?.cancel();
    _sseSub = null;
    if (_disposed) return;
    _reconnect?.cancel();
    final secs = (3 * (1 << _reconnectAttempts)).clamp(3, 30);
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(0, 4);
    _reconnect = Timer(Duration(seconds: secs), _connectSse);
  }

  // ── mutations ──────────────────────────────────────────────────────────────
  Future<void> _submit(IssueLinkOption option, List<String> targetIds) async {
    try {
      final links = await _repo.addIssueLinks(
        widget.issueId,
        type: option.type,
        outward: option.outward,
        targetIds: targetIds,
      );
      if (mounted) {
        setState(() {
          _links = links;
          _adding = false;
        });
      }
      widget.onChanged?.call();
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    }
  }

  Future<void> _remove(IssueLink link) async {
    // Optimistic removal — the SSE ping / returned list reconciles truth.
    final previous = _links;
    setState(() => _links = [for (final l in _links) if (l.id != link.id) l]);
    try {
      final links = await _repo.deleteIssueLink(widget.issueId, link.id);
      if (mounted) setState(() => _links = links);
      widget.onChanged?.call();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _links = previous);
      _toast(failure.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Links already present, so the picker can hint they're connected and the
  /// editor can avoid offering an exact duplicate of the selected relationship.
  Set<String> get _linkedIssueIds => {for (final l in _links) l.issue.id};

  /// Groups links by their display verb in the canonical [kIssueLinkOptions]
  /// order, so the sections always read blocks → is blocked by → clones → …
  List<MapEntry<String, List<IssueLink>>> get _grouped {
    final byVerb = <String, List<IssueLink>>{};
    for (final link in _links) {
      byVerb.putIfAbsent(link.verb, () => []).add(link);
    }
    final ordered = <MapEntry<String, List<IssueLink>>>[];
    final seen = <String>{};
    for (final opt in kIssueLinkOptions) {
      final group = byVerb[opt.verb];
      if (group != null && seen.add(opt.verb)) {
        ordered.add(MapEntry(opt.verb, group));
      }
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final hasLinks = _links.isNotEmpty;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('issues.links.title'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (hasLinks)
                Text(
                  '${_links.length}',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            for (final group in _grouped) ...[
              const SizedBox(height: 12),
              _LinkGroup(
                verb: group.key,
                links: group.value,
                project: widget.project,
                userNames: widget.userNames,
                userAvatars: widget.userAvatars,
                onOpen: widget.onOpenIssue,
                onRemove: _remove,
              ),
            ],
            const SizedBox(height: 6),
            // Animated transform: the text-only "add" button morphs into the
            // inline link editor and back.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    child: child,
                  ),
                ),
                child: _adding
                    ? _LinkEditor(
                        key: const ValueKey('editor'),
                        projectId: widget.projectId,
                        issueId: widget.issueId,
                        linkedIssueIds: _linkedIssueIds,
                        project: widget.project,
                        onSubmit: _submit,
                        onCancel: () => setState(() => _adding = false),
                      )
                    : Align(
                        key: const ValueKey('button'),
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _adding = true),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.stTodo,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: Text(context.t('issues.links.add')),
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One verb group: a bold relationship label and its linked-issue rows.
class _LinkGroup extends StatelessWidget {
  const _LinkGroup({
    required this.verb,
    required this.links,
    required this.project,
    required this.userNames,
    required this.userAvatars,
    required this.onRemove,
    this.onOpen,
  });

  final String verb;
  final List<IssueLink> links;
  final Project? project;
  final Map<String, String> userNames;
  final Map<String, String?> userAvatars;
  final void Function(IssueLink) onRemove;
  final void Function(String readableId)? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          verb,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        for (final link in links)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _LinkRow(
              link: link,
              project: project,
              assigneeName: link.issue.assigneeId != null
                  ? userNames[link.issue.assigneeId!]
                  : null,
              assigneeAvatar: link.issue.assigneeId != null
                  ? userAvatars[link.issue.assigneeId!]
                  : null,
              onOpen: onOpen,
              onRemove: () => onRemove(link),
            ),
          ),
      ],
    );
  }
}

/// A single linked issue: type glyph, id, title, workflow-state badge, assignee
/// avatar, and an unlink affordance. Tapping the row opens the issue.
class _LinkRow extends StatefulWidget {
  const _LinkRow({
    required this.link,
    required this.project,
    required this.onRemove,
    this.assigneeName,
    this.assigneeAvatar,
    this.onOpen,
  });

  final IssueLink link;
  final Project? project;
  final String? assigneeName;
  final String? assigneeAvatar;
  final void Function(String readableId)? onOpen;
  final VoidCallback onRemove;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _hover = false;

  Color? _stateColor(String state) {
    final hue = widget.project?.hueForState(state);
    return hue == null ? null : hueColor(hue);
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.link.issue;
    final done = issue.resolved;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onOpen == null
            ? null
            : () => widget.onOpen!(issue.readableId),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              TypeGlyph(type: issue.type, size: 18),
              const SizedBox(width: 8),
              IdMono(issue.readableId),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? AppColors.inkFaint : AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StateDotBadge(
                state: issue.state,
                color: _stateColor(issue.state),
              ),
              if (widget.assigneeName != null) ...[
                const SizedBox(width: 10),
                HiveAvatar(
                  name: widget.assigneeName!,
                  imageUrl: widget.assigneeAvatar,
                  size: 20,
                ),
              ],
              const SizedBox(width: 4),
              // Unlink — always reachable (touch), emphasised on hover (desktop).
              IconButton(
                tooltip: context.t('issues.links.remove'),
                onPressed: widget.onRemove,
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                splashRadius: 18,
                icon: Icon(
                  LucideIcons.unlink,
                  color: _hover ? AppColors.danger : AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline editor: a relationship-type dropdown (left) and a searchable,
/// multi-select issue field with selected chips and a glass suggestions
/// dropdown (right), plus create / link / cancel actions.
class _LinkEditor extends StatefulWidget {
  const _LinkEditor({
    super.key,
    required this.projectId,
    required this.issueId,
    required this.linkedIssueIds,
    required this.project,
    required this.onSubmit,
    required this.onCancel,
  });

  final String projectId;
  final String issueId;
  final Set<String> linkedIssueIds;
  final Project? project;
  final Future<void> Function(IssueLinkOption option, List<String> targetIds)
  onSubmit;
  final VoidCallback onCancel;

  @override
  State<_LinkEditor> createState() => _LinkEditorState();
}

class _LinkEditorState extends State<_LinkEditor> {
  HinataRepository get _repo => context.read<HinataRepository>();

  IssueLinkOption _option = kIssueLinkOptions.first;
  final List<Issue> _selected = [];

  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  final _fieldLink = LayerLink();
  final _overlay = OverlayPortalController();
  final _typeKey = GlobalKey();

  /// Shared TapRegion group: taps on the field or the dropdown are "inside";
  /// a tap anywhere else dismisses the dropdown without stealing field taps.
  final Object _tapGroup = Object();

  List<Issue> _candidates = const [];
  bool _loadingCandidates = true;
  bool _submitting = false;
  String _query = '';
  double _fieldWidth = 280;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _loadCandidates();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _searchCtrl.dispose();
    _focus.dispose();
    if (_overlay.isShowing) _overlay.hide();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      if (!_overlay.isShowing) _overlay.show();
    }
  }

  Future<void> _loadCandidates() async {
    try {
      final res = await _repo.issues(projectId: widget.projectId, size: 100);
      if (mounted) {
        setState(() {
          _candidates = res.issues;
          _loadingCandidates = false;
        });
      }
    } on ApiFailure {
      if (mounted) setState(() => _loadingCandidates = false);
    }
  }

  /// Project issues that aren't this one and aren't already selected, filtered
  /// by the live query (readable id or title). Already-linked issues are kept
  /// (a different relationship may still be valid) but flagged in the tile.
  List<Issue> get _suggestions {
    final q = _query.trim().toLowerCase();
    final selectedIds = {for (final s in _selected) s.id};
    return _candidates.where((i) {
      if (i.id == widget.issueId) return false;
      if (selectedIds.contains(i.id)) return false;
      if (q.isEmpty) return true;
      return i.readableId.toLowerCase().contains(q) ||
          i.title.toLowerCase().contains(q);
    }).take(60).toList();
  }

  void _add(Issue issue) {
    setState(() {
      _selected.add(issue);
      _searchCtrl.clear();
      _query = '';
    });
    _focus.requestFocus();
  }

  void _removeChip(Issue issue) {
    setState(() => _selected.removeWhere((i) => i.id == issue.id));
  }

  Future<void> _pickType() async {
    final box = _typeKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? anchor;
    if (box != null && box.hasSize) {
      final offset = box.localToGlobal(Offset.zero);
      anchor = offset & box.size;
    }
    final chosen = await showGlassOptions<int>(
      context,
      title: context.t('issues.links.typeTitle'),
      anchorRect: anchor,
      options: [
        for (var i = 0; i < kIssueLinkOptions.length; i++)
          (
            value: i,
            child: Text(
              kIssueLinkOptions[i].verb,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
    if (chosen != null && mounted) {
      setState(() => _option = kIssueLinkOptions[chosen]);
    }
  }

  Future<void> _createLinked() async {
    _overlay.hide();
    final created = await showIssueForm(context, projectId: widget.projectId);
    if (created != null && mounted) {
      setState(() {
        if (!_candidates.any((i) => i.id == created.id)) {
          _candidates = [created, ..._candidates];
        }
        if (!_selected.any((i) => i.id == created.id)) _selected.add(created);
      });
    }
  }

  Future<void> _submit() async {
    if (_selected.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    _overlay.hide();
    await widget.onSubmit(_option, [for (final i in _selected) i.id]);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // Stack the type dropdown above the field on narrow widths.
              final narrow = c.maxWidth < 440;
              final type = _TypePill(
                key: _typeKey,
                verb: _option.verb,
                onTap: _pickType,
              );
              final field = _buildField();
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: type),
                    const SizedBox(height: 8),
                    field,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  type,
                  const SizedBox(width: 8),
                  Expanded(child: field),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              // On narrow widths the three actions can't share one row without
              // the long "create" label pushing the confirm button off-screen.
              // Stack them: primary confirm on top, then create + cancel.
              final narrow = c.maxWidth < 440;
              final create = TextButton.icon(
                onPressed: _createLinked,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.inkSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                icon: const Icon(LucideIcons.plus, size: 15),
                label: Text(
                  context.t('issues.links.create'),
                  overflow: TextOverflow.ellipsis,
                ),
              );
              final confirm = FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  disabledBackgroundColor: AppColors.surfaceMuted,
                  minimumSize: narrow ? const Size.fromHeight(44) : null,
                ),
                onPressed: _selected.isEmpty || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.t('issues.links.confirm')),
              );
              final cancel = TextButton(
                onPressed: _submitting ? null : widget.onCancel,
                child: Text(
                  context.t('common.cancel'),
                  style: TextStyle(color: AppColors.inkSoft),
                ),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    confirm,
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: create),
                        cancel,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: create),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      confirm,
                      const SizedBox(width: 6),
                      cancel,
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildField() {
    return CompositedTransformTarget(
      link: _fieldLink,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: _buildOverlay,
        child: LayoutBuilder(
          builder: (context, c) {
            _fieldWidth = c.maxWidth;
            return TapRegion(
              groupId: _tapGroup,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _focus.requestFocus,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(
                    color: _focus.hasFocus
                        ? AppColors.accent
                        : AppColors.hairline,
                    width: _focus.hasFocus ? 1.4 : 1,
                  ),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final issue in _selected)
                      _LinkChip(
                        issue: issue,
                        onRemove: () => _removeChip(issue),
                      ),
                    // The text field fills the full width of the run it lands on
                    // (its own line beneath the chips, or the whole field when
                    // empty) instead of a fixed 160px stub — otherwise the input
                    // caret sat in a cramped half-width box. `_fieldWidth` is the
                    // container's outer width; subtract its 10px horizontal
                    // padding on each side to get the Wrap's content width.
                    SizedBox(
                      width: (_fieldWidth - 20).clamp(120.0, double.infinity),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _focus,
                        onChanged: (v) {
                          setState(() => _query = v);
                          if (!_overlay.isShowing) _overlay.show();
                        },
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          hintText: _selected.isEmpty
                              ? context.t('issues.links.fieldHint')
                              : null,
                          hintStyle: TextStyle(
                            color: AppColors.inkFaint,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    // The panel shares the field's TapRegion group, so a tap on the field or a
    // suggestion stays "inside"; any tap elsewhere dismisses the dropdown.
    return CompositedTransformFollower(
      link: _fieldLink,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 6),
      child: Align(
        alignment: Alignment.topLeft,
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) {
            if (_overlay.isShowing) {
              _overlay.hide();
              _focus.unfocus();
            }
          },
          child: _GlassDropdownPanel(
            width: _fieldWidth,
            child: _buildSuggestions(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    if (_loadingCandidates) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final suggestions = _suggestions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(
            context.t('issues.links.suggestionsTitle'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.inkFaint,
            ),
          ),
        ),
        if (suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
            child: Text(
              context.t('issues.links.noMatches'),
              style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (context, i) {
                final issue = suggestions[i];
                return _SuggestionTile(
                  issue: issue,
                  alreadyLinked: widget.linkedIssueIds.contains(issue.id),
                  onTap: () => _add(issue),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The relationship-type dropdown button (e.g. "is blocked by ▾").
class _TypePill extends StatelessWidget {
  const _TypePill({super.key, required this.verb, required this.onTap});

  final String verb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        height: 46,
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                verb,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// A selected issue rendered as a chip inside the search field.
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.issue, required this.onRemove});

  final Issue issue;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TypeGlyph(type: issue.type, size: 15),
          const SizedBox(width: 5),
          Text(
            issue.readableId,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accentStrong,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                LucideIcons.x,
                size: 13,
                color: AppColors.accentStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the suggestions dropdown.
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.issue,
    required this.alreadyLinked,
    required this.onTap,
  });

  final Issue issue;
  final bool alreadyLinked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            TypeGlyph(type: issue.type, size: 18),
            const SizedBox(width: 9),
            Text(
              issue.readableId,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSoft,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                issue.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            if (alreadyLinked) ...[
              const SizedBox(width: 8),
              Icon(LucideIcons.link, size: 14, color: AppColors.inkFaint),
            ],
          ],
        ),
      ),
    );
  }
}

/// Liquid-glass dropdown surface for the suggestions list — mirrors the glass
/// panel used by the anchored pickers (`showGlassAnchoredPopover`).
class _GlassDropdownPanel extends StatelessWidget {
  const _GlassDropdownPanel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: 320),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(18),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: const LiquidRoundedSuperellipse(borderRadius: 18),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: dark,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
  }
}
