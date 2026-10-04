import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/team_models.dart';
import '../../core/repositories/article_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_chrome.dart' show kOnAmber;
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;
import 'data/knowledge_models.dart' show lucideIcon;
import '../../core/theme/app_type.dart';

/// Opens the picker for the knowledge pages of [teamId] a member may read —
/// the "selected pages" half of a team membership's knowledge access.
///
/// Anchored glass popover on wide screens, a glass sheet on phones. Resolves to
/// the picked page ids, or null when dismissed. A picked page includes every
/// page below it, so those rows show as included instead of asking twice.
Future<List<String>?> showTeamPagesPicker(
  BuildContext context, {
  required Rect anchorRect,
  required String teamId,
  required List<String> selected,
  required ArticleRepository articles,
}) {
  final panel = TeamPagesPickerPanel(
    loadPages: (query) => articles.teamPages(teamId, query: query),
    selected: selected,
  );
  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<List<String>>(
      context,
      anchorRect: anchorRect,
      width: 400,
      minHeight: 240,
      maxHeight: 480,
      builder: (_) => panel,
    );
  }
  return showGlassBottomSheet<List<String>>(
    context,
    builder: (_) => SizedBox(height: 480, child: panel),
  );
}

/// The picker's body: note, search, the team's pages as a tree, and a footer
/// that confirms the choice. Public for tests.
///
/// The pages come from the slim team pages endpoint, titles and tree only.
/// Search asks the server ([loadPages] with the query, debounced), so a team
/// with more pages than one answer holds is still searchable to the end. A
/// grant on a page that is not in the current answer is kept as it is: saving
/// must never quietly take away access that nobody touched.
class TeamPagesPickerPanel extends StatefulWidget {
  const TeamPagesPickerPanel({
    super.key,
    required this.loadPages,
    required this.selected,
  });

  /// One answer of the team's pages, narrowed by the search text ('' for all).
  final Future<CappedList<TeamPageRef>> Function(String query) loadPages;
  final List<String> selected;

  @override
  State<TeamPagesPickerPanel> createState() => _TeamPagesPickerPanelState();
}

class _TeamPagesPickerPanelState extends State<TeamPagesPickerPanel> {
  /// How long typing pauses before the server is asked.
  static const _debounce = Duration(milliseconds: 300);

  final _search = TextEditingController();
  late final Set<String> _picked = {...widget.selected};

  /// The rows on screen: the tree while nothing is searched, the matches flat
  /// while something is.
  List<({TeamPageRef page, int depth})> _rows = const [];

  /// Every page any answer brought, so a picked page's children still know
  /// it is above them after a search replaced the rows.
  final Map<String, TeamPageRef> _byId = {};

  /// Each page that is included through a picked page above it, with that
  /// page. Worked out once per pick or answer, not per row per frame.
  Map<String, TeamPageRef> _includedVia = const {};

  bool _loading = true;
  bool _truncated = false;

  /// Whether the last unsearched answer was the whole team: only then does a
  /// picked id missing from it mean the page is gone.
  bool _complete = false;
  String? _error;
  String _query = '';
  Timer? _debounceTimer;

