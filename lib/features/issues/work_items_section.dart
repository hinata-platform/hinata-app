import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart'
    show
        GlassModalHeader,
        GlassToastKind,
        showGlassConfirm,
        showGlassErrorToast,
        showGlassModal,
        showGlassToast;
import 'work_item_labels.dart';
import 'work_log_sheet.dart';

/// Who may do what to a work item — resolved once by the host from the auth
/// state and the project's leads, so every row and the "all entries" sheet
/// answer the same way without re-deriving it.
///
/// Mirrors the server rule (owner, a lead of the entry's project, or an admin
/// may change or remove it) with one deliberate narrowing: the app only offers
/// *editing* on your own entries. A lead correcting someone else's hours is
/// the exception, and deleting the entry and asking for a fresh one keeps the
/// audit trail honest about who wrote what.
class WorkItemAccess {
  const WorkItemAccess({required this.meId, this.managesProject = false});

  /// Nobody signed in yet — every row is read-only.
  static const none = WorkItemAccess(meId: null);

  /// The signed-in user, or null while the session is still resolving.
  final String? meId;

  /// Whether the caller leads the entry's project or is an admin — may remove
  /// other people's entries, and the legacy remainder that belongs to nobody.
  final bool managesProject;

  bool isOwn(WorkItem item) => meId != null && item.userId == meId;

  bool canEdit(WorkItem item) => isOwn(item);

  bool canDelete(WorkItem item) => isOwn(item) || managesProject;

  /// Whether the reader may see *whose* entry this is, and what they wrote in
  /// it.
  ///
  /// Everyone on the project sees that the hours exist — that is what makes the
  /// card answer "why did a one-day job take three". Who worked them is a
  /// different question: a per-person, per-day breakdown of a colleague's
  /// working time is exactly the reading of time data that has to be switched
  /// on deliberately rather than shipped as the default (§ 87 Abs. 1 Nr. 6
  /// BetrVG, Art. 25 DSGVO). So it is your own entries, plus those of a project
  /// you lead, and the operator policy that opens it up comes with the policy
  /// model itself.
  bool canSeeAuthor(WorkItem item) => isOwn(item) || managesProject;
}

/// Opens the entry in the work-log sheet's edit mode. Answers the patched
/// entry once it was saved, and null when nothing changed.
Future<WorkItem?> showEditWorkItem(
  BuildContext context,
  String issueId,
  WorkItem item,
) async {
  final saved = await showWorkLogSheet(context, issueId, existing: item);
  return saved is WorkItem ? saved : null;
}

/// Asks, then deletes. True when the entry is gone; a refused or failed
/// delete answers false — the failure (a 403 for someone else's entry, say)
/// is already localized by the server and shown as it came.
Future<bool> confirmDeleteWorkItem(BuildContext context, WorkItem item) async {
  final repository = context.read<IssueRepository>();
  final date = item.date;
  final deleted = context.t('time.deleted');
  final confirmed = await showGlassConfirm(
    context,
    icon: LucideIcons.trash2,
    title: context.t('time.deleteTitle'),
    message: context.t(
      'time.deleteConfirm',
      variables: {
        'duration': fmtDuration(context, item.durationMinutes),
        'date': date == null
            ? context.t('time.fmt.none')
            : MaterialLocalizations.of(context).formatMediumDate(date),
      },
    ),
    confirmLabel: context.t('common.delete'),
    confirmIcon: LucideIcons.trash2,
    destructive: true,
  );
  if (confirmed != true) return false;
  try {
    await repository.deleteWorkItem(item.id);
  } on ApiFailure catch (failure) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t(failure.message));
    }
    return false;
  }
  if (context.mounted) {
    showGlassToast(context, deleted, kind: GlassToastKind.success);
  }
  return true;
}

/// The head of an issue's timeline: the newest entries plus the door to all of
/// them. The host owns the data and the reloads — this only draws and asks.
class WorkItemList extends StatelessWidget {
  const WorkItemList({
    super.key,
    required this.items,
    required this.total,
    required this.access,
    required this.nameFor,
    required this.avatarFor,
    required this.onEdit,
    required this.onDelete,
    required this.onShowAll,
    this.limit = headCount,
  });

  /// How many entries the card shows — and, because nothing else is drawn,
  /// exactly how many the issue detail asks the server for.
  static const headCount = 8;

  final List<WorkItem> items;

  /// The issue's full count — what the "all entries" button says, and why it
  /// shows even when every entry already fits: the sheet is also where the
  /// list can be worked on at full width.
  final int total;
  final WorkItemAccess access;
  final String? Function(String userId) nameFor;
  final String? Function(String userId) avatarFor;
  final ValueChanged<WorkItem> onEdit;
  final ValueChanged<WorkItem> onDelete;
  final VoidCallback onShowAll;

