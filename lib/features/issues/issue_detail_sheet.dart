import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import 'issue_markdown.dart';
import 'work_log_sheet.dart';

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
  final repository = context.read<HivoraRepository>();
  final auth = context.read<AuthBloc>();
  final header = ValueNotifier<Issue?>(null);
  final bodyKey = GlobalKey<IssueDetailBodyState>();

  return WoltModalSheet.show<void>(
    context: context,
    // Push onto the root navigator so the sheet covers the floating glass
    // bottom-nav instead of rendering behind it (the shell nav is a Positioned
    // sibling inside the ShellRoute's nested navigator).
    useRootNavigator: true,
    barrierDismissible: true,
    modalTypeBuilder: (ctx) => MediaQuery.sizeOf(ctx).width >= 760
        ? const _WideDialogType()
        : WoltModalType.bottomSheet(),
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        hasTopBarLayer: true,
        isTopBarLayerAlwaysVisible: true,
        leadingNavBarWidget: ValueListenableBuilder<Issue?>(
          valueListenable: header,
          builder: (_, issue, _) => issue == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: Row(
                    spacing: 10,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TypeGlyph(type: issue.type, size: 24),
                      IdMono(issue.readableId, color: AppColors.inkSoft, fontSize: 16),
                    ],
                  ),
                ),
        ),
        trailingNavBarWidget: _SheetActions(
          onCopyLink: () => bodyKey.currentState?.copyIssueLink(),
          onEdit: () => bodyKey.currentState?.beginTitleEdit(),
          onDelete: () => bodyKey.currentState?.confirmDeleteIssue(),
          onClose: () => Navigator.of(modalContext).maybePop(),
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
          ),
        ),
      ),
    ],
  ).whenComplete(header.dispose);
}

/// Copy-link · overflow menu (edit / delete) · close — rendered in the wolt
/// top bar. All secondary actions live in the 3-dot menu.
class _SheetActions extends StatelessWidget {
  const _SheetActions({
    required this.onCopyLink,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  final VoidCallback onCopyLink;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.t('issues.copyLink'),
          onPressed: onCopyLink,
          icon: Icon(Icons.link_rounded, size: 20, color: AppColors.inkSoft),
        ),
        _IssueOverflowMenu(onEdit: onEdit, onDelete: onDelete),
        IconButton(
          tooltip: context.t('common.cancel'),
          onPressed: onClose,
          icon: Icon(Icons.close_rounded, size: 20, color: AppColors.inkSoft),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

/// Shared 3-dot menu holding the edit + delete actions.
class _IssueOverflowMenu extends StatelessWidget {
  const _IssueOverflowMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      icon: Icon(Icons.more_horiz_rounded, size: 22, color: AppColors.inkSoft),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 10),
              Text(context.t('issues.edit')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: 10),
              Text(
                context.t('common.delete'),
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
      ],
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
  });

  final String issueId;
  final VoidCallback? onChanged;
  final ValueNotifier<Issue?>? header;

  @override
  State<IssueDetailBody> createState() => IssueDetailBodyState();
}

