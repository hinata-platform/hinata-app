import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:hinata/core/theme/glass_chrome.dart'
    show GlassCircleButton, navGlass;
import 'package:hinata/features/shell/app_shell.dart' show isNativeApp;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart' show ApiFailure;
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/util/file_download.dart';
import '../../core/widgets/frosted_surface.dart';
import '../../core/widgets/glass_bulk_bar.dart';
import '../../core/widgets/glass_filter_bar.dart'
    show GlassPill, WideToolbar, kGlassControlHeight;
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/person_picker.dart' show showPersonPicker;
import '../../core/widgets/subtask_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../sprint/modals/glass_modal.dart'
    show
        GlassToastKind,
        showGlassConfirm,
        showGlassOptions,
        showGlassToast,
        showGlassToastIn,
        showGlassDatePicker,
        showGlassDateRangePicker;
import '../reports/logo_raster.dart';
import '../shell/page_chrome.dart';
import 'deadline_editor.dart';
import 'issue_detail_sheet.dart';
import 'issue_export.dart';
import 'issue_filter.dart';
import 'issue_filter_popup.dart';
import 'issue_form.dart';
import 'issue_move_wizard.dart';
import 'issues_cubit.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/widgets/user_pronouns.dart';
import '../../core/theme/app_type.dart';

part 'issues_screen.toolbar.dart';
part 'issues_screen.rows.dart';
part 'issues_screen.bulk.dart';