  /// How many entries the card shows before pointing at the sheet.
  final int limit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items.take(limit))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: WorkItemRow(
              item: item,
              access: access,
              nameFor: nameFor,
              avatarFor: avatarFor,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        if (total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _AllEntriesButton(count: total, onTap: onShowAll),
            ),
          ),
      ],
    );
  }
}

/// One logged entry: who, how long, doing what, on which day — and, when the
/// reader may change it, the menu that does.
class WorkItemRow extends StatelessWidget {
  const WorkItemRow({
    super.key,
    required this.item,
    required this.access,
    required this.nameFor,
    required this.avatarFor,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkItem item;
  final WorkItemAccess access;
  final String? Function(String userId) nameFor;
  final String? Function(String userId) avatarFor;
  final ValueChanged<WorkItem> onEdit;
  final ValueChanged<WorkItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final canEdit = access.canEdit(item);
    final canDelete = access.canDelete(item);
    // The legacy remainder belongs to nobody, so naming it discloses nothing.
    final named = access.canSeeAuthor(item) || item.isLegacy;
    final who = named ? workItemPersonLabel(context, item, nameFor) : null;
    final description = named ? item.description?.trim() ?? '' : '';
    final date = item.date;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: _leading(who)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${fmtDuration(context, item.durationMinutes)} · '
                      '${activityLabel(context, item.activityType)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (date != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      MaterialLocalizations.of(context).formatShortDate(date),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
              if (who != null) ...[
                const SizedBox(height: 2),
                Text(
                  description.isEmpty ? who : '$who · $description',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ],
          ),
        ),
        if (canEdit || canDelete) ...[
          const SizedBox(width: 4),
          _WorkItemMenu(
            canEdit: canEdit,
            canDelete: canDelete,
            onEdit: () => onEdit(item),
            onDelete: () => onDelete(item),
          ),
        ],
      ],
    );
  }

  /// A face for a person; a mark for the three kinds of nobody — the pre-2.0
  /// remainder (a commit glyph), a deleted account, and a colleague this reader
  /// is not shown (a plain figure, which says "someone" without saying who).
  Widget _leading(String? who) {
    final userId = item.userId;
    if (who == null) {
      return HiveAvatar(
        name: '',
        size: 24,
        background: AppColors.inkFaint,
        glyph: const Icon(LucideIcons.user, size: 12, color: Colors.white),
      );
    }
    if (item.isLegacy || userId == null || nameFor(userId) == null) {
      return HiveAvatar(
        name: who,
        size: 24,
        background: AppColors.inkFaint,
        glyph: Icon(
          item.isLegacy ? LucideIcons.gitCommitHorizontal : LucideIcons.userX,
          size: 12,
          color: Colors.white,
        ),
      );
    }
    return HiveAvatar(name: who, imageUrl: avatarFor(userId), size: 24);
  }
}

enum _WorkItemAction { edit, delete }

