import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart' show showGlassAnchoredPopover;

/// Result of the on-the-fly epic/parent picker.
///
/// `null` from [showEpicSearchPopover] means dismissed. Otherwise:
/// - [clear] true → detach the current parent (patch `parentId: ''`);
/// - [issue] non-null → attach that issue as parent (patch `parentId: id`).
class EpicPickResult {
  const EpicPickResult.pick(this.issue) : clear = false;
  const EpicPickResult.clear()
      : issue = null,
        clear = true;

  final Issue? issue;
  final bool clear;
}

/// Opens the inline, server-searched epic/parent picker anchored to [anchorRect]
/// (the tapped "epic hinzufügen" row). Mirrors the "Vorgang verknüpfen" inline
/// UX — a search field, a recency-ordered list, and real-time filtering — but
/// backed by a **debounced, paginated server query** rather than an in-memory
/// snapshot, so it stays fast and complete on large projects.
///
/// [forSubtask] switches the target set: sub-tasks attach to a standard issue,
/// standard issues attach to an epic. [hasCurrentParent] toggles the leading
/// "no epic" (detach) row.
Future<EpicPickResult?> showEpicSearchPopover(
  BuildContext context, {
  required Rect anchorRect,
  required String projectId,
  required String currentIssueId,
  required bool forSubtask,
  required bool hasCurrentParent,
}) {
  return showGlassAnchoredPopover<EpicPickResult>(
    context,
    anchorRect: anchorRect,
    width: 360,
    minHeight: 180,
    maxHeight: 420,
    builder: (_) => _EpicSearchPanel(
      projectId: projectId,
      currentIssueId: currentIssueId,
      forSubtask: forSubtask,
      hasCurrentParent: hasCurrentParent,
    ),
  );
}

class _EpicSearchPanel extends StatefulWidget {
  const _EpicSearchPanel({
    required this.projectId,
    required this.currentIssueId,
    required this.forSubtask,
    required this.hasCurrentParent,
  });

  final String projectId;
  final String currentIssueId;
  final bool forSubtask;
  final bool hasCurrentParent;

  @override
  State<_EpicSearchPanel> createState() => _EpicSearchPanelState();
}

class _EpicSearchPanelState extends State<_EpicSearchPanel> {
  static const _debounceDelay = Duration(milliseconds: 180);
  static const _pageSize = 25;

  IssueRepository get _repo => context.read<IssueRepository>();

  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<Issue> _results = [];
  final Set<String> _seen = {};
  String _query = '';
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  /// Monotonic request token — a debounced search that lands after a newer one
  /// started is discarded, so a slow response can never overwrite fresh results.
  int _reqSeq = 0;

  bool get _hasMore => _results.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Autofocus so the user can type immediately; page 0 (empty query) is the
    // recency-ordered "recent" list.
    _focus.requestFocus();
    _runSearch(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _runSearch(reset: true));
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 120) {
      _runSearch(reset: false);
    }
  }

  Future<void> _runSearch({required bool reset}) async {
    if (reset) {
      _debounce?.cancel();
    } else {
      // Load-more guard: only when there's another page and we're idle.
      if (_loadingMore || _loading || !_hasMore) return;
    }

    final seq = ++_reqSeq;
    final page = reset ? 0 : _page + 1;
    final query = _query.trim();

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });

    try {
      // Epics can be filtered server-side by type. For sub-tasks the parent must
      // be any *standard* issue (not EPIC/SUBTASK); the search endpoint's `type`
      // param takes a single value, so we query untyped and drop non-standard
      // rows per page. Standard issues dominate a project, so pages stay dense.
      final res = await _repo.issues(
        projectId: widget.projectId,
        type: widget.forSubtask ? null : 'EPIC',
        query: query.isEmpty ? null : query,
        page: page,
        size: _pageSize,
      );
      if (!mounted || seq != _reqSeq) return;

      final incoming = res.issues.where((i) {
        if (i.id == widget.currentIssueId) return false;
        if (widget.forSubtask && !i.isStandard) return false;
        return true;
      });

      setState(() {
        if (reset) {
          _results.clear();
          _seen.clear();
        }
        for (final i in incoming) {
          if (_seen.add(i.id)) _results.add(i);
        }
        _page = page;
        _total = res.total;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiFailure {
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _pick(Issue issue) =>
      Navigator.of(context).pop(EpicPickResult.pick(issue));

  void _clear() => Navigator.of(context).pop(const EpicPickResult.clear());

  @override
  Widget build(BuildContext context) {
    final isEmptyQuery = _query.trim().isEmpty;
    final headerKey = isEmptyQuery
        ? (widget.forSubtask
            ? 'issues.epicPicker.recentParents'
            : 'issues.epicPicker.recent')
        : 'issues.epicPicker.results';
    // Only standard issues can detach to "no epic"; sub-tasks always need a
    // parent, so the clear row is offered for epics only.
    final showClear = !widget.forSubtask && widget.hasCurrentParent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchField(),
        Divider(height: 1, thickness: 1, color: AppColors.hairline),
        if (showClear) _ClearRow(onTap: _clear),
        Padding(
          padding: EdgeInsets.fromLTRB(14, showClear ? 4 : 12, 14, 6),
          child: Text(
            context.t(headerKey),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.inkFaint,
            ),
          ),
        ),
        Flexible(child: _buildResults()),
      ],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _focus,
        onChanged: _onQueryChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(
            LucideIcons.search,
            size: 17,
            color: AppColors.inkFaint,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
          hintText: context.t(
            widget.forSubtask
                ? 'issues.epicPicker.searchParentsHint'
                : 'issues.epicPicker.searchHint',
          ),
          hintStyle: TextStyle(color: AppColors.inkFaint, fontSize: 14),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        child: Text(
          context.t(
            widget.forSubtask
                ? 'issues.epicPicker.noParentResults'
                : 'issues.epicPicker.noResults',
          ),
          style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 8),
      shrinkWrap: true,
      itemCount: _results.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _EpicTile(issue: _results[i], onTap: () => _pick(_results[i]));
      },
    );
  }
}

/// Leading "no epic" (detach) row, shown for standard issues that already have a
/// parent.
class _ClearRow extends StatelessWidget {
  const _ClearRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(LucideIcons.circleSlash, size: 17, color: AppColors.inkFaint),
            const SizedBox(width: 10),
            Text(
              context.t('issues.epicPicker.clear'),
              style: TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// One result row — reuses the visual language of the link-issue suggestion
/// tile (type glyph · readable id · title).
class _EpicTile extends StatelessWidget {
  const _EpicTile({required this.issue, required this.onTap});

  final Issue issue;
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
          ],
        ),
      ),
    );
  }
}