/// Shared lookup data for rendering issue rows — loaded once alongside the
/// paginated issue stream (users → names/avatars, projects → names/palette and
/// the unioned workflow-state order for status grouping).
typedef _RefData = ({
  Map<String, String> names,
  Map<String, String> avatars,
  Map<String, String> pronouns,
  Map<String, String> projectNames,
  List<String> stateOrder,
  ProjectPalette palette,
});

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({
    super.key,
    this.projectId,
    this.initialView,
    this.scopeProjectIds = const [],
    this.assigneeId,
  });

  final String? projectId;

  /// Optional preset the screen opens pre-filtered on (dashboard KPI deep-link).
  final IssuesInitialView? initialView;

  /// Project scope carried from the dashboard so a KPI deep-link reproduces the
  /// same project selection the card was counted with. Empty ⇒ all projects.
  final List<String> scopeProjectIds;

  /// Opens the list on one person's issues (`/issues?assignee=<id>`), the
  /// link a person's profile offers (HIN-165).
  final String? assigneeId;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  /// Empty lookups so rows can still render if reference data fails to load
  /// (names fall back to ids) without blocking the issue list.
  static final _RefData _emptyRef = (
    names: const {},
    avatars: const {},
    pronouns: const {},
    projectNames: const {},
    stateOrder: const [],
    palette: ProjectPalette.empty,
  );

  static const int _pageSize = 100;

  late final IssuesListCubit _issues;

  /// Built on the first export, not with the screen: only an export reads the
  /// server's meta and logo.
  IssuesExportCubit? _exporter;
  final ScrollController _scroll = ScrollController();

  // Reference data (users + projects), loaded once in parallel with page 0.
  _RefData? _ref;
  bool _refLoading = true;
  bool _refError = false;

  // Guards the "export everything" flow so the menu can't fire twice.
  bool _exporting = false;

  /// Multi-select for bulk actions (move to another project, one deadline for
  /// all). Entered by long-pressing a row — the same gesture the comment
  /// thread uses — after which a plain tap toggles instead of opening the
  /// issue. The head also carries a toggle for it: a long press with a mouse
  /// is something nobody tries, and a screen reader or switch user cannot
  /// press and hold at all.
  ///
  /// Keyed by issue id, holding the project each ticked issue belongs to,
  /// noted the moment it is ticked. Whether a selection sits in one project is
  /// read from here rather than from the loaded rows, which a reload may have
  /// replaced in the meantime.
  final Map<String, String> _selected = {};
  bool _selectionMode = false;

  /// Whether selection mode was switched on deliberately with the head's
  /// toggle rather than by a long press. Then it stays on with nothing
  /// selected: somebody who asked for it is about to pick rows, and the mode
  /// vanishing under them after unticking the first one would be a surprise.
  bool _selectionPinned = false;

  /// While a bulk request runs; keeps the bar's actions from firing twice.
  bool _bulkBusy = false;

  /// The projects whose issues the caller may delete, read once with the
  /// reference data. Null while unknown, or when the server cannot say: Delete
  /// then shows, and the server decides as it always does.
  Set<String>? _deletable;

  /// The row a shift-click range starts from: the last one ticked or unticked
  /// on its own.
  String? _rangeAnchor;

  /// Takes the list's keyboard shortcuts (select all, Delete, Escape) on a
  /// wide window, where the hardware keyboard is.
  final FocusNode _keys = FocusNode(debugLabel: 'issues list');

  /// Projects by id, kept from the reference load, so a bulk deadline can
  /// count from the event date of the one project a selection belongs to.
  Map<String, Project> _projectsById = const {};

  /// Whether the phone-layout tip about long-pressing is still to be shown.
  /// Read once from [AppStorage] as the screen opens. False where no storage
  /// is provided, so a screen without it just shows no tip.
  bool _showSelectHint = false;

  void _enterSelection(Issue issue) {
    setState(() {
      _selectionMode = true;
      _selected[issue.id] = issue.projectId;
      _rangeAnchor = issue.id;
    });
    _takeKeys();
    // Whoever found the long press on their own needs no tip about it.
    if (_showSelectHint) _dismissSelectHint();
  }

  void _toggleSelection(Issue issue) => setState(() {
    if (_selected.remove(issue.id) == null) {
      _selected[issue.id] = issue.projectId;
    }
    _rangeAnchor = issue.id;
    // Deselecting the last row leaves selection mode, so a stray long-press
    // never strands the list with no way out but the ✕. Not when the mode was
    // asked for with the toggle; see [_selectionPinned].
    if (_selected.isEmpty && !_selectionPinned) {
      _selectionMode = false;
      _rangeAnchor = null;
    }
  });

  void _exitSelection() => setState(() {
    _selectionMode = false;
    _selectionPinned = false;
    _selected.clear();
    _rangeAnchor = null;
  });

  /// Whether a shift key is down: a click then extends the selection.
  bool get _rangeKey => HardwareKeyboard.instance.isShiftPressed;

  /// Whether ⌘ or Ctrl is down: a click then ticks a row instead of opening it.
  bool get _addKey =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  /// A row tapped outside selection mode. With shift, ⌘ or Ctrl held it starts
  /// a selection, as in a file manager; a plain tap opens the issue.
  void _tapRow(Issue issue) {
    if (_rangeKey && _rangeAnchor != null) {
      _selectRange(issue);
    } else if (_rangeKey || _addKey) {
      _enterSelection(issue);
    } else {
      showIssueDetailSheet(context, issueId: issue.id);
    }
  }

  /// A row tapped in selection mode: shift extends from the anchor, anything
  /// else ticks or unticks the one row.
  void _toggleRow(Issue issue) => _rangeKey && _rangeAnchor != null
      ? _selectRange(issue)
      : _toggleSelection(issue);

  /// Ticks every visible row from the anchor to [issue], both included, in the
  /// order they are shown. Capped like select all.
  void _selectRange(Issue issue) {
    final visible = _visibleIssues();
    final from = visible.indexWhere((i) => i.id == _rangeAnchor);
    final to = visible.indexWhere((i) => i.id == issue.id);
    if (from < 0 || to < 0) {
      _selectionMode ? _toggleSelection(issue) : _enterSelection(issue);
      return;
    }
    final range = visible.sublist(
      from < to ? from : to,
      (from < to ? to : from) + 1,
    );
    _addToSelection(range);
    _takeKeys();
  }

  /// Ticks [issues] up to what one bulk request may carry, and says so when
  /// that cut the selection short.
  void _addToSelection(Iterable<Issue> issues) {
    const max = IssueRepository.bulkDeadlineMax;
    var capped = false;
    setState(() {
      _selectionMode = true;
      for (final issue in issues) {
        if (_selected.containsKey(issue.id)) continue;
        if (_selected.length >= max) {
          capped = true;
          break;
        }
        _selected[issue.id] = issue.projectId;
      }
    });
    if (capped) {
      showGlassToast(
        context,
        context.t('issues.selectAllCapped', variables: {'max': '$max'}),
      );
    }
  }

  /// The rows on screen in the order they are shown: the loaded rows that match
  /// the current view, minus those folded away in a collapsed group.
  List<Issue> _visibleIssues() => _grouping == IssueGrouping.none
      ? _viewList
      : [
          for (final section in _viewSections)
            if (!_collapsed.contains(section.key)) ...section.issues,
        ];

  /// Moves keyboard focus to the list, so Delete and Escape reach it, unless
  /// somebody is typing: their field keeps it.
  void _takeKeys() {
    if (_typing || _keys.hasFocus) return;
    _keys.requestFocus();
  }

  /// Whether a text field has the keyboard. The list's shortcuts stand aside
  /// then, so Backspace deletes a character and ⌘A selects text, not issues.
  bool get _typing {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Refetches from page 0 because the server query changed (filter, sort).
  ///
  /// The selection is dropped with it: the ticked rows may not be part of the
  /// new result at all, and a bulk action on rows the reader can no longer see
  /// would be a surprise. A mode switched on with the toggle stays on.
  void _reloadFromStart() {
    if (_selected.isNotEmpty || _selectionMode) {
      setState(() {
        _selected.clear();
        // A range would otherwise start from a row clicked in the old order.
        _rangeAnchor = null;
        if (!_selectionPinned) _selectionMode = false;
      });
    }
    _issues.load();
  }

  /// The head's toggle: into selection mode with nothing selected yet, or out
  /// of it again.
  void _toggleSelectionMode() {
    if (_selectionMode) {
      _exitSelection();
      return;
    }
    setState(() {
      _selectionMode = true;
      _selectionPinned = true;
    });
  }

  /// Ticks every row on screen: the loaded rows that match the current view,
  /// minus those folded away in a collapsed group. Capped at what one bulk
  /// request may carry, so "select all" never builds a selection the bar's
  /// actions would then refuse.
  void _selectAllVisible() {
    _addToSelection(_visibleIssues());
    _takeKeys();
  }

  /// Hides the long-press tip for good on this server.
  void _dismissSelectHint() {
    setState(() => _showSelectHint = false);
    unawaited(context.read<AppStorage?>()?.setMultiSelectHintSeen());
  }

  /// Whether the selection fits one bulk request; says so when it does not.
  bool _selectionFits() {
    const max = IssueRepository.bulkDeadlineMax;
    if (_selected.length <= max) return true;
    showGlassToast(
      context,
      context.t('issues.bulkDeadline.tooMany', variables: {'max': '$max'}),
      kind: GlassToastKind.error,
    );
    return false;
  }

  /// Runs one bulk request with the bar's actions held off until it answers,
  /// and turns a refusal into a toast in the reader's language.
  Future<void> _runBulk(Future<void> Function() request) async {
    if (!mounted || _bulkBusy) return;
    setState(() => _bulkBusy = true);
    try {
      await request();
    } on ApiFailure catch (failure) {
      if (mounted) {
        showGlassToast(
          context,
          context.t(failure.message),
          kind: GlassToastKind.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showGlassToast(
          context,
          context.t('errors.unexpected'),
          kind: GlassToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  /// Takes the server's answer to a change of fields into the list.
  ///
  /// The selection stays, so a second field can follow the first, and the rows
  /// are swapped in place: the pages already scrolled through stay, and
  /// nothing is fetched again. Not under a filter or a time range, though: a
  /// changed row may no longer belong there, so the list is read again and the
  /// selection goes with it, as on every refetch.
  void _adoptBulkChange(List<Issue> updated) {
    if (_hasActiveView) {
      _exitSelection();
      _issues.load();
    } else {
      _issues.replaceItems(updated);
    }
    // The board and the dashboard show these issues too and hear it on the
    // app-wide bus; this screen skips its own message.
    IssueEvents.instance.notifyChanged(origin: this);
  }

  /// One deadline for every selected issue.
  ///
  /// Rules that follow an event date are offered only where they can mean one
  /// thing: the module is on, and every selected issue sits in the same
  /// project, whose event date they would count from. Otherwise a date is all
  /// there is to choose. The server applies it to all of them or to none.
  Future<void> _setDeadlineSelected() async {
    if (_selected.isEmpty || _bulkBusy || !_selectionFits()) return;
    final ids = _selected.keys.toList();
    final meta = context.read<AppConfigBloc?>()?.state.meta;
    final projectIds = _selected.values.toSet();
    final project = projectIds.length == 1
        ? _projectsById[projectIds.first]
        : null;
    final choice = await _askBulkDeadline(
      context,
      count: ids.length,
      offsetsOffered: meta?.projectTemplates ?? false,
      project: project,
      defaultBasis: deadlineBasisFor(project, meta),
      // Only asked while a rule is on offer, which needs the one project.
      resolve: (offset) async {
        if (project == null) return null;
        return _issues.resolveOffset(project.id, offset: offset);
      },
    );
    if (choice == null || !mounted) return;
    await _runBulk(() async {
      final updated = await _issues.bulkSetDeadline(
        ids,
        // A rule's day is only what the editor showed; the server writes the
        // real one from the rule, so it is not sent alongside.
        dueDate: choice.offset == null ? choice.date : null,
        dueOffset: choice.offset,
        clearDueDate: choice.cleared,
      );
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(
          choice.cleared
              ? 'issues.bulkDeadline.cleared'
              : 'issues.bulkDeadline.done',
          count: updated.length,
        ),
        kind: GlassToastKind.success,
      );
      _adoptBulkChange(updated);
    });
  }

  /// Sets the state, the priority or the assignee of every selected issue.
  Future<void> _updateSelected({
    String? state,
    String? priority,
    String? assigneeId,
  }) async {
    if (_selected.isEmpty || !_selectionFits()) return;
    final ids = _selected.keys.toList();
    await _runBulk(() async {
      final updated = await _issues.bulkUpdate(
        ids,
        state: state,
        priority: priority,
        assigneeId: assigneeId,
      );
      if (!mounted) return;
      showGlassToast(
        context,
        context.t('issues.bulk.updated', count: updated.length),
        kind: GlassToastKind.success,
      );
      _adoptBulkChange(updated);
    });
  }

  /// The states every selected issue's project has, in the first project's
  /// order. Empty when the projects share none, or one is not loaded.
  List<String> _sharedStates() {
    final projects = [
      for (final id in _selected.values.toSet()) _projectsById[id],
    ];
    if (projects.isEmpty || projects.contains(null)) return const [];
    return [
      for (final state in projects.first!.stateNames)
        if (projects.every((p) => p!.stateNames.contains(state))) state,
    ];
  }

  Future<void> _pickStatusSelected(Rect anchor) async {
    if (_selected.isEmpty || _bulkBusy) return;
    final states = _sharedStates();
    if (states.isEmpty) {
      showGlassToast(context, context.t('issues.bulk.noCommonStatus'));
      return;
    }
    final palette = _ref?.palette;
    final chosen = await showGlassOptions<String>(
      context,
      title: context.t('issues.status'),
      anchorRect: anchor,
      options: [
        for (final s in states)
          (
            value: s,
            child: StateDotBadge(state: s, color: palette?.stateColor(s)),
          ),
      ],
    );
    if (chosen != null && mounted) await _updateSelected(state: chosen);
  }

  Future<void> _pickPrioritySelected(Rect anchor) async {
    if (_selected.isEmpty || _bulkBusy) return;
    final chosen = await showGlassOptions<String>(
      context,
      title: context.t('issues.priority'),
      anchorRect: anchor,
      options: [
        for (final p in kIssuePriorityCodes)
          (value: p, child: PriorityFlag(priority: p, withLabel: true)),
      ],
    );
    if (chosen != null && mounted) await _updateSelected(priority: chosen);
  }

  /// Assigns every selected issue to one person, or to nobody.
  ///
  /// Two steps at most: the short list (me, somebody else, nobody), and the
  /// searchable, server-paged directory only for "somebody else". Assigning
  /// replaces who was on the issues before, as the single picker does. The
  /// server refuses a person who cannot open every one of the projects.
  Future<void> _pickAssigneeSelected(Rect anchor) async {
    if (_selected.isEmpty || _bulkBusy) return;
    final me = context.read<AuthBloc?>()?.state.user;
    final choice = await showGlassOptions<_AssignChoice>(
      context,
      title: context.t('issues.bulk.assignee'),
      anchorRect: anchor,
      options: [
        if (me != null)
          (
            value: _AssignChoice.me,
            child: _OptionLabel(
              icon: LucideIcons.userCheck,
              label: context.t('issues.assignToMe'),
            ),
          ),
        (
          value: _AssignChoice.someone,
          child: _OptionLabel(
            icon: LucideIcons.userSearch,
            label: context.t('issues.bulk.pickPerson'),
          ),
        ),
        (
          value: _AssignChoice.nobody,
          child: _OptionLabel(
            icon: LucideIcons.userX,
            label: context.t('issues.bulk.unassign'),
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _AssignChoice.me:
        await _updateSelected(assigneeId: me!.id);
      case _AssignChoice.nobody:
        await _updateSelected(assigneeId: '');
      case _AssignChoice.someone:
        final person = await showPersonPicker(
          context,
          anchorRect: anchor,
          meId: me?.id,
        );
        if (person != null && mounted) {
          await _updateSelected(assigneeId: person.id);
        }
    }
  }

  /// Archives the selected issues, or restores them in the archive view, and
  /// offers to take it back.
  ///
  /// No question first: nothing is lost, and the toast's Undo is the faster way
  /// back from a slip than a dialog in front of every deliberate archive. The
  /// rows leave the list in place, sub-tasks with their parents, so the pages
  /// already scrolled through stay; Undo puts them back where they were.
  Future<void> _archiveSelected() async {
    if (_selected.isEmpty || _bulkBusy || !_selectionFits()) return;
    final ids = _selected.keys.toList();
    final archive = !_filter.archivedOnly;
    // Held now: Undo may come after this screen is gone.
    final repo = context.read<IssueRepository>();
    final overlay = Overlay.of(context, rootOverlay: true);
    await _runBulk(() async {
      final result = await _issues.bulkArchive(ids, archived: archive);
      if (!mounted) return;
      _exitSelection();
      final gone = {...result.toggledIds, ...result.toggledSubtaskIds};
      final removed = [
        for (final (index, issue) in _issues.state.items.indexed)
          if (gone.contains(issue.id) ||
              (issue.isSubtask && gone.contains(issue.parentId)))
            (index: index, item: issue),
      ];
      _issues.removeWhere(
        (issue) =>
            gone.contains(issue.id) ||
            (issue.isSubtask && gone.contains(issue.parentId)),
      );
      IssueEvents.instance.notifyChanged(origin: this);
      if (gone.isEmpty) return;
      showGlassToast(
        context,
        context.t(
          archive ? 'issues.bulk.archived' : 'issues.bulk.restored',
          count: result.issues.length,
        ),
        kind: GlassToastKind.success,
        actionLabel: context.t('issues.bulk.undo'),
        onAction: () => _undoArchive(
          repo: repo,
          overlay: overlay,
          switched: result,
          archived: archive,
          removed: removed,
        ),
      );
    });
  }

  /// Takes an archive (or a restore) back: exactly the issues it switched, with
  /// nothing cascading, so a sub-task archived on its own before stays so.
  ///
  /// Works after this screen is gone too, which is why it reaches the server
  /// through the repository and speaks through the root overlay. While the
  /// screen is still there, the rows go back where they were; had the list been
  /// read again in between, a row already back is left alone.
  Future<void> _undoArchive({
    required IssueRepository repo,
    required OverlayState overlay,
    required BulkArchiveResult switched,
    required bool archived,
    required List<({int index, Issue item})> removed,
  }) async {
    String t(String key, {int? count}) => overlay.context.t(key, count: count);
    try {
      final result = await repo.bulkArchive(
        switched.toggledIds,
        archived: !archived,
        cascade: false,
        subtaskIds: switched.toggledSubtaskIds,
      );
      final fresh = {for (final issue in result.issues) issue.id: issue};
      if (mounted) {
        _issues.reinsert([
          for (final entry in removed)
            (index: entry.index, item: fresh[entry.item.id] ?? entry.item),
        ]);
      }
      IssueEvents.instance.notifyChanged(origin: mounted ? this : null);
      showGlassToastIn(
        overlay,
        t(
          archived ? 'issues.bulk.restored' : 'issues.bulk.archived',
          count: result.issues.length,
        ),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      showGlassToastIn(overlay, t(failure.message), kind: GlassToastKind.error);
    } catch (_) {
      showGlassToastIn(
        overlay,
        t('errors.unexpected'),
        kind: GlassToastKind.error,
      );
    }
  }

  /// Whether Delete is worth showing at all: the caller may delete somewhere,
  /// or the server has not said.
  bool get _deleteOffered => _deletable?.isNotEmpty ?? true;

  /// Whether the server would accept deleting this selection.
  bool get _mayDeleteSelection {
    final allowed = _deletable;
    if (allowed == null) return true;
    return _selected.values.every(allowed.contains);
  }

  /// Deletes the selected issues for good, after asking once for all of them.
  ///
  /// Only project leads and team admins may delete, and the bar offers Delete
  /// only where they are; the server checks again and refuses the whole
  /// request for anybody else.
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _bulkBusy || !_selectionFits()) return;
    final ids = _selected.keys.toList();
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('issues.bulkDelete.title', count: ids.length),
      message: context.t('issues.bulkDelete.message', count: ids.length),
      confirmLabel: context.t('issues.bulkDelete.confirm'),
      confirmIcon: LucideIcons.trash2,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _runBulk(() async {
      final deleted = await _issues.bulkDelete(ids);
      if (!mounted) return;
      showGlassToast(
        context,
        context.t('issues.bulkDelete.done', count: deleted),
        kind: GlassToastKind.success,
      );
      _exitSelection();
      // The board and the dashboard hear it on the app-wide bus; this screen
      // fetches its own rows again, sub-tasks of the deleted issues included.
      IssueEvents.instance.notifyChanged(origin: this);
      // Only the rows: the people, projects and rights the list holds alongside
      // them have not changed.
      await _issues.load();
    });
  }

  /// The overflow: what is rarely done to a selection, and on a phone what
  /// the bar has no room for.
  Future<void> _moreSelected(Rect anchor) async {
    if (_bulkBusy) return;
    final phone = context.isCompact;
    final some = _selected.isNotEmpty;
    // What the bar itself leaves out on a phone, and never the field changes
    // in the archive view.
    final extra = phone && !_filter.archivedOnly;
    final choice = await showGlassOptions<_MoreChoice>(
      context,
      title: context.t('issues.bulk.more'),
      anchorRect: anchor,
      options: [
        if (extra)
          (
            value: _MoreChoice.selectAll,
            child: _OptionLabel(
              icon: LucideIcons.listChecks,
              label: context.t('issues.selectAll'),
            ),
          ),
        if (extra && some) ...[
          (
            value: _MoreChoice.priority,
            child: _OptionLabel(
              icon: LucideIcons.signal,
              label: context.t('issues.priority'),
            ),
          ),
          (
            value: _MoreChoice.deadline,
            child: _OptionLabel(
              icon: LucideIcons.calendarClock,
              label: context.t('issues.bulkDeadline.action'),
            ),
          ),
        ],
        if (some)
          (
            value: _MoreChoice.move,
            child: _OptionLabel(
              icon: LucideIcons.folderInput,
              label: context.t('issues.move.action'),
            ),
          ),
        if (extra && some && _deleteOffered && _mayDeleteSelection)
          (
            value: _MoreChoice.delete,
            child: _OptionLabel(
              icon: LucideIcons.trash2,
              label: context.t('issues.bulkDelete.action'),
              danger: true,
            ),
          ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _MoreChoice.selectAll:
        _selectAllVisible();
      case _MoreChoice.priority:
        await _pickPrioritySelected(anchor);
      case _MoreChoice.deadline:
        await _setDeadlineSelected();
      case _MoreChoice.move:
        await _moveSelected();
      case _MoreChoice.delete:
        await _deleteSelected();
    }
  }

  /// Bulk-moves the selected issues. The wizard asks for the target project and
  /// the status mapping once for the whole set.
  Future<void> _moveSelected() async {
    if (_selected.isEmpty) return;
    // A selection may span projects (the unscoped list shows all of them); only
    // a single-project selection can pre-exclude its own project as a target.
    final projectIds = _selected.values.toSet();
    final moved = await showIssueMoveWizard(
      context,
      issueIds: _selected.keys.toList(),
      currentProjectId: projectIds.length == 1 ? projectIds.first : null,
    );
    if (moved != true || !mounted) return;
    _exitSelection();
    await _issues.load();
  }

  IssueFilter _filter = IssueFilter.empty;
  IssueGrouping _grouping = IssueGrouping.none;
  IssueTimeRange _timeRange = IssueTimeRange.none;

  /// Server-side ordering. Changing it refetches from page 0 so the order is
  /// correct across the whole result set, not just the loaded pages.
  IssueSort _sort = IssueSort.defaultSort;

  // Memoized filter/section sweep. While a filter is active the screen pulls
  // every backend page in the background, and each intermediate rebuild would
  // otherwise re-run the full _filtered/_sections over the whole growing list.
  // These cache the last result keyed on the exact inputs, so a rebuild with
  // unchanged (loaded set + filter/time/grouping/ref) reuses it instead.
  List<Issue>? _viewAll;
  Object? _viewRef;
  IssueFilter? _viewFilter;
  IssueTimeRange? _viewTimeRange;
  IssueGrouping? _viewGrouping;
  List<Issue> _viewList = const [];
  List<_Section> _viewSections = const [];

  /// The deep-link preset is applied once, after projects load (so bucket
  /// presets can resolve to real state names); later refreshes keep the user's
  /// own filter choices.
  bool _initialViewApplied = false;

  /// Group keys currently collapsed in the grouped view (mirrors the board's
  /// swimlane collapse). Cleared whenever the grouping dimension changes.
  final Set<String> _collapsed = {};

  final GlobalKey _filterKey = GlobalKey();

  /// Re-fetch when an issue is created/changed elsewhere (e.g. the global
  /// nav-rail "new issue" button, which can't reach this screen's cubit).
  StreamSubscription<Object?>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((origin) {
      // Changes this screen made itself are already in its rows.
      if (!identical(origin, this)) _reload();
    });
    _issues = IssuesListCubit(
      issues: context.read<IssueRepository>(),
      projects: context.read<ProjectRepository>(),
      users: context.read<UserRepository>(),
      query: () => _query,
      pageSize: _pageSize,
    )..load();
    _scroll.addListener(_onScroll);
    _loadRef();
    // Nullable lookup: the storage is there in the app, and a test that does
    // not care about the tip need not provide it.
    _showSelectHint =
        !(context.read<AppStorage?>()?.multiSelectHintSeen ?? true);
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _keys.dispose();
    _scroll.dispose();
    _issues.close();
    _exporter?.close();
    super.dispose();
  }

  /// Loads users + projects into [_ref]. Best-effort: a failure leaves rows to
  /// render with id fallbacks rather than blocking the whole screen.
  Future<void> _loadRef() async {
    if (mounted) {
      setState(() {
        _refLoading = true;
        _refError = false;
      });
    }
    try {
      final deletable = _loadDeletable();
      final (:users, :projects) = await _issues.reference();
      final mayDelete = await deletable;
      // Workflow-state order (UPPER-CASE), unioned across projects in first-seen
      // order, so status grouping lists columns the way the projects define them.
      final stateOrder = <String>[];
      final seenStates = <String>{};
      for (final p in projects) {
        for (final name in p.stateNames) {
          final code = name.toUpperCase();
          if (seenStates.add(code)) stateOrder.add(code);
        }
      }
      if (!mounted) return;
      setState(() {
        _deletable = mayDelete;
        _projectsById = {for (final p in projects) p.id: p};
        _ref = (
          names: {for (final u in users) u.id: u.displayName},
          avatars: {
            for (final u in users)
              if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                u.id: u.avatarUrl!,
          },
          pronouns: pronounsById(users),
          projectNames: {for (final p in projects) p.id: p.name},
          stateOrder: stateOrder,
          palette: ProjectPalette.fromProjects(projects),
        );
        _refLoading = false;
        // Apply a dashboard deep-link preset once, now that we know the
        // projects' workflow/resolved states.
        if (!_initialViewApplied && widget.initialView != null) {
          _applyInitialView(widget.initialView!, projects);
          _initialViewApplied = true;
        } else if (!_initialViewApplied && widget.assigneeId != null) {
          _filter = IssueFilter(assignees: {widget.assigneeId!});
          _initialViewApplied = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refLoading = false;
        _refError = true;
      });
    }
  }

  /// Where the caller may delete issues; null when the server cannot say, so a
  /// failure here never takes the list down with it.
  Future<Set<String>?> _loadDeletable() async {
    try {
      return await _issues.deletableProjectIds();
    } catch (_) {
      return null;
    }
  }

  /// Translates a dashboard KPI deep-link preset into the concrete filter/time
  /// range. Bucket presets use the same rule as the dashboard's server-side
  /// completion split: done = the projects' resolved states, backlog =
  /// `Backlog`/`Open`, in-progress = everything else.
  void _applyInitialView(IssuesInitialView view, List<Project> projects) {
    // Each preset fully defines the view — start from a clean slate so nothing
    // from a previous state (filter or time range) leaks in.
    _filter = IssueFilter.empty;
    _timeRange = IssueTimeRange.none;
    // The dashboard's project scope (if any) applies to every preset so the
    // filtered list reproduces exactly what the KPI card counted.
    final scope = widget.scopeProjectIds.toSet();
    if (view == IssuesInitialView.today) {
      // "Today's tasks" = my open issues due today or overdue — the exact set the
      // dashboard KPI counts, so the filtered list length matches the card.
      final me = context.read<AuthBloc>().state.user?.id;
      _filter = IssueFilter(
        assignees: me == null ? const {} : {me},
        projects: scope,
      );
      _timeRange = const IssueTimeRange(preset: IssueTimePreset.dueByToday);
      return;
    }
    final done = <String>{};
    final all = <String>{};
    for (final p in projects) {
      for (final name in p.resolvedStates) {
        done.add(name.toUpperCase());
      }
      for (final name in p.stateNames) {
        all.add(name.toUpperCase());
      }
    }
    const backlog = {'BACKLOG', 'OPEN'};
    final states = switch (view) {
      IssuesInitialView.done => done,
      IssuesInitialView.backlog => all.intersection(backlog),
      IssuesInitialView.inProgress => all.difference(done).difference(backlog),
      IssuesInitialView.today => const <String>{},
    };
    _filter = IssueFilter(states: states, projects: scope);
  }

  /// Pull-to-refresh / retry: reload the first page and the reference data.
  Future<void> _reload() => Future.wait([_issues.load(), _loadRef()]);

  /// Infinite scroll: pull the next page as the user nears the bottom. The
  /// cubit guards against overlapping or past-the-end requests.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _issues.loadMore();
    }
  }

  // ── filtering / sorting ────────────────────────────────────────────────

  /// Applies the active filter + time-range to the loaded pages. Ordering is
  /// intentionally left to the backend (the `?sort=` param, see [_sort]) so it
  /// holds across the whole paginated result set — re-sorting here would only
  /// reorder the pages currently in memory and fight the server order.
  List<Issue> _filtered(List<Issue> issues) =>
      issues.where((i) => _filter.matches(i) && _timeRange.matches(i)).toList();

  /// Returns the filtered list + grouped sections for [all]/[ref], reusing the
  /// last computation when every input is unchanged. Cheap references — during
  /// the background page sweep `all` is a new list each page (so it correctly
  /// recomputes), but the many other rebuilds (SSE on peers, keyboard, theme)
  /// hit the cache instead of re-sweeping the whole accumulated set.
  ({List<Issue> list, List<_Section> sections}) _view(
    List<Issue> all,
    _RefData ref,
  ) {
    if (identical(all, _viewAll) &&
        identical(ref, _viewRef) &&
        identical(_filter, _viewFilter) &&
        identical(_timeRange, _viewTimeRange) &&
        _grouping == _viewGrouping) {
      return (list: _viewList, sections: _viewSections);
    }
    final list = _filtered(all);
    final sections = _sections(list, ref);
    _viewAll = all;
    _viewRef = ref;
    _viewFilter = _filter;
    _viewTimeRange = _timeRange;
    _viewGrouping = _grouping;
    _viewList = list;
    _viewSections = sections;
    return (list: list, sections: sections);
  }

  // ── grouping ──────────────────────────────────────────────────────────

  /// Buckets [list] into ordered sections for the active grouping. Returns an
  /// empty list when grouping is off (the caller renders a flat list instead).
  List<_Section> _sections(List<Issue> list, _RefData data) {
    if (_grouping == IssueGrouping.none) return const [];
    final buckets = <String, List<Issue>>{};
    String keyOf(Issue i) => switch (_grouping) {
      IssueGrouping.state => i.state.toUpperCase(),
      IssueGrouping.priority => i.priority.toUpperCase(),
      IssueGrouping.assignee =>
        (i.assigneeId?.isNotEmpty ?? false) ? i.assigneeId! : _kNone,
      IssueGrouping.project => i.projectId,
      IssueGrouping.type => i.type.toUpperCase(),
      IssueGrouping.none => '',
    };
    for (final issue in list) {
      buckets.putIfAbsent(keyOf(issue), () => []).add(issue);
    }
    final keys = buckets.keys.toList()..sort(_keyComparator(data));
    return [
      for (final k in keys)
        _Section(
          key: k,
          header: _groupHeader(k, buckets[k]!.length, data),
          issues: buckets[k]!,
        ),
    ];
  }

  int Function(String, String) _keyComparator(_RefData data) {
    switch (_grouping) {
      case IssueGrouping.state:
        return (a, b) {
          final ia = data.stateOrder.indexOf(a);
          final ib = data.stateOrder.indexOf(b);
          final ra = ia == -1 ? data.stateOrder.length : ia;
          final rb = ib == -1 ? data.stateOrder.length : ib;
          return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
        };
      case IssueGrouping.priority:
        // Backend codes (see [kIssuePriorityCodes]) with the legacy aliases
        // interleaved at the matching severity, so old data still groups right.
        const order = [
          'SHOWSTOPPER',
          'CRITICAL',
          'URGENT',
          'MAJOR',
          'HIGH',
          'NORMAL',
          'MINOR',
          'LOW',
          'TRIVIAL',
        ];
        return (a, b) => _rankIn(order, a).compareTo(_rankIn(order, b));
      case IssueGrouping.type:
        const order = ['EPIC', 'STORY', 'TASK', 'BUG', 'FEATURE', 'SUBTASK'];
        return (a, b) => _rankIn(order, a).compareTo(_rankIn(order, b));
      case IssueGrouping.assignee:
        return (a, b) {
          if (a == _kNone) return 1;
          if (b == _kNone) return -1;
          return (data.names[a] ?? a).toLowerCase().compareTo(
            (data.names[b] ?? b).toLowerCase(),
          );
        };
      case IssueGrouping.project:
        return (a, b) => (data.projectNames[a] ?? a).toLowerCase().compareTo(
          (data.projectNames[b] ?? b).toLowerCase(),
        );
      case IssueGrouping.none:
        return (a, b) => 0;
    }
  }

  Widget _groupHeader(String key, int count, _RefData data) {
    Widget leading;
    String label;
    switch (_grouping) {
      case IssueGrouping.state:
        leading = _Dot(color: data.palette.stateColor(key));
        label = stateLabel(key);
      case IssueGrouping.priority:
        leading = PriorityFlag(priority: key);
        label = _enumLabel(context, 'priority', key);
      case IssueGrouping.type:
        leading = TypeGlyph(type: key, size: 18);
        label = _enumLabel(context, 'type', key);
      case IssueGrouping.assignee:
        if (key == _kNone) {
          leading = Icon(
            LucideIcons.userX,
            size: 18,
            color: AppColors.inkFaint,
          );
          label = context.t('issues.unassigned');
        } else {
          final name = data.names[key] ?? key;
          leading = HiveAvatar(
            name: name,
            imageUrl: data.avatars[key],
            size: 22,
          );
          label = name;
        }
      case IssueGrouping.project:
        leading = Icon(LucideIcons.folder, size: 17, color: AppColors.inkFaint);
        label = data.projectNames[key] ?? key;
      case IssueGrouping.none:
        leading = const SizedBox.shrink();
        label = '';
    }
    return _GroupHeader(leading: leading, label: label, count: count);
  }

  // ── actions ───────────────────────────────────────────────────────────

  void _openFilter(_RefData data) => openIssueFilter(
    context,
    anchorKey: _filterKey,
    filter: _filter,
    // Options come from reference data (all states/projects/users + the fixed
    // type/priority enums), not the loaded issues — the list is now
    // server-filtered, so deriving options from it would hide facet
    // values the current result page happens not to contain.
    options: IssueFilterOptions.reference(
      states: data.stateOrder,
      assignees: data.names.keys.toList(),
      projects: data.projectNames.keys.toList(),
    ),
    names: data.names,
    avatars: data.avatars,
    projectNames: data.projectNames,
    onChanged: (f) {
      // Facets the backend expresses (state/priority/type/assignee + archived)
      // change the server query, so the page cache must be refetched when the
      // server-query signature changes. Purely client-side facets (project /
      // time range / "unassigned") only need a rebuild.
      final before = _serverQuerySignature;
      setState(() => _filter = f);
      if (_serverQuerySignature != before) _reloadFromStart();
    },
  );

  /// Opens the filter popup against the *current* loaded issues + reference
  /// data. Used as a stable callback for the pinned toolbar so its header
  /// delegate need not rebuild every time a new page loads (it reads the fresh
  /// data at tap time instead of closing over a build snapshot).
  void _openFilterCurrent() => _openFilter(_ref ?? _emptyRef);

  /// Whether the reference data has loaded and names no project at all: the
  /// caller belongs to none, which is where somebody an issue was shared with
  /// stands (HIN-136).
  bool _withoutProjects(_RefData ref) =>
      !identical(ref, _emptyRef) &&
      ref.projectNames.isEmpty &&
      widget.projectId == null;

  void _onGroupingChanged(IssueGrouping g) => setState(() {
    _grouping = g;
    _collapsed.clear();
  });

  /// Sort is server-side: change the order and refetch from page 0 so it
  /// applies to the whole result set, not just the loaded pages.
  void _onSortChanged(IssueSort s) {
    if (s == _sort) return;
    setState(() => _sort = s);
    _reloadFromStart();
  }

  void _onTimeRangeChanged(IssueTimeRange r) => setState(() => _timeRange = r);

  Future<void> _newIssue() async {
    final created = await showIssueForm(context, projectId: widget.projectId);
    if (created != null && mounted) _reload();
  }

  // A tear-off, so the bar's action compares equal across rebuilds and the
  // page does not re-publish its chrome every frame.
  void _newIssueFromBar(Rect? _) => unawaited(_newIssue());

  /// Fixed height of the toolbar when docked into the app bar (compact).
  static const double _kDockedToolbarHeight = 56;

  /// The view-controls toolbar (group · sort · filter · time · export), built
  /// with the live state + stable callbacks. Docked into the app bar on compact
  /// (so it shares the bar's single glass blur — no separate band); rendered as
  /// a normal in-scroll row on wide.
  Widget _toolbar() => _Toolbar(
    grouping: _grouping,
    onGrouping: _onGroupingChanged,
    sort: _sort,
    onSort: _onSortChanged,
    filterCount: _filter.activeCount,
    filterKey: _filterKey,
    onFilter: _openFilterCurrent,
    timeRange: _timeRange,
    onTimeRange: _onTimeRangeChanged,
    onExport: _export,
    exporting: _exporting,
    selecting: _selectionMode,
    onToggleSelection: _toggleSelectionMode,
  );

  Future<void> _export(String format) async {
    if (_exporting) return;
    // Read inherited blocs / repositories before the first await to avoid using
    // context across async gaps.
    final cachedMeta = context.read<AppConfigBloc>().state.meta;
    final exporter = _exporter ??= IssuesExportCubit(
      issues: context.read<IssueRepository>(),
      meta: context.read<MetaRepository>(),
    );
    setState(() => _exporting = true);
    try {
      // Export EVERY matching issue, not just the pages scrolled into view:
      // page through the whole backend result set first so the file is complete
      // regardless of how far the user has scrolled.
      final List<Issue> all;
      try {
        all = await exporter.all(_query);
      } catch (_) {
        if (mounted) {
          _toast(context.t('reports.exportFailed'), kind: GlassToastKind.error);
        }
        return;
      }
      if (!mounted) return;
      final ref = _ref ?? _emptyRef;

      if (format == 'pdf') {
        ServerMeta? meta = cachedMeta;
        try {
          meta = await exporter.meta();
        } catch (_) {
          meta = cachedMeta;
        }
        Uint8List? logoPng;
        try {
          final logoAsset = await exporter.organizationLogo();
          if (logoAsset != null) {
            logoPng = await logoToPng(
              bytes: logoAsset.bytes,
              isSvg: logoAsset.isSvg,
            );
          }
        } catch (_) {
          logoPng = null;
        }
        if (!mounted) return;
        final failMsg = context.t('reports.exportFailed');
        try {
          await shareIssuesPdf(_buildExportData(ref, all, meta, logoPng));
        } catch (_) {
          _toast(failMsg, kind: GlassToastKind.error);
        }
        return;
      }

      final data = _buildExportData(ref, all, null, null);
      final isCsv = format == 'csv';
      final content = isCsv ? buildIssuesCsv(data) : buildIssuesJson(data);
      final mime = isCsv ? 'text/csv' : 'application/json';
      final exportedMsg = context.t(
        'reports.exported',
        variables: {'format': format.toUpperCase()},
      );
      final copiedMsg = context.t(
        'reports.copied',
        variables: {'format': format.toUpperCase()},
      );
      if (kIsWeb) {
        // Browsers block window.open() to a data: URL ("Not allowed to navigate
        // top frame to data URL"), so trigger a real Blob download instead —
        // and surface a proper error if it fails rather than a false success.
        final result = await downloadBytes(
          'issues-export.${isCsv ? 'csv' : 'json'}',
          Uint8List.fromList(utf8.encode(content)),
          mime,
        );
        if (!mounted) return;
        if (result.outcome == DownloadOutcome.failed) {
          _toast(context.t('reports.exportFailed'), kind: GlassToastKind.error);
        } else {
          _toast(exportedMsg, kind: GlassToastKind.success);
        }
      } else {
        await Clipboard.setData(ClipboardData(text: content));
        _toast(copiedMsg, kind: GlassToastKind.success);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  IssueExportData _buildExportData(
    _RefData ref,
    List<Issue> allIssues,
    ServerMeta? meta,
    Uint8List? logoPng,
  ) {
    final list = _filtered(allIssues);
    final names = ref.names;
    final projectNames = ref.projectNames;

    IssueExportRow rowOf(Issue i) => (
      id: i.readableId,
      title: i.title,
      status: stateLabel(i.state),
      priority: _enumLabel(context, 'priority', i.priority.toUpperCase()),
      assignee: (i.assigneeId?.isNotEmpty ?? false)
          ? (names[i.assigneeId] ?? i.assigneeId!)
          : context.t('issues.unassigned'),
      project: projectNames[i.projectId] ?? i.projectId,
      type: _enumLabel(context, 'type', i.type.toUpperCase()),
      due: i.dueDate?.toIso8601String().substring(0, 10) ?? '',
    );

    final grouped = _grouping != IssueGrouping.none;
    final List<IssueExportGroup> groups;
    if (grouped) {
      groups = [
        for (final s in _sections(list, ref))
          (
            title: _sectionLabel(s.key, ref),
            rows: [for (final i in s.issues) rowOf(i)],
          ),
      ];
    } else {
      groups = [
        (title: '', rows: [for (final i in list) rowOf(i)]),
      ];
    }

    final scope = widget.projectId != null
        ? (projectNames[widget.projectId] ?? context.t('nav.issues'))
        : context.t('board.allProjects');

    return IssueExportData(
      orgName: (meta?.organizationName?.trim().isNotEmpty ?? false)
          ? meta!.organizationName!.trim()
          : 'Hinata',
      logoBytes: logoPng,
      scopeLabel: scope,
      generatedAt: DateTime.now(),
      locale: Localizations.localeOf(context).toString(),
      groups: groups,
      grouped: grouped,
      groupByLabel: grouped
          ? '${context.t('board.groupBy')}: ${_groupingLabel(context, _grouping)}'
          : null,
      filterSummary: _filterSummary(names, projectNames),
      labels: (
        reportTitle: context.t('reports.issuesReport'),
        issuesCount: context.t(
          'issues.countSummary',
          variables: {'count': '${list.length}'},
        ),
        generatedPrefix: context.t('reports.generatedPrefix'),
        pageLabel: context.t('reports.page'),
        colId: context.t('issues.colId'),
        colTitle: context.t('issues.colTitle'),
        colStatus: context.t('issues.colStatus'),
        colPriority: context.t('issues.colPriority'),
        colAssignee: context.t('issues.colAssignee'),
        colDue: context.t('issues.colDue'),
      ),
    );
  }

  /// A plain-text label for a group key (no widgets) — used by the PDF/CSV/JSON
  /// export, which can't render header widgets.
  String _sectionLabel(String key, _RefData data) => switch (_grouping) {
    IssueGrouping.state => stateLabel(key),
    IssueGrouping.priority => _enumLabel(context, 'priority', key),
    IssueGrouping.type => _enumLabel(context, 'type', key),
    IssueGrouping.assignee =>
      key == _kNone ? context.t('issues.unassigned') : (data.names[key] ?? key),
    IssueGrouping.project => data.projectNames[key] ?? key,
    IssueGrouping.none => '',
  };

  List<String> _filterSummary(
    Map<String, String> names,
    Map<String, String> projectNames,
  ) {
    final out = <String>[];
    String join(String prefix, Iterable<String> values) =>
        '$prefix: ${values.join(', ')}';
    if (_filter.states.isNotEmpty) {
      out.add(
        join(context.t('issues.colStatus'), _filter.states.map(stateLabel)),
      );
    }
    if (_filter.priorities.isNotEmpty) {
      out.add(
        join(
          context.t('issues.colPriority'),
          _filter.priorities.map((p) => _enumLabel(context, 'priority', p)),
        ),
      );
    }
    if (_filter.types.isNotEmpty) {
      out.add(
        join(
          context.t('issues.type'),
          _filter.types.map((t) => _enumLabel(context, 'type', t)),
        ),
      );
    }
    if (_filter.assignees.isNotEmpty) {
      out.add(
        join(
          context.t('issues.colAssignee'),
          _filter.assignees.map(
            (a) => a == IssueFilter.noAssignee
                ? context.t('issues.unassigned')
                : (names[a] ?? a),
          ),
        ),
      );
    }
    if (_filter.projects.isNotEmpty) {
      out.add(
        join(
          context.t('issues.project'),
          _filter.projects.map((p) => projectNames[p] ?? p),
        ),
      );
    }
    if (_filter.archivedOnly) {
      out.add(context.t('issues.filterArchived'));
    }
    if (_timeRange.isActive) {
      out.add(
        '${context.t('issues.timeRange')}: ${_timeLabel(context, _timeRange)}',
      );
    }
    return out;
  }

  void _toast(String message, {GlassToastKind kind = GlassToastKind.info}) {
    if (!mounted) return;
    showGlassToast(context, context.t(message), kind: kind);
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PagedCubit<Issue>, PagedState<Issue>>(
      bloc: _issues,
      builder: (context, state) {
        final ref = _ref ?? _emptyRef;
        final all = state.items;
        final view = _view(all, ref);
        final list = view.list;
        final sections = view.sections;

        // Project-scoped view: surface which project is open — the project
        // name becomes the page title (and the shell app-bar title via
        // PageChrome), with the generic "Issues" label demoted to the
        // subtitle. Falls back to "Issues" while reference data loads.
        final projectName = widget.projectId != null
            ? ref.projectNames[widget.projectId]
            : null;

        // State/priority/type/assignee facets are now applied by the backend
        // so the returned pages are already reduced and normal paged
        // scroll suffices. Only the residual client-side facets (multi-project,
        // time range, "unassigned") still filter the loaded pages, so we eagerly
        // pull the remaining (already server-reduced) pages ONLY then —
        // otherwise a match beyond the first page would never surface.
        if (_hasClientResidual && state.hasMore && !state.isLoadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _issues.loadMore();
          });
        }

        // True while a residual client-side filter is still pulling pages but has
        // matched nothing yet — show a spinner instead of a premature "no results".
        final searchingMore =
            list.isEmpty &&
            (state.isLoadingMore || (_hasClientResidual && state.hasMore));

        final compact = context.isCompact;
        // Only a wide window draws this head. On a phone the bar above says
        // the page's name already, "+" sits in the bar beside the bell and the
        // selection switch in the docked toolbar beside the export.
        final head = PageHead(
          title: projectName ?? context.t('nav.issues'),
          subtitle: projectName != null
              ? '${context.t('nav.issues')} · ${_subtitle(list.length, state.total)}'
              : _subtitle(list.length, state.total),
          actions: [
            // Selection without holding: nobody holds a mouse button down on
            // a row to see what happens, and a screen reader or switch user
            // cannot press and hold at all.
            _SelectionToggle(
              active: _selectionMode,
              onTap: _toggleSelectionMode,
            ),
            PrimaryButton(
              icon: LucideIcons.plus,
              label: context.t('issues.new'),
              collapseToIcon: true,
              onPressed: _newIssue,
            ),
          ],
        );
        return PageChrome(
          title: projectName ?? context.t('nav.issues'),
          // The bar's own "+": with an action in it the title moves to the
          // leading edge, where a project's name has the room to be read.
          actions: compact
              ? [
                  PageAction(
                    icon: LucideIcons.plus,
                    label: context.t('issues.new'),
                    primary: true,
                    onTap: _newIssueFromBar,
                  ),
                ]
              : const [],
          // On compact the toolbar docks into the app bar (shared blur, no
          // separate band); on wide it stands under the title, above the list.
          bottom: compact
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
                  child: Center(child: _toolbar()),
                )
              : null,
          bottomHeight: compact ? _kDockedToolbarHeight : 0,
          child: _keyboard(
            compact: compact,
            child: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _reload,
                  color: AppColors.accent,
                  edgeOffset: context.topGutter,
                  child: AsyncView(
                    isLoading:
                        state.isLoading ||
                        (_refLoading && _ref == null && !_refError),
                    hasData: state.hasData && (_ref != null || _refError),
                    errorKey: state.errorKey,
                    onRetry: _reload,
                    builder: (context) {
                      final scroll = CustomScrollView(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          // On a phone the list starts right under the bar; the
                          // head is the bar's title and buttons there.
                          if (compact)
                            SliverToBoxAdapter(
                              child: SizedBox(height: context.topGutter + 12),
                            ),
                          // The long-press tip, once per server, and only where
                          // there is a row to press.
                          if (compact &&
                              _showSelectHint &&
                              !_selectionMode &&
                              list.isNotEmpty)
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                context.pageGutter,
                                0,
                                context.pageGutter,
                                4,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: _SelectHint(
                                  onDismiss: _dismissSelectHint,
                                ),
                              ),
                            ),
                          if (list.isEmpty && !searchingMore)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: context.pageGutter,
                                  vertical: 40,
                                ),
                                child: HiveEmptyState(
                                  title: context.t('nav.issues'),
                                  message: _hasActiveView
                                      ? context.t('issues.emptyFiltered')
                                      : _withoutProjects(ref)
                                      ? context.t(
                                          'issues.participants.emptyIssuesHint',
                                        )
                                      : context.t('issues.empty'),
                                  action:
                                      !_hasActiveView && _withoutProjects(ref)
                                      // Somebody in no project finds what is
                                      // shared with them on the watched page.
                                      ? OutlinedButton(
                                          onPressed: () => GoRouter.of(
                                            context,
                                          ).go('/watched'),
                                          child: Text(
                                            context.t(
                                              'issues.participants.openWatched',
                                            ),
                                          ),
                                        )
                                      : _hasActiveView
                                      ? OutlinedButton(
                                          onPressed: () {
                                            final refetch =
                                                _filter.archivedOnly;
                                            setState(() {
                                              _filter = IssueFilter.empty;
                                              _timeRange = IssueTimeRange.none;
                                            });
                                            if (refetch) _reloadFromStart();
                                          },
                                          child: Text(
                                            context.t('board.clearFilters'),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            )
                          else if (list.isNotEmpty)
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                context.pageGutter,
                                12,
                                context.pageGutter,
                                14,
                              ),
                              // Measured here rather than read off the window:
                              // the rail and the gutters take their share first,
                              // and the table only pays off when what is left
                              // gives the title room to be read.
                              sliver: SliverLayoutBuilder(
                                builder: (context, constraints) {
                                  final table = issueTableFits(
                                    context,
                                    constraints.crossAxisExtent,
                                  );
                                  // Lightweight row descriptors (headers / issues /
                                  // spacers) fed to a lazy builder, so only on-screen
                                  // rows are ever built — a workspace with thousands of
                                  // issues no longer constructs every SoftCard per frame.
                                  final entries =
                                      _grouping == IssueGrouping.none
                                      ? _flatEntries(list, table: table)
                                      : _groupedEntries(sections);
                                  return SliverList.builder(
                                    itemCount: entries.length,
                                    itemBuilder: (context, i) => _buildEntry(
                                      entries[i],
                                      ref.names,
                                      ref.avatars,
                                      ref.pronouns,
                                      ref.palette,
                                      table: table,
                                    ),
                                  );
                                },
                              ),
                            ),
                          // Infinite-scroll footer: the standard HiveLoader while the next
                          // page (or a filter's background sweep) is loading.
                          if (state.isLoadingMore || searchingMore)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(child: HiveLoader(size: 30)),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              // Extra room while selecting so the floating bulk bar
                              // never covers the last row.
                              height:
                                  context.pageGutter +
                                  context.bottomGutter +
                                  (_selectionMode && compact ? 72 : 0),
                            ),
                          ),
                        ],
                      );
                      if (compact) return scroll;
                      // On a wide window the head and the tools stay where they
                      // are while the list scrolls, as on the boards and the
                      // time pages: narrowing a long list should not start with
                      // scrolling back up to its top.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              context.pageGutter,
                              24 + context.topGutter,
                              context.pageGutter,
                              14,
                            ),
                            child: head,
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              context.pageGutter,
                              0,
                              context.pageGutter,
                              14,
                            ),
                            child: _toolbarSlot(),
                          ),
                          Expanded(child: scroll),
                        ],
                      );
                    },
                  ),
                ),
                // On a phone the bulk-action bar docks above the nav, where the
                // thumb is. The dock measures from the nav's own edge; the scroll
                // gutter counts the home indicator twice on an iPhone. Wider
                // windows show it at the top instead; see [_toolbarSlot].
                if (_selectionMode && compact)
                  GlassBulkBarDock(child: _bulkBar()),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The bar of actions on the selected issues.
  ///
  /// Grouped and divided as people scan it: what acts on the selection (select
  /// all), what changes the issues' fields, what takes them out of the list,
  /// and the overflow. The field actions open a menu and say so with a chevron.
  /// Disabled, not hidden, while nothing is ticked: the bar then says what it
  /// will offer once something is. Delete appears only where the caller may
  /// delete; everybody can archive.
  ///
  /// A phone has room for four icons beside the count, so it keeps the three
  /// most used changes in the bar and moves the rest into the overflow, which
  /// opens there as a sheet with labels.
  ///
  /// The archive view offers restoring, deleting and moving, not field changes:
  /// an archived issue is out of the work, and editing its state or deadline
  /// there would change something nobody sees until it is restored.
  Widget _bulkBar() {
    final none = _selected.isEmpty || _bulkBusy;
    final archiveView = _filter.archivedOnly;
    final phone = context.isCompact;
    final count = context.t(
      'issues.selectedCount',
      variables: {'count': '${_selected.length}'},
    );
    final delete = GlassBulkAction(
      icon: LucideIcons.trash2,
      label: context.t('issues.bulkDelete.action'),
      danger: true,
      onTap: none || !_mayDeleteSelection ? null : _deleteSelected,
      disabledReason: !none && !_mayDeleteSelection
          ? context.t('issues.bulk.deleteNotAllowed')
          : null,
    );
    return GlassBulkBar(
      countLabel: phone && !archiveView ? '${_selected.length}' : count,
      countSemanticsLabel: count,
      onClear: _exitSelection,
      clearTooltip: context.t('issues.selection.exit'),
      labelledMinWidth: archiveView ? 640 : 1120,
      leading: phone && !archiveView
          ? null
          : GlassBulkAction(
              icon: LucideIcons.listChecks,
              label: context.t('issues.selectAll'),
              onTap: _bulkBusy ? null : _selectAllVisible,
            ),
      actions: [
        if (!archiveView) ...[
          GlassBulkAction(
            icon: LucideIcons.circleDot,
            label: context.t('issues.status'),
            menu: true,
            onTapAt: none ? null : _pickStatusSelected,
          ),
          if (!phone)
            GlassBulkAction(
              icon: LucideIcons.signal,
              label: context.t('issues.priority'),
              menu: true,
              onTapAt: none ? null : _pickPrioritySelected,
            ),
          GlassBulkAction(
            icon: LucideIcons.userRound,
            label: context.t('issues.bulk.assignee'),
            menu: true,
            onTapAt: none ? null : _pickAssigneeSelected,
          ),
          if (!phone) ...[
            GlassBulkAction(
              icon: LucideIcons.calendarClock,
              label: context.t('issues.bulkDeadline.action'),
              onTap: none ? null : _setDeadlineSelected,
            ),
            const GlassBulkDivider(),
          ],
        ],
        GlassBulkAction(
          icon: archiveView ? LucideIcons.archiveRestore : LucideIcons.archive,
          label: context.t(archiveView ? 'issues.unarchive' : 'issues.archive'),
          onTap: none ? null : _archiveSelected,
        ),
        // Last of the strip, and red, so it is never the action a hurried tap
        // lands on.
        if (_deleteOffered && (archiveView || !phone)) delete,
        GlassBulkAction(
          icon: LucideIcons.ellipsis,
          label: context.t('issues.bulk.more'),
          iconOnly: true,
          // Select all stays reachable with nothing ticked yet.
          onTapAt: _bulkBusy || (none && !(phone && !archiveView))
              ? null
              : _moreSelected,
        ),
      ],
    );
  }

  /// What the list's shortcuts do, made once: each reads the state when it is
  /// pressed, so a rebuild for every ticked row need not make new ones.
  late final Map<Type, Action<Intent>> _keyActions = {
    _SelectAllIssuesIntent: _ListKeyAction<_SelectAllIssuesIntent>(
      enabled: () => !_typing && !_bulkBusy && _viewList.isNotEmpty,
      run: () {
        if (!_selectionMode) _selectionPinned = true;
        _selectAllVisible();
      },
    ),
    _ExitSelectionIntent: _ListKeyAction<_ExitSelectionIntent>(
      enabled: () => !_typing && _selectionMode,
      run: _exitSelection,
    ),
    _DeleteSelectionIntent: _ListKeyAction<_DeleteSelectionIntent>(
      enabled: () =>
          !_typing &&
          _selectionMode &&
          _selected.isNotEmpty &&
          !_bulkBusy &&
          _deleteOffered &&
          _mayDeleteSelection,
      run: _deleteSelected,
    ),
  };

  /// The list's keyboard shortcuts: ⌘A (Ctrl+A) selects every row on screen,
  /// Escape ends the selection, Delete or Backspace deletes it. Each stands
  /// aside while a text field has the keyboard, or while it could not act, so
  /// the key reaches whatever else wants it.
  Widget _keyboard({required bool compact, required Widget child}) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            _SelectAllIssuesIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _SelectAllIssuesIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _ExitSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.delete): _DeleteSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): _DeleteSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.backspace, meta: true):
            _DeleteSelectionIntent(),
      },
      child: Actions(
        actions: _keyActions,
        child: Focus(focusNode: _keys, autofocus: !compact, child: child),
      ),
    );
  }

  /// The tools row of a wide window, which the bulk bar takes over while
  /// selecting.
  ///
  /// At the bottom of a large window the bar sat far from where anyone is
  /// looking. Up here it is next to the head, and it replaces the tools rather
  /// than adding a row: changing a filter or the sort drops the selection
  /// anyway, and the hidden tools keep their height, so the list does not move
  /// as the bar comes and goes.
  Widget _toolbarSlot() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        Visibility(
          visible: !_selectionMode,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: _toolbar(),
        ),
        Positioned.fill(
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxHeight: double.infinity,
            alignment: AlignmentDirectional.centerStart,
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _selectionMode
                  ? KeyedSubtree(key: const ValueKey('bulk'), child: _bulkBar())
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ),
      ],
    );
  }

  bool get _hasActiveView => !_filter.isEmpty || _timeRange.isActive;

  // ── server-pushed facets ──────────────────────────────────────────
  // The backend expresses state/priority/type/assignee directly, so a filtered
  // page comes back already reduced and we no longer drain every page for them.

  /// What the list and its export ask the server for, as the head shows it.
  IssueListQuery get _query => (
    projectId: widget.projectId,
    archived: _filter.archivedOnly,
    states: _serverStates,
    priorities: _serverPriorities,
    types: _serverTypes,
    assigneeIds: _serverAssignees,
    sort: _sort.wire,
  );

  List<String>? get _serverStates =>
      _filter.states.isEmpty ? null : _filter.states.toList();
  List<String>? get _serverPriorities =>
      _filter.priorities.isEmpty ? null : _filter.priorities.toList();
  List<String>? get _serverTypes =>
      _filter.types.isEmpty ? null : _filter.types.toList();

  /// Assignee ids are server-pushable only when the "unassigned" sentinel is not
  /// among them — the backend `$in` can't also express "has no assignee", so
  /// that case falls back to client-side filtering (and paging).
  List<String>? get _serverAssignees =>
      (_filter.assignees.isEmpty ||
          _filter.assignees.contains(IssueFilter.noAssignee))
      ? null
      : _filter.assignees.toList();

  /// Facets that still run client-side ([_filtered]) because the backend can't
  /// express them: the multi-project facet, the schedule-aware time range, and
  /// the "unassigned" sentinel. While any is active a server page may still be
  /// reduced locally, so we page the (already server-reduced) result set to keep
  /// the filtered list complete — the same behaviour as before, over far less
  /// data.
  bool get _hasClientResidual =>
      _filter.projects.isNotEmpty ||
      _timeRange.isActive ||
      _filter.assignees.contains(IssueFilter.noAssignee);

  /// Signature of the facets sent to the backend; when it changes the paged
  /// cubit must refetch from page 0 because the server query itself changed.
  String get _serverQuerySignature {
    String csv(Iterable<String> v) => (v.toList()..sort()).join(',');
    return '${csv(_filter.states)}|${csv(_filter.priorities)}|'
        '${csv(_filter.types)}|${csv(_serverAssignees ?? const [])}|'
        '${_filter.archivedOnly}';
  }

  /// [shown] is the number of currently-matched rows; [total] is the backend's
  /// full count (so it reflects everything, not just the pages loaded so far).
  String _subtitle(int shown, int total) {
    if (_hasActiveView) {
      return context.t(
        'issues.countFiltered',
        variables: {'count': '$shown', 'total': '$total'},
      );
    }
    return context.t('issues.countSummary', variables: {'count': '$total'});
  }

  /// Flat (ungrouped) row descriptors: an optional table header then one entry
  /// per issue. Cheap to build every frame — the actual [IssueRow] widgets are
  /// constructed lazily by [_buildEntry] only when scrolled into view.
  List<_RowEntry> _flatEntries(List<Issue> list, {required bool table}) => [
    if (table) const _RowEntry.tableHeader(),
    for (final issue in list) _RowEntry.issue(issue),
  ];

  /// Grouped row descriptors: a collapsible header per section, its issues (when
  /// expanded), and a trailing spacer.
  List<_RowEntry> _groupedEntries(List<_Section> sections) {
    final rows = <_RowEntry>[];
    for (final section in sections) {
      final collapsed = _collapsed.contains(section.key);
      rows.add(_RowEntry.sectionHeader(section, collapsed));
      if (!collapsed) {
        for (final issue in section.issues) {
          rows.add(_RowEntry.issue(issue));
        }
      }
      rows.add(_RowEntry.spacer(collapsed ? 6 : 10));
    }
    return rows;
  }

  /// Builds the widget for a single [_RowEntry] on demand.
  Widget _buildEntry(
    _RowEntry entry,
    Map<String, String> names,
    Map<String, String> avatars,
    Map<String, String> pronouns,
    ProjectPalette palette, {
    required bool table,
  }) {
    switch (entry.kind) {
      case _RowKind.tableHeader:
        return const _IssueTableHeader();
      case _RowKind.spacer:
        return SizedBox(height: entry.height);
      case _RowKind.sectionHeader:
        final section = entry.section!;
        return _CollapsibleHeader(
          collapsed: entry.collapsed,
          header: section.header,
          onTap: () => setState(() {
            if (!_collapsed.remove(section.key)) _collapsed.add(section.key);
          }),
        );
      case _RowKind.issue:
        final issue = entry.issue!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: IssueRow(
            issue: issue,
            assignee: names[issue.assigneeId],
            assigneeAvatar: avatars[issue.assigneeId],
            assigneePronouns: pronouns[issue.assigneeId],
            palette: palette,
            table: table,
            selectionMode: _selectionMode,
            selected: _selected.containsKey(issue.id),
            onTap: () => _tapRow(issue),
            onToggleSelect: () => _toggleRow(issue),
            onLongPress: () => _enterSelection(issue),
          ),
        );
    }
  }
}

enum _RowKind { tableHeader, sectionHeader, issue, spacer }

/// A lightweight descriptor for one row in the issues sliver, so the list can be
/// built lazily (only visible rows) instead of materializing every widget.
class _RowEntry {
  const _RowEntry.tableHeader()
    : kind = _RowKind.tableHeader,
      issue = null,
      section = null,
      collapsed = false,
      height = 0;
  const _RowEntry.issue(this.issue)
    : kind = _RowKind.issue,
      section = null,
      collapsed = false,
      height = 0;
  const _RowEntry.sectionHeader(this.section, this.collapsed)
    : kind = _RowKind.sectionHeader,
      issue = null,
      height = 0;
  const _RowEntry.spacer(this.height)
    : kind = _RowKind.spacer,
      issue = null,
      section = null,
      collapsed = false;

  final _RowKind kind;
  final Issue? issue;
  final _Section? section;
  final bool collapsed;
  final double height;
}

/// Sentinel group key for "no assignee".
const _kNone = '__none__';

/// Rank of [value] within [order] (its index), or [order].length when absent so
/// unknown codes sort after the known ones.
int _rankIn(List<String> order, String value) {
  final i = order.indexOf(value);
  return i == -1 ? order.length : i;
}