/// The row's "…" — a glass popover with the corrections the reader may make.
/// Rows that allow neither never render it, so a read-only timeline stays a
/// timeline rather than a list of inert buttons.
class _WorkItemMenu extends StatelessWidget {
  const _WorkItemMenu({
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassPopupMenu<_WorkItemAction?>(
      value: null,
      width: 210,
      items: [
        if (canEdit)
          GlassMenuItem<_WorkItemAction?>(
            value: _WorkItemAction.edit,
            label: context.t('common.edit'),
            leading: Icon(LucideIcons.pencil, size: 16, color: AppColors.ink),
          ),
        if (canDelete)
          GlassMenuItem<_WorkItemAction?>(
            value: _WorkItemAction.delete,
            label: context.t('common.delete'),
            color: AppColors.danger,
            dividerAbove: canEdit,
            leading: const Icon(
              LucideIcons.trash2,
              size: 16,
              color: AppColors.danger,
            ),
          ),
      ],
      onSelected: (action) => switch (action) {
        _WorkItemAction.edit => onEdit(),
        _WorkItemAction.delete => onDelete(),
        null => null,
      },
      child: Tooltip(
        message: context.t('time.entryActions'),
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(LucideIcons.ellipsis, size: 16, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

class _AllEntriesButton extends StatelessWidget {
  const _AllEntriesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.history,
              size: 15,
              color: AppColors.accentStrong,
            ),
            const SizedBox(width: 6),
            Text(
              context.t('time.allEntries', variables: {'count': '$count'}),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.accentStrong,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              forwardChevron(context),
              size: 14,
              color: AppColors.accentStrong,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens every entry of [issue] in a glass sheet that pages the server as the
/// reader scrolls. [onChanged] fires after each edit or delete made inside, so
/// the host can refetch its own head of the list once the sheet closes.
Future<void> showAllWorkItemsSheet(
  BuildContext context, {
  required Issue issue,
  required WorkItemAccess access,
  required String? Function(String userId) nameFor,
  required String? Function(String userId) avatarFor,
  required VoidCallback onChanged,
}) {
  // The sheet is a root-navigator route, so it does not inherit the caller's
  // providers — hand the repository across explicitly.
  final repository = context.read<IssueRepository>();
  return showGlassModal<void>(
    context,
    width: 600,
    builder: (_) => RepositoryProvider<IssueRepository>.value(
      value: repository,
      child: AllWorkItemsSheet(
        issue: issue,
        access: access,
        nameFor: nameFor,
        avatarFor: avatarFor,
        onChanged: onChanged,
      ),
    ),
  );
}

/// Body of [showAllWorkItemsSheet]: a header naming the issue and its total,
/// then the entries, newest first, in an infinite scroll over the paged route.
class AllWorkItemsSheet extends StatefulWidget {
  const AllWorkItemsSheet({
    super.key,
    required this.issue,
    required this.access,
    required this.nameFor,
    required this.avatarFor,
    required this.onChanged,
    this.pageSize = 50,
  });

  final Issue issue;
  final WorkItemAccess access;
  final String? Function(String userId) nameFor;
  final String? Function(String userId) avatarFor;
  final VoidCallback onChanged;
  final int pageSize;

  @override
  State<AllWorkItemsSheet> createState() => _AllWorkItemsSheetState();
}

class _AllWorkItemsSheetState extends State<AllWorkItemsSheet> {
  late final IssueRepository _repository;
  late final PagedCubit<WorkItem> _cubit;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Resolved once — the fetcher closure outlives this build and every
    // loadMore would otherwise walk the element tree again.
    _repository = context.read<IssueRepository>();
    _cubit = PagedCubit<WorkItem>(
      (page, size) =>
          _repository.workItemsPage(widget.issue.id, page: page, size: size),
      pageSize: widget.pageSize,
      keyOf: (item) => item.id,
    )..load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cubit.close();
    super.dispose();
  }

  /// Infinite scroll: pull the next page as the reader nears the bottom.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 240) _cubit.loadMore();
  }

  /// A correction updates the row in place. Reloading would start the paging
  /// over, which on a long-running issue throws away every page the reader has
  /// scrolled through, drops them back to the top and immediately fetches the
  /// next page — all to change one line they are looking at.
  Future<void> _edit(WorkItem item) async {
    final patched = await showEditWorkItem(context, widget.issue.id, item);
    if (patched == null) return;
    _cubit.replaceItem(patched);
    widget.onChanged();
  }

  Future<void> _delete(WorkItem item) async {
    if (!await confirmDeleteWorkItem(context, item)) return;
    _cubit.removeItem(item.id);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.history,
          title: context.t('time.allEntriesTitle'),
          subtitle:
              '${widget.issue.readableId} · '
              '${context.t('time.loggedTotal', variables: {'spent': fmtDuration(context, widget.issue.spentMinutes)})}',
        ),
        Flexible(
          child: BlocBuilder<PagedCubit<WorkItem>, PagedState<WorkItem>>(
            bloc: _cubit,
            builder: _body,
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, PagedState<WorkItem> state) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    if (state.isLoading && !state.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: HiveLoader(size: 22)),
      );
    }
    final errorKey = state.errorKey;
    if (errorKey != null && !state.hasData) {
      return Padding(
        padding: EdgeInsets.fromLTRB(22, 8, 22, 22 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(errorKey),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _cubit.load,
              icon: const Icon(LucideIcons.rotateCcw, size: 15),
              label: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }
    final items = state.items;
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: HiveEmptyState(
          card: false,
          title: context.t('time.noEntries'),
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        ),
      );
    }
    final showLoader = state.isLoadingMore;
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(22, 4, 22, 18 + bottomInset),
      itemCount: items.length + (showLoader ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: HiveLoader(size: 16)),
          );
        }
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 4 : 12),
          child: WorkItemRow(
            item: items[index],
            access: widget.access,
            nameFor: widget.nameFor,
            avatarFor: widget.avatarFor,
            onEdit: _edit,
            onDelete: _delete,
          ),
        );
      },
    );
  }
}