  /// Guards against an older answer landing after a newer one.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => _load(value.trim()));
  }

  Future<void> _load(String query) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final answer = await widget.loadPages(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        for (final p in answer.items) {
          _byId[p.id] = p;
        }
        _query = query;
        _truncated = answer.truncated;
        if (query.isEmpty) _complete = !answer.truncated;
        _rows = query.isEmpty
            ? _treeOrder(answer.items)
            : [for (final p in answer.items) (page: p, depth: 0)];
        _includedVia = _computeIncludedVia();
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  /// Depth-first, siblings by sort order then title. A page whose parent is
  /// not in the list starts a tree of its own.
  static List<({TeamPageRef page, int depth})> _treeOrder(
    List<TeamPageRef> pages,
  ) {
    final ids = {for (final p in pages) p.id};
    final children = <String?, List<TeamPageRef>>{};
    for (final p in pages) {
      final parent = ids.contains(p.parentId) ? p.parentId : null;
      children.putIfAbsent(parent, () => []).add(p);
    }
    for (final list in children.values) {
      list.sort((a, b) {
        final bySort = a.sortOrder.compareTo(b.sortOrder);
        return bySort != 0
            ? bySort
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }
    final out = <({TeamPageRef page, int depth})>[];
    final seen = <String>{};
    void walk(String? parent, int depth) {
      for (final p in children[parent] ?? const <TeamPageRef>[]) {
        if (!seen.add(p.id)) continue;
        out.add((page: p, depth: depth));
        walk(p.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  /// For every known page, the nearest picked page above it. Each page's
  /// answer is kept as it is worked out, so a long chain is walked once.
  Map<String, TeamPageRef> _computeIncludedVia() {
    final via = <String, TeamPageRef?>{};
    TeamPageRef? resolve(String id, Set<String> guard) {
      if (via.containsKey(id)) return via[id];
      final parentId = _byId[id]?.parentId;
      TeamPageRef? found;
      if (parentId != null && guard.add(parentId)) {
        found = _picked.contains(parentId)
            ? _byId[parentId]
            : resolve(parentId, guard);
      }
      return via[id] = found;
    }

    for (final id in _byId.keys) {
      resolve(id, {id});
    }
    return {
      for (final e in via.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  bool get _atLimit => _picked.length >= KnowledgeAccess.maxPages;

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id) && !_atLimit) _picked.add(id);
    _includedVia = _computeIncludedVia();
  });

  /// The picked ids. One that is not among the loaded pages stays, unless the
  /// whole team was loaded without it: then the page is gone, and the server
  /// would refuse the grant over it.
  List<String> _result() => [
    for (final id in _picked)
      if (!_complete || _byId.containsKey(id)) id,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: AppColors.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.t('teams.knowledge.pickerNote'),
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          // The hint is the only caption; the label keeps the field named
          // once the user has typed.
          child: Semantics(
            label: context.t('teams.knowledge.searchPages'),
            textField: true,
            child: TextField(
              controller: _search,
              // On a phone the keyboard would cover half the tree before anyone
              // asked to search; the popover beside a wide form may take focus.
              autofocus:
                  MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: AppType.body),
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
                hintText: context.t('teams.knowledge.searchPages'),
                hintStyle: TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: AppType.body,
                ),
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
                  borderSide: const BorderSide(
                    color: AppColors.accent,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.hairline),
        if (_truncated && !_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(
              context.t('teams.knowledge.truncated'),
              style: TextStyle(
                fontSize: AppType.caption,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        // Takes the height the popover or sheet leaves, and builds only the
        // rows in view: a team can have a couple of thousand pages.
        Flexible(child: _list(_rows)),
        Divider(height: 1, color: AppColors.hairline),
        _footer(),
      ],
    );
  }

  Widget _list(List<({TeamPageRef page, int depth})> visible) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: HiveLoader(size: 18)),
      );
    }
    final error = _error;
    if (error != null || visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        child: Text(
          error != null
              ? context.t(error)
              : context.t(
                  _query.isEmpty
                      ? 'teams.knowledge.noPages'
                      : 'teams.knowledge.noPageMatches',
                ),
          style: TextStyle(color: AppColors.inkFaint, fontSize: AppType.label),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final row = visible[i];
        final page = row.page;
        final picked = _picked.contains(page.id);
        final via = picked ? null : _includedVia[page.id];
        final enabled = via == null && (picked || !_atLimit);
        return _PageRow(
          title: page.title.isEmpty
              ? context.t('knowledge.untitled')
              : page.title,
          icon: page.icon,
          depth: row.depth,
          picked: picked,
          includedVia: via?.title,
          onTap: enabled ? () => _toggle(page.id) : null,
        );
      },
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _atLimit
                  ? context.t(
                      'teams.knowledge.limitReached',
                      variables: {'max': '${KnowledgeAccess.maxPages}'},
                    )
                  : context.t(
                      'teams.knowledge.pagesPicked',
                      variables: {'count': '${_picked.length}'},
                      count: _picked.length,
                    ),
              style: TextStyle(
                fontSize: AppType.caption,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          FilledButton(
            onPressed: _loading
                ? null
                : () => Navigator.of(context).pop(_result()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
            child: Text(context.t('teams.knowledge.apply')),
          ),
        ],
      ),
    );
  }
}

/// One page in the picker: indented by depth, a check that is filled when the
/// page is picked, and a quiet "included" line when a page above it is.
class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.title,
    required this.icon,
    required this.depth,
    required this.picked,
    required this.includedVia,
    required this.onTap,
  });

  final String title;
  final String? icon;
  final int depth;
  final bool picked;
  final String? includedVia;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final included = includedVia != null;
    final on = picked || included;
    return Semantics(
      checked: on,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              14 + depth.clamp(0, 6) * 16.0,
              6,
              14,
              6,
            ),
            child: Row(
              children: [
                Icon(
                  lucideIcon(icon),
                  size: 15,
                  color: on ? AppColors.accentStrong : AppColors.inkSoft,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: picked
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: onTap == null && !included
                              ? AppColors.inkFaint
                              : AppColors.ink,
                        ),
                      ),
                      if (included)
                        Text(
                          context.t(
                            'teams.knowledge.includedVia',
                            variables: {'title': includedVia},
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Check(on: picked, included: included),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on, required this.included});
  final bool on;
  final bool included;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: on
            ? AppColors.accent
            : included
            ? AppColors.accentSoft
            : AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          // An empty box needs a rim that reads on the glass, not a hairline.
          color: on || included ? AppColors.accent : AppColors.inkFaint,
        ),
      ),
      child: on || included
          ? Icon(
              LucideIcons.check,
              size: 14,
              color: on ? kOnAmber : AppColors.accentStrong,
            )
          : null,
    );
  }
}
