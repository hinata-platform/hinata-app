import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/timesheet_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;

/// Weekly timesheet matrix (user × project × day).
///
/// One week at a time, because the server caps the range anyway and a week is
/// what a reader reconciles against a calendar. The page publishes its title and
/// the "today" jump into the shell's glass app bar ([PageChrome]) and takes the
/// full content width: the table is a grid to scan across, not prose to read.
///
/// Admins additionally get a user and a project filter — both server-side
/// parameters, so the narrowing happens in the database rather than by hiding
/// rows that were already fetched. Everyone else sees only their own time (the
/// server refuses another user's), so a filter would have nothing to offer.
class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({super.key});

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  /// Width of a filter field and of the popover it opens, so the dropdown lines
  /// up with the field instead of hanging off it.
  static const double _filterWidth = 232;

  late DateTime _from;
  late DateTime _to;

  List<TimesheetRow> _rows = const [];

  /// Only the people the fetched rows actually name — resolved by id rather
  /// than by draining the whole directory, which grows without bound.
  Map<String, DirectoryUser> _users = const {};

  /// Whether the directory answered for this week's rows. Until it has, an id
  /// that is missing from [_users] means "not looked up yet", not "deleted".
  bool _directoryAnswered = false;

  /// Only the projects this week's rows actually name. The whole catalogue is
  /// never loaded: an instance can hold hundreds of projects, and a week's
  /// table names a handful.
  Map<String, Project> _projectsById = const {};

  bool _loading = true;
  String? _error;

  // Admin filters. The id is what travels to the server; the label is kept
  // beside it so the field can name a pick whose row is not in this week.
  String? _userFilter;
  String? _userFilterLabel;
  String? _projectFilter;
  String? _projectFilterLabel;

  /// Monotonic token, so a slow week that resolves after the reader has already
  /// paged on can never overwrite the week now on screen.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _from = _weekStart(DateTime.now());
    _to = _addDays(_from, 6);
    unawaited(_load());
  }

  /// Monday of [day]'s week, at local midnight.
  ///
  /// Built through the constructor rather than by subtracting a [Duration]:
  /// a duration is an exact number of hours, so in a week that changes clocks
  /// it lands at 23:00 on the day before and the whole grid shifts by one.
  static DateTime _weekStart(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - 1));

  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  bool get _isCurrentWeek => _weekStart(DateTime.now()) == _from;

  bool get _isAdmin => context.watch<AuthBloc>().state.user?.isAdmin ?? false;

  /// Names for exactly the projects [rows] mention. Null when the lookup could
  /// not be made — the table then keeps whatever it already had rather than
  /// blanking a column over a failed label fetch.
  Future<Map<String, Project>?> _resolveProjects(
    List<TimesheetRow> rows,
  ) async {
    final ids = {
      for (final row in rows)
        if (row.projectId != null) row.projectId!,
    };
    if (ids.isEmpty) return const {};
    try {
      final projects = await context.read<ProjectRepository>().resolveProjects(
        ids.toList(),
      );
      return {for (final project in projects) project.id: project};
    } on ApiFailure {
      return null;
    }
  }

  Future<void> _load() async {
    // A filter is an admin affordance, and losing the role hides the field but
    // would not by itself forget the pick behind it — every later week would go
    // on asking for a colleague's rows. (The server refuses, which is what
    // actually protects them; this is so the page stops asking.)
    if (!(context.read<AuthBloc>().state.user?.isAdmin ?? false)) {
      _userFilter = null;
      _userFilterLabel = null;
      _projectFilter = null;
      _projectFilterLabel = null;
    }
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context.read<TimesheetRepository>().timesheet(
        _from,
        _to,
        userId: _userFilter,
        projectId: _projectFilter,
      );
      if (!mounted || seq != _loadSeq) return;
      final labels = await Future.wait([
        _resolveUsers(rows),
        _resolveProjects(rows),
      ]);
      if (!mounted || seq != _loadSeq) return;
      final users = labels[0] as Map<String, DirectoryUser>?;
      final projects = labels[1] as Map<String, Project>?;
      setState(() {
        _rows = rows;
        _users = users ?? _users;
        _projectsById = projects ?? _projectsById;
        _directoryAnswered = users != null;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  /// Names and avatars for exactly the people [rows] mention. Null when the
  /// directory could not be asked — different from "answered, and does not know
  /// this id", which is what makes an account a deleted one.
  Future<Map<String, DirectoryUser>?> _resolveUsers(
    List<TimesheetRow> rows,
  ) async {
    final ids = {
      for (final row in rows)
        if (row.userId.isNotEmpty) row.userId,
    };
    if (ids.isEmpty) return const {};
    try {
      final users = await context.read<UserRepository>().usersByIds(
        ids.toList(),
      );
      return {for (final user in users) user.id: user};
    } on ApiFailure {
      return null;
    }
  }

  void _shiftWeek(int direction) {
    setState(() {
      _from = _addDays(_from, 7 * direction);
      _to = _addDays(_from, 6);
    });
    unawaited(_load());
  }

  void _previousWeek() => _shiftWeek(-1);

  void _nextWeek() => _shiftWeek(1);

  /// Back to the week that contains today. Also re-fetches when it is already
  /// on screen, so the action doubles as a refresh rather than doing nothing.
  void _goToToday() {
    setState(() {
      _from = _weekStart(DateTime.now());
      _to = _addDays(_from, 6);
    });
    unawaited(_load());
  }

  // ── Filters ────────────────────────────────────────────────────────────────

  Future<void> _pickUser(Rect anchor) async {
    final choice = await _showFilterPicker(
      anchor: anchor,
      titleKey: 'timesheet.member',
      allLabelKey: 'timesheet.allUsers',
      searchHintKey: 'timesheet.searchUsers',
      selectedId: _userFilter,
      load: _searchUsers,
    );
    if (choice == null || !mounted) return;
    setState(() {
      _userFilter = choice.id;
      _userFilterLabel = choice.label;
    });
    unawaited(_load());
  }

  Future<void> _pickProject(Rect anchor) async {
    final choice = await _showFilterPicker(
      anchor: anchor,
      titleKey: 'timesheet.project',
      allLabelKey: 'timesheet.allProjects',
      searchHintKey: 'timesheet.searchProjects',
      selectedId: _projectFilter,
      load: _searchProjects,
    );
    if (choice == null || !mounted) return;
    setState(() {
      _projectFilter = choice.id;
      _projectFilterLabel = choice.label;
    });
    unawaited(_load());
  }

  /// Server-side type-ahead over the directory — the same paged endpoint the
  /// assignee pickers use, so a large org never loads every account to filter
  /// one week.
  Future<_FilterPage> _searchUsers(String query, int page) async {
    final result = await context.read<UserRepository>().searchUsers(
      query,
      page: page,
      size: _filterPageSize,
    );
    return (
      items: [
        for (final user in result.items)
          _FilterOption(
            id: user.id,
            label: user.displayName.isEmpty ? user.username : user.displayName,
            secondary: user.username,
            avatarUrl: user.avatarUrl,
            pronouns: user.pronouns,
            person: true,
          ),
      ],
      total: result.total,
    );
  }

  /// The project filter reads the server a page at a time, like the user one.
  /// Holding the whole catalogue to filter it here would mean downloading every
  /// project an admin can see — with its workflow states, its labels and its
  /// colours — to fill one dropdown.
  Future<_FilterPage> _searchProjects(String query, int page) async {
    final result = await context.read<ProjectRepository>().searchProjects(
      query: query,
      page: page,
      size: _filterPageSize,
    );
    return (
      items: [
        for (final project in result.projects)
          _FilterOption(
            id: project.id,
            label: project.name,
            secondary: project.key,
          ),
      ],
      total: result.total,
    );
  }

  /// Opens the shared filter panel: an anchored glass dropdown beside the field
  /// on wide screens, a glass sheet on phones where an anchored panel would be
  /// buried under the keyboard. Resolves to null when dismissed.
  Future<_FilterChoice?> _showFilterPicker({
    required Rect anchor,
    required String titleKey,
    required String allLabelKey,
    required String searchHintKey,
    required String? selectedId,
    required Future<_FilterPage> Function(String query, int page) load,
  }) {
    Widget panel(bool sheet) => _FilterPanel(
      titleKey: sheet ? titleKey : null,
      allLabelKey: allLabelKey,
      searchHintKey: searchHintKey,
      selectedId: selectedId,
      load: load,
    );

    if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
      return showGlassAnchoredPopover<_FilterChoice>(
        context,
        anchorRect: anchor,
        width: _filterWidth,
        minHeight: 180,
        maxHeight: 420,
        builder: (_) => panel(false),
      );
    }
    return showGlassBottomSheet<_FilterChoice>(
      context,
      builder: (_) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: panel(true),
      ),
    );
  }

  // ── Labels ─────────────────────────────────────────────────────────────────

  /// Whose row this is. An id the directory answered about but does not carry
  /// belongs to an erased account — work items keep the id as a pseudonym — and
  /// says so, rather than showing the raw id to everyone who opens the week.
  String _userLabel(String id) {
    final user = _users[id];
    if (user != null) {
      return user.displayName.isEmpty ? user.username : user.displayName;
    }
    return context.t(_directoryAnswered ? 'time.deletedUser' : 'time.fmt.none');
  }

  /// Time that belongs to no project — an entry whose issue was deleted, say —
  /// is its own line and is named as such, never left blank.
  String _projectLabel(String? id) {
    if (id == null) return context.t('timesheet.unassigned');
    return _projectsById[id]?.key ?? context.t('time.fmt.none');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final admin = _isAdmin;
    // [PageChrome] is here for `fullWidth` — a seven-day grid wants the whole
    // page, not the reading column. Its title and actions are not: the shell
    // draws those in the sub-page bar, and a destination in the nav has no
    // sub-page bar, so on a wide window they would simply never appear. A
    // top-level page wears its own head, the way Reports, Gantt and Board do.
    return PageChrome(
      fullWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              18 + context.topGutter,
              context.pageGutter,
              12,
            ),
            child: PageHead(
              title: context.t('timesheet.title'),
              actions: [
                // Amber only when there is somewhere to come back from; on
                // this week it is still there, and still re-reads it, but it
                // does not ask for attention it has not earned.
                if (_isCurrentWeek)
                  GhostButton(
                    icon: LucideIcons.calendarCheck,
                    label: context.t('timesheet.today'),
                    onPressed: _goToToday,
                    collapseToIcon: true,
                  )
                else
                  PrimaryButton(
                    icon: LucideIcons.calendarCheck,
                    label: context.t('timesheet.today'),
                    onPressed: _goToToday,
                    collapseToIcon: true,
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              0,
              context.pageGutter,
              12,
            ),
            child: _toolbar(admin),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _toolbar(bool admin) {
    final localizations = MaterialLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(_filterWidth, constraints.maxWidth);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _weekNav(localizations),
            if (admin) ...[
              SizedBox(
                width: width,
                child: _FilterField(
                  icon: LucideIcons.userRound,
                  label: context.t('timesheet.member'),
                  value: _userFilterLabel ?? context.t('timesheet.allUsers'),
                  active: _userFilter != null,
                  onTap: _pickUser,
                ),
              ),
              SizedBox(
                width: width,
                child: _FilterField(
                  icon: LucideIcons.folderKanban,
                  label: context.t('timesheet.project'),
                  value:
                      _projectFilterLabel ?? context.t('timesheet.allProjects'),
                  active: _projectFilter != null,
                  onTap: _pickProject,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _weekNav(MaterialLocalizations localizations) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _previousWeek,
          tooltip: context.t('timesheet.previousWeek'),
          icon: Icon(backChevron(context)),
        ),
        // The numeric form, not the spelled-out one: two long dates and two
        // buttons do not fit a phone, and the weekday a range starts on is not
        // what anybody reads here. Flexible on top of that, so no language with
        // longer dates can push the row past its edge.
        Flexible(
          child: Text(
            '${localizations.formatCompactDate(_from)} – '
            '${localizations.formatCompactDate(_to)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: _nextWeek,
          tooltip: context.t('timesheet.nextWeek'),
          icon: Icon(forwardChevron(context)),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading && _rows.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(40), child: HiveLoader()),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t(_error!),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => unawaited(_load()),
                child: Text(context.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      child: _rows.isEmpty
          // Capped rather than stretched: a full-width empty card on a desk
          // monitor is a lot of nothing, and the sentence has to be findable.
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: HiveEmptyState(
                  title: context.t('timesheet.title'),
                  message: context.t('timesheet.empty'),
                ),
              ),
            )
          : _table(),
    );
  }

  /// The grid. It scrolls sideways inside its own card — a week of columns plus
  /// two label columns does not fit a phone — while the page itself never does.
  Widget _table() {
    final localizations = MaterialLocalizations.of(context);
    final days = [for (var i = 0; i < 7; i++) _addDays(_from, i)];
    return SoftCard(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: AppColors.textPrimary,
          ),
          columns: [
            DataColumn(label: Text(context.t('timesheet.member'))),
            DataColumn(label: Text(context.t('timesheet.project'))),
            for (final day in days)
              DataColumn(label: Text(localizations.formatShortDate(day))),
            DataColumn(label: Text(context.t('timesheet.total'))),
          ],
          rows: [
            for (final row in _rows)
              DataRow(
                cells: [
                  DataCell(_memberCell(row)),
                  DataCell(Text(_projectLabel(row.projectId))),
                  for (final day in days) DataCell(Text(_cell(row, day))),
                  DataCell(
                    Text(
                      fmtDuration(context, row.totalMinutes),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _memberCell(TimesheetRow row) {
    final user = _users[row.userId];
    final name = _userLabel(row.userId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (user == null)
          // The same treatment the issue timeline gives an id nobody answers
          // to, so a reader who sees both in one session reads them the same.
          HiveAvatar(
            name: name,
            size: 24,
            background: AppColors.inkFaint,
            glyph: const Icon(LucideIcons.userX, size: 12, color: Colors.white),
          )
        else
          AppAvatar(
            name: name,
            imageUrl: user.avatarUrl,
            pronouns: user.pronouns,
            radius: 12,
          ),
        const SizedBox(width: 8),
        Text(name),
      ],
    );
  }

  String _cell(TimesheetRow row, DateTime day) {
    // A lookup, not a scan: `parseDate` builds the keys at local midnight and
    // so does `_addDays`, so the day is an exact hit. The scan this replaces
    // cost seven comparisons per cell on every rebuild.
    final minutes = row.minutesPerDay[day] ?? 0;
    return minutes == 0
        ? context.t('time.fmt.none')
        : fmtDuration(context, minutes);
  }
}

// ── Filter plumbing ──────────────────────────────────────────────────────────

/// One pickable row in a filter panel.
@immutable
class _FilterOption {
  const _FilterOption({
    required this.id,
    required this.label,
    this.secondary,
    this.avatarUrl,
    this.pronouns,
    this.person = false,
  });

  final String id;
  final String label;

  /// The dimmer second half of the row: a username, a project key.
  final String? secondary;
  final String? avatarUrl;
  final String? pronouns;

  /// Whether the row is a person, and therefore gets an avatar — a project
  /// carries an avatarless name and would only gain a fake monogram.
  final bool person;
}

typedef _FilterPage = PageResult<_FilterOption>;

/// How many options one page of a filter list holds.
const int _filterPageSize = 25;

/// What a filter panel resolves to. [id] null means "everything" — which is a
/// real choice, and therefore not the same as dismissing the panel (null).
@immutable
class _FilterChoice {
  const _FilterChoice(this.id, this.label);

  final String? id;
  final String? label;
}

/// Labelled field that opens its picker anchored to itself, reporting its own
/// global rect so the dropdown attaches to the field rather than the page.
class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Whether a filter is actually set — the field warms to the accent so an
  /// unnoticed narrowing can't be mistaken for an empty week.
  final bool active;
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          final rect = box != null && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : Rect.zero;
          onTap(rect);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.hairline,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: active
                    ? AppColors.accentStrong
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronsUpDown,
                size: 15,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Body of a timesheet filter: a search field, an "everything" row and the
/// pages the loader hands back, more of them as the reader scrolls.
///
/// One panel for both filters. The user list is a server type-ahead and the
/// project list is the visible catalogue narrowed in memory, but the reader
/// sees the same control either way — which is the point of passing the loader
/// in rather than branching on what is being filtered.
class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.titleKey,
    required this.allLabelKey,
    required this.searchHintKey,
    required this.selectedId,
    required this.load,
  });

  /// Sheet header on phones; null in the anchored popover, where the field the
  /// reader just tapped is still visible behind it.
  final String? titleKey;
  final String allLabelKey;
  final String searchHintKey;
  final String? selectedId;
  final Future<_FilterPage> Function(String query, int page) load;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  static const _debounce = Duration(milliseconds: 180);

  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounceTimer;

  /// The list itself is the house's paged cubit — the same one the "all
  /// entries" sheet uses. It owns the accumulated items, the page counter, the
  /// two loading flags, the de-duplication across pages and the token that
  /// drops a slow answer overtaken by a newer one; what stays here is the
  /// search box in front of it.
  late final PagedCubit<_FilterOption> _cubit = PagedCubit<_FilterOption>(
    (page, size) => widget.load(_query.trim(), page),
    pageSize: _filterPageSize,
    keyOf: (option) => option.id,
  );

  String _query = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _focus.addListener(_onFocusChanged);
    unawaited(_cubit.load());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounceTimer?.cancel();
    // A new term starts the list over: `load` resets to page 0, and the cubit's
    // own token discards whatever the previous term was still fetching.
    _debounceTimer = Timer(_debounce, () => unawaited(_cubit.load()));
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100) {
      unawaited(_cubit.loadMore());
    }
  }

  void _pick(_FilterChoice choice) => Navigator.of(context).pop(choice);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.titleKey != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: Text(
              context.t(widget.titleKey!),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        _searchField(),
        Flexible(child: _list()),
      ],
    );
  }

  /// Inset glass pill rather than a themed [TextField]: the app's input theme
  /// fills opaquely, which on a glass panel reads as a separate bar stuck on
  /// top instead of part of the surface. Same treatment as the project picker.
  Widget _searchField() {
    final focused = _focus.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: focused ? 0.4 : 0.26),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: focused ? AppColors.accent : AppColors.hairline2,
            width: focused ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.search,
              size: 16,
              color: focused ? AppColors.accentStrong : AppColors.textSecondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focus,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13.5),
                cursorColor: AppColors.accentStrong,
                // Every border state is cleared by hand: the app's input theme
                // supplies enabled/focused borders and those survive
                // `isCollapsed`, drawing a second box inside the pill.
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  hintText: context.t(widget.searchHintKey),
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  _searchCtrl.clear();
                  _onQueryChanged('');
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    return BlocBuilder<PagedCubit<_FilterOption>, PagedState<_FilterOption>>(
      bloc: _cubit,
      builder: (context, state) {
        final options = state.items;
        if (state.isLoading && options.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(child: HiveLoader(size: 18)),
          );
        }
        if (state.errorKey != null && options.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Text(
              context.t(state.errorKey!),
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          );
        }

        // "Everything" only belongs at the top of an unfiltered list: while a
        // query is running it is not one of the matches.
        final hasAllRow = _query.trim().isEmpty;
        final leading = hasAllRow ? 1 : 0;
        final empty =
            options.isEmpty && !state.isLoading && !state.isLoadingMore;
        final trailing = empty || state.isLoadingMore ? 1 : 0;

        // Built on demand, not assembled into a list first: a search rebuilds
        // this on every debounced keystroke, and materialising every loaded
        // option each time is the cost the builder exists to avoid.
        return ListView.builder(
          controller: _scroll,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: leading + options.length + trailing,
          itemBuilder: (_, index) {
            if (hasAllRow && index == 0) {
              return _FilterRow(
                label: context.t(widget.allLabelKey),
                selected: widget.selectedId == null,
                onTap: () => _pick(const _FilterChoice(null, null)),
              );
            }
            final at = index - leading;
            if (at < options.length) {
              final option = options[at];
              return _FilterRow(
                label: option.label,
                secondary: option.secondary,
                avatar: option.person,
                avatarUrl: option.avatarUrl,
                pronouns: option.pronouns,
                selected: widget.selectedId == option.id,
                onTap: () => _pick(_FilterChoice(option.id, option.label)),
              );
            }
            if (state.isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: HiveLoader(size: 15)),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Text(
                context.t('common.noMatches'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.secondary,
    this.avatar = false,
    this.avatarUrl,
    this.pronouns,
  });

  final String label;
  final String? secondary;
  final bool avatar;
  final String? avatarUrl;
  final String? pronouns;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 17,
              color: selected
                  ? AppColors.accentStrong
                  : AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            if (avatar) ...[
              AppAvatar(
                name: label,
                imageUrl: avatarUrl,
                pronouns: pronouns,
                radius: 11,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (secondary != null) ...[
              const SizedBox(width: 8),
              Text(
                secondary!,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