class IssueDetailBodyState extends State<IssueDetailBody> {
  final _comment = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  Issue? _issue;
  List<IssueComment> _comments = const [];
  List<IssueActivity> _activity = const [];
  List<WorkItem> _workItems = const [];
  Project? _project;
  List<DirectoryUser> _users = const [];
  List<Sprint> _sprints = const [];
  Map<String, String> get _names => {
    for (final u in _users) u.id: u.displayName,
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

  HivoraRepository get _repo => context.read<HivoraRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
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
      final issue = await _repo.issue(widget.issueId);
      final results = await Future.wait([
        _repo.comments(widget.issueId),
        _repo.workItems(widget.issueId),
        _repo.projects(),
        _repo.users(),
        _repo.issueActivity(widget.issueId),
      ]);
      _issue = issue;
      _comments = results[0] as List<IssueComment>;
      _workItems = results[1] as List<WorkItem>;
      _project = (results[2] as List<Project>)
          .where((p) => p.id == issue.projectId)
          .firstOrNull;
      _users = results[3] as List<DirectoryUser>;
      _activity = results[4] as List<IssueActivity>;
      // Sprints come from the project's board(s); best-effort.
      try {
        final boards = await _repo.boards(projectId: issue.projectId);
        if (boards.isNotEmpty) {
          final view = await _repo.boardView(boards.first.id);
          _sprints = view.sprints;
        }
      } catch (_) {
        _sprints = const [];
      }
      widget.header?.value = issue;
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

  Future<void> _patch(Map<String, dynamic> patch) async {
    setState(() => _busy = true);
    try {
      final updated = await _repo.updateIssue(widget.issueId, patch);
      _issue = updated;
      widget.header?.value = updated;
      widget.onChanged?.call();
      // Refresh the change history so the new entry shows immediately.
      try {
        _activity = await _repo.issueActivity(widget.issueId);
      } catch (_) {
        // Non-critical; the next full load reflects server truth.
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    try {
      await _repo.addComment(widget.issueId, text);
      _comment.clear();
      _comments = await _repo.comments(widget.issueId);
      if (mounted) setState(() {});
    } on ApiFailure catch (failure) {
      _toast(failure.message);
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

  void copyIssueLink() {
    final issue = _issue;
    if (issue == null) return;
    String link;
    try {
      link = '${Uri.base.origin}/#/issues/${issue.id}';
    } catch (_) {
      link = '/issues/${issue.id}';
    }
    Clipboard.setData(ClipboardData(text: link));
    _toast(context.t('issues.linkCopied'));
  }

  Future<void> confirmDeleteIssue() async {
    final issue = _issue;
    if (issue != null) await _confirmDelete(issue);
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading && _issue == null) {
      return const SizedBox(
        height: 260,
        child: Center(child: HiveLoader()),
      );
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
    final inSheet = widget.header != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!inSheet)
          _RouteTopBar(
            issue: issue,
            busy: _busy,
            onCopyLink: copyIssueLink,
            onEdit: beginTitleEdit,
            onDelete: () => _confirmDelete(issue),
            onClose: () => Navigator.of(context).maybePop(),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, inSheet ? 16 : 16, 20, 24),
          child: LayoutBuilder(
            builder: (context, c) {
              final left = <Widget>[
                _contentCard(issue),
                const SizedBox(height: 14),
                _activityCard(),
              ];
              final right = <Widget>[
                _detailsCard(issue),
                const SizedBox(height: 14),
                _timeCard(issue),
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
                  const SizedBox(height: 14),
                  _detailsCard(issue),
                  const SizedBox(height: 14),
                  _timeCard(issue),
                  const SizedBox(height: 14),
                  _activityCard(),
                ],
              );
            },
          ),
        ),
      ],
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
          if (issue.tags.isNotEmpty && !_editingTitle) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in issue.tags) LabelTag(t)],
            ),
          ],
          const SizedBox(height: 18),
          _sectionLabel(context.t('issues.description')),
          const SizedBox(height: 8),
          // Description — double-tap to edit as Markdown.
          if (_editingDesc)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarkdownEditorField(
                  controller: _descCtrl,
                  hintText: context.t('issues.description'),
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
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _beginDescEdit,
              child: (issue.description ?? '').isNotEmpty
                  ? MarkdownText(issue.description!)
                  : Text(
                      context.t('issues.noDescription'),
                      style: TextStyle(
                        color: AppColors.inkFaint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
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

  Widget _detailsCard(Issue issue) {
    final assigneeName = issue.assigneeId != null
        ? _names[issue.assigneeId!]
        : null;
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
            child: StateDotBadge(state: issue.state),
          ),
          // Assignee + "assign to me"
          _DetailRow(
            label: context.t('issues.assignee'),
            onTap: _pickAssignee,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _person(assigneeName, fallback: context.t('issues.unassigned')),
                if (me != null && issue.assigneeId != me.id) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _patch({'assigneeId': me.id}),
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
          // Type
          _DetailRow(
            label: context.t('issues.type'),
            onTap: _pickType,
            child: TypeBadge(type: issue.type),
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
            child: _person(
              reporterName,
              fallback: context.t('issues.unassigned'),
            ),
          ),
          // Start date
          _DetailRow(
            label: context.t('issues.startDate'),
            onTap: () => _pickDate(isStart: true),
            child: _dateValue(issue.startDate, isStart: true),
          ),
          // Due date
          _DetailRow(
            label: context.t('issues.dueDate'),
            onTap: () => _pickDate(isStart: false),
            last: true,
            child: _dateValue(issue.dueDate, isStart: false),
          ),
        ],
      ),
    );
  }

  Widget _person(String? name, {required String fallback}) {
    if (name == null || name.isEmpty) {
      return Text(
        fallback,
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HiveAvatar(name: name, size: 22),
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
          child: Icon(Icons.close_rounded, size: 15, color: AppColors.inkFaint),
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
                  context.t('issues.timeTracking'),
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
          const SizedBox(height: 8),
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
                    Icons.timelapse_rounded,
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

  Widget _activityCard() {
    final filter = _activityFilter;
    final showComposer = filter != _ActivityFilter.history;
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
          if (showComposer) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _comment,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.t('issues.addComment'),
                    ),
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: AppColors.navy),
                  onPressed: _submitComment,
                  icon: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the activity feed for [filter]:
  ///  • comments → comments oldest-first (chat style)
  ///  • history  → change events newest-first
  ///  • all      → both, merged newest-first
  List<Widget> _activityItems(_ActivityFilter filter) {
    Widget commentTile(IssueComment c) =>
        _CommentTile(comment: c, authorName: _names[c.authorId] ?? c.authorId);
    Widget activityTile(IssueActivity a) => _ActivityTile(
      activity: a,
      actorName: a.actorId != null
          ? (_names[a.actorId!] ?? a.actorId!)
          : context.t('issues.unassigned'),
      names: _names,
      sprintNames: _sprintNames,
    );

    switch (filter) {
      case _ActivityFilter.comments:
        if (_comments.isEmpty) {
          return [_emptyActivity(context.t('issues.activityEmpty'))];
        }
        return [for (final c in _comments) commentTile(c)];
      case _ActivityFilter.history:
        if (_activity.isEmpty) {
          return [_emptyActivity(context.t('issues.historyEmpty'))];
        }
        return [for (final a in _activity) activityTile(a)];
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
        return [for (final m in merged) m.tile];
    }
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

  Future<void> _pickStatus() async {
    final states = _project?.workflowStates ?? [_issue!.state];
    final chosen = await _showOptions<String>(
      title: context.t('issues.status'),
      options: [
        for (final s in states) (value: s, child: StateDotBadge(state: s)),
      ],
    );
    if (chosen != null) await _patch({'state': chosen});
  }

  Future<void> _pickPriority() async {
    const priorities = ['SHOWSTOPPER', 'CRITICAL', 'MAJOR', 'NORMAL', 'MINOR'];
    final chosen = await _showOptions<String>(
      title: context.t('issues.priority'),
      options: [
        for (final p in priorities)
          (value: p, child: PriorityFlag(priority: p, withLabel: true)),
      ],
    );
    if (chosen != null) await _patch({'priority': chosen});
  }

  Future<void> _pickType() async {
    const types = ['TASK', 'BUG', 'FEATURE', 'EPIC'];
    final chosen = await _showOptions<String>(
      title: context.t('issues.type'),
      options: [for (final t in types) (value: t, child: TypeBadge(type: t))],
    );
    if (chosen != null) await _patch({'type': chosen});
  }

  static const _noSprint = '__none__';

  Future<void> _pickSprint() async {
    final chosen = await _showOptions<String>(
      title: context.t('issues.sprint'),
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
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final iso = picked.toIso8601String().substring(0, 10);
      await _patch({isStart ? 'startDate' : 'dueDate': iso});
    }
  }

  Future<void> _pickAssignee() async {
    final me = context.read<AuthBloc>().state.user;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PeoplePicker(
        users: _users,
        meId: me?.id,
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
      ),
    );
  }

  Future<T?> _showOptions<T>({
    required String title,
    required List<({T value, Widget child})> options,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final o in options)
              InkWell(
                onTap: () => Navigator.of(sheetContext).pop(o.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Align(alignment: Alignment.centerLeft, child: o.child),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Issue issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(dialogContext.t('issues.deleteTitle')),
        content: Text(
          dialogContext.t(
            'issues.deleteBody',
            variables: {'id': issue.readableId},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.t('common.delete')),
          ),
        ],
      ),
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
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
                Icons.unfold_more_rounded,
                size: 16,
                color: AppColors.inkFaint,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Option picker ─────────────────────────────────

/// Bottom-sheet single-choice picker (shared by the create body). Mirrors the
/// detail sheet's inline `_showOptions`.
Future<T?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required List<({T value, Widget child})> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          for (final o in options)
            InkWell(
              onTap: () => Navigator.of(sheetContext).pop(o.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Align(alignment: Alignment.centerLeft, child: o.child),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
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
    required this.onCreated,
  });

  final IssueCreateController controller;
  final String? projectId;
  final String? initialState;
  final ValueChanged<Issue> onCreated;

  @override
  State<IssueCreateBody> createState() => IssueCreateBodyState();
}

class IssueCreateBodyState extends State<IssueCreateBody> {
  HivoraRepository get _repo => context.read<HivoraRepository>();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  List<Project> _projects = const [];
  List<DirectoryUser> _users = const [];
  List<Sprint> _sprints = const [];

  String? _projectId;
  String? _state;
  String? _assigneeId;
  String _priority = 'NORMAL';
  String _type = 'TASK';
  String? _sprintId;
  DateTime? _startDate;
  DateTime? _dueDate;

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

  /// Loads sprints + a default status for the selected project.
  Future<void> _loadProjectScoped() async {
    _state ??= _project?.workflowStates.firstOrNull;
    _sprints = const [];
    final pid = _projectId;
    if (pid == null) return;
    try {
      final boards = await _repo.boards(projectId: pid);
      if (boards.isNotEmpty) {
        final view = await _repo.boardView(boards.first.id);
        _sprints = view.sprints;
      }
    } catch (_) {
      _sprints = const [];
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
        if (_assigneeId != null) 'assigneeId': _assigneeId,
        if (_sprintId != null) 'sprintId': _sprintId,
        if (_startDate != null)
          'startDate': _startDate!.toIso8601String().substring(0, 10),
        if (_dueDate != null)
          'dueDate': _dueDate!.toIso8601String().substring(0, 10),
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
    return Form(
      key: _formKey,
      autovalidateMode: _autovalidate
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Padding(
        // Bottom clearance for the pinned save bar (which overlays the content):
        // ~save button + its padding + the device safe-area inset.
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 88 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final left = _contentCard();
                final right = _detailsCard();
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
            errorStyle:
                const TextStyle(color: AppColors.danger, fontSize: 12),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? context.t('errors.required')
              : null,
        ),
        const SizedBox(height: 18),
        _sectionLabel(context.t('issues.description')),
        const SizedBox(height: 8),
        MarkdownEditorField(
          controller: _descCtrl,
          hintText: context.t('issues.description'),
        ),
      ],
    );
  }

  Widget _detailsCard() {
    final assigneeName = _assigneeId != null ? _names[_assigneeId] : null;
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
                ? StateDotBadge(state: _state!)
                : Text(
                    context.t('issues.noValue'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  ),
          ),
          _DetailRow(
            label: context.t('issues.assignee'),
            onTap: _pickAssignee,
            child: _person(
              assigneeName,
              fallback: context.t('issues.unassigned'),
            ),
          ),
          _DetailRow(
            label: context.t('issues.priority'),
            onTap: _pickPriority,
            child: PriorityFlag(priority: _priority, withLabel: true),
          ),
          _DetailRow(
            label: context.t('issues.type'),
            onTap: _pickType,
            child: TypeBadge(type: _type),
          ),
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
          _DetailRow(
            label: context.t('issues.startDate'),
            onTap: () => _pickDate(isStart: true),
            child: _dateValue(_startDate, isStart: true),
          ),
          _DetailRow(
            label: context.t('issues.dueDate'),
            onTap: () => _pickDate(isStart: false),
            last: true,
            child: _dateValue(_dueDate, isStart: false),
          ),
        ],
      ),
    );
  }

  Widget _person(String? name, {required String fallback}) {
    if (name == null || name.isEmpty) {
      return Text(
        fallback,
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HiveAvatar(name: name, size: 22),
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
          child: Icon(Icons.close_rounded, size: 15, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Future<void> _pickProject() async {
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.project'),
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

  Future<void> _pickStatus() async {
    final states = _project?.workflowStates ?? const <String>[];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.status'),
      options: [
        for (final s in states) (value: s, child: StateDotBadge(state: s)),
      ],
    );
    if (chosen != null) setState(() => _state = chosen);
  }

  Future<void> _pickPriority() async {
    const priorities = ['SHOWSTOPPER', 'CRITICAL', 'MAJOR', 'NORMAL', 'MINOR'];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.priority'),
      options: [
        for (final p in priorities)
          (value: p, child: PriorityFlag(priority: p, withLabel: true)),
      ],
    );
    if (chosen != null) setState(() => _priority = chosen);
  }

  Future<void> _pickType() async {
    const types = ['TASK', 'BUG', 'FEATURE', 'EPIC'];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.type'),
      options: [for (final t in types) (value: t, child: TypeBadge(type: t))],
    );
    if (chosen != null) setState(() => _type = chosen);
  }

  Future<void> _pickSprint() async {
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.sprint'),
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

  Future<void> _pickAssignee() async {
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.assignee'),
      options: [
        (
          value: _none,
          child: Text(
            context.t('issues.unassigned'),
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
        for (final u in _users)
          (value: u.id, child: _person(u.displayName, fallback: '')),
      ],
    );
    if (chosen != null) {
      setState(() => _assigneeId = chosen == _none ? null : chosen);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
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
}

// ─────────────────────────── Top bar ───────────────────────────────────────

class _RouteTopBar extends StatelessWidget {
  const _RouteTopBar({
    required this.issue,
    required this.busy,
    required this.onCopyLink,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  final Issue issue;
  final bool busy;
  final VoidCallback onCopyLink;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: AppColors.inkSoft,
            ),
          ),
          IdMono(issue.readableId, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          StateDotBadge(state: issue.state),
          if (busy) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 14,
              height: 14,
              child: HiveLoader(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: context.t('issues.copyLink'),
            onPressed: onCopyLink,
            icon: Icon(Icons.link_rounded, size: 20, color: AppColors.inkSoft),
          ),
          _IssueOverflowMenu(onEdit: onEdit, onDelete: onDelete),
        ],
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
              icon: Icons.check_rounded,
              color: AppColors.success,
              onTap: onSave,
            ),
            const SizedBox(width: 8),
            _SquareButton(
              icon: Icons.close_rounded,
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

/// Comment row: author avatar + name + relative date + body text.
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.authorName});

  final IssueComment comment;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HiveAvatar(name: authorName, size: 30),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (comment.createdAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatShortDate(comment.createdAt!.toLocal()),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: TextStyle(
                    height: 1.5,
                    fontSize: 13,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
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
  });

  final IssueActivity activity;
  final String actorName;
  final Map<String, String> names;
  final Map<String, String> sprintNames;

  // Fields where a before→after value pair is worth showing as chips.
  static const _chipFields = {
    'STATE',
    'ASSIGNEE',
    'PRIORITY',
    'TYPE',
    'SPRINT',
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HiveAvatar(name: actorName, size: 30),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                if (activity.createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatShortDate(activity.createdAt!.toLocal()),
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                  ),
                ],
                if (showChips) ...[
                  const SizedBox(height: 7),
                  _changeRow(context),
                ],
              ],
            ),
          ),
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
          Icon(
            Icons.arrow_forward_rounded,
            size: 14,
            color: AppColors.inkFaint,
          ),
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
        _ => null,
      };
    }
    return switch (field) {
      'ASSIGNEE' => names[raw] ?? raw,
      'SPRINT' => sprintNames[raw] ?? raw,
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

// ─────────────────────────── People picker ─────────────────────────────────

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({
    required this.users,
    required this.meId,
    required this.onSelect,
    required this.onUnassign,
    required this.onAssignMe,
  });

  final List<DirectoryUser> users;
  final String? meId;
  final ValueChanged<String> onSelect;
  final VoidCallback onUnassign;
  final VoidCallback? onAssignMe;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  String _query = '';

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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
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
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  if (widget.onAssignMe != null && q.isEmpty)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.accentSoft,
                        child: Icon(
                          Icons.person_rounded,
                          color: AppColors.accentStrong,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        context.t('issues.assignToMe'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: widget.onAssignMe,
                    ),
                  if (q.isEmpty)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.canvas2,
                        child: Icon(
                          Icons.block_rounded,
                          color: AppColors.inkSoft,
                          size: 18,
                        ),
                      ),
                      title: Text(context.t('issues.unassign')),
                      onTap: widget.onUnassign,
                    ),
                  if (q.isEmpty) const Divider(height: 1),
                  for (final u in filtered)
                    ListTile(
                      leading: HiveAvatar(name: u.displayName, size: 34),
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
                      trailing: u.id == widget.meId
                          ? const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: AppColors.accent,
                            )
                          : null,
                      onTap: () => widget.onSelect(u.id),
                    ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          context.t('issues.empty'),
                          style: TextStyle(color: AppColors.inkFaint),
                        ),
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
}
