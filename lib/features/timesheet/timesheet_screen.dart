import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/time_approval_models.dart';
import '../../core/models/time_policy_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/repositories/timesheet_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/util/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../shell/page_chrome.dart';
import '../time/approval_actions.dart';
import '../time/lock_notice.dart';
import '../time/time_views.dart';
import '../time/time_entry_sheet.dart';
import '../time/timesheet_cell_sheet.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassDateRangePicker;

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
  const TimesheetScreen({super.key, this.moduleView = false});

  /// Whether this is the extended module's `/time/timesheet` rather than the
  /// base `/timesheet`.
  ///
  /// One screen for both, because they are the same grid: a week of days across
  /// people and projects, the same labels resolved the same way, the same
  /// filters. What the flag changes is where the rows come from — the module's
  /// paged route rather than the array-shaped one the published app reads — and
  /// that a cell of your own can be typed into. Two files would be one grid
  /// maintained twice.
  final bool moduleView;

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  /// Width of a filter field and of the popover it opens, so the dropdown lines
  /// up with the field instead of hanging off it.
  static const double _filterWidth = 232;

  /// Rows per request on the module's paged route.
  ///
  /// A hundred is the server's ceiling and far more than a week of one person
  /// holds. An administrator's instance-wide week can run past it, and that is
  /// what [_shown]/[_total] are for: a working-time record that quietly omits
  /// every row past the hundredth is a wrong answer wearing the shape of a
  /// right one.
  static const int _pageSize = 100;

  late DateTime _from;
  late DateTime _to;

  /// The period on screen when this instance submits timesheets, or null.
  ///
  /// Handed out by the server — the app derives **no** rhythm of its own. Which
  /// days "March 2026" or "CW 12" covers is arithmetic that lives once, on the
  /// server, because two implementations would disagree on exactly one day a year
  /// and nobody would notice until a payroll period was short.
  ApprovalPeriod? _period;

  /// The day whose period is shown. The arrows move this, not the window: a
  /// period's neighbour is found by stepping one day past its edge and asking
  /// again, because a month is four different lengths.
  DateTime? _anchor;

  /// Under a FREE rhythm there is no grid, so the span is picked rather than
  /// stepped through. Null until somebody picks one.
  DateTimeRange? _freeSpan;

  List<TimesheetRow> _rows = const [];

  /// How many rows the whole matrix has, against how many are on screen. Equal
  /// on every ordinary week; apart only when the server's page ran out.
  int _total = 0;

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

  /// Set on the first [didChangeDependencies], not in [initState]: the week's
  /// first day comes from [MaterialLocalizations], which is not reachable
  /// before the element is in the tree.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final today = DateTime.now();
    _from = weekStartFor(context, today);
    _to = addDays(_from, 6);
    _anchor = DateTime(today.year, today.month, today.day);
    // The rules decide whether the window is a week or a period, so they have to
    // be in before the first fetch. A cubit that nobody calls is a feature that
    // works in the test and never appears in the app.
    unawaited(
      context.read<TimePolicyCubit>().ensureLoaded().then((_) {
        if (mounted) unawaited(_load());
      }),
    );
  }

  bool get _isCurrentWeek => weekStartFor(context, DateTime.now()) == _from;

  bool get _isAdmin => context.watch<AuthBloc>().state.user?.isAdmin ?? false;

  /// The operator's rules. Watched, so switching approvals on takes effect
  /// without a reopen.
  TimePolicySnapshot get _policy => context.watch<TimePolicyCubit>().state;

  /// Whether the window is a submission period rather than a week.
  ///
  /// Only in the module, and only while approvals are on. The plain
  /// `/timesheet` is the surface the published app reads and stays a week
  /// whatever this instance has configured.
  bool _usesPeriods(TimePolicySnapshot policy) =>
      widget.moduleView && policy.approvalsEnabled;

  /// The period the grid is showing, clamped to what the grid route accepts.
  ///
  /// The server caps a timesheet window at a month, and for good reason: every
  /// row carries a minutes-per-day map. Every common rhythm fits — a week, two
  /// weeks, half a month, a month. A quarter does not, so the grid shows its
  /// first days and says so, while the status chips above it carry the figures
  /// for the **whole** period, which is what submitting is about.
  static const int _maxGridDays = 31;

  bool get _periodExceedsGrid {
    final period = _period;
    if (period == null) return false;
    return period.end.difference(period.start).inDays + 1 > _maxGridDays;
  }

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
      if (_usesPeriods(context.read<TimePolicyCubit>().state)) {
        await _resolvePeriod();
        if (!mounted || seq != _loadSeq) return;
      }
      // The module's route is a page of rows; the base one is every row at
      // once. Same scope either way — the server refuses another person's rows
      // to a non-admin on both — so the difference is how many arrive, and a
      // week of one person's projects is never more than the first page.
      final List<TimesheetRow> rows;
      final int total;
      if (widget.moduleView) {
        final page = await context.read<TimeRepository>().timesheet(
          from: _from,
          to: _to,
          userId: _userFilter,
          projectId: _projectFilter,
          size: _pageSize,
        );
        rows = page.items;
        total = page.total;
      } else {
        rows = await context.read<TimesheetRepository>().timesheet(
          _from,
          _to,
          userId: _userFilter,
          projectId: _projectFilter,
        );
        // The array-shaped route answers with every row it has, so what arrived
        // is the whole of it by definition.
        total = rows.length;
      }
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
        _total = total;
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

  /// Asks the server which period the anchor day belongs to, and sets the window
  /// from it.
  ///
  /// One request, and the app does none of the arithmetic: the answer carries the
  /// boundaries, the rhythm's name and each project's standing and minutes for
  /// the whole period. A failure here is not fatal — the window falls back to the
  /// week it already had, so an instance whose approvals route is unreachable
  /// still shows a timesheet.
  Future<void> _resolvePeriod() async {
    final policy = context.read<TimePolicyCubit>().state;
    final span = policy.approvalRhythm.hasGrid
        ? null
        : _freeSpan; // FREE: the person picks, and until they do there is none.
    final anchor = _anchor ?? DateTime.now();
    final from = span?.start ?? anchor;
    final to = span?.end ?? anchor;
    try {
      final periods = await context.read<TimeRepository>().approvalPeriods(
        from: DateTime(from.year, from.month, from.day),
        to: DateTime(to.year, to.month, to.day),
        projectId: _projectFilter,
      );
      if (!mounted) return;
      // Under a FREE rhythm the server answers with the spans that *exist* —
      // what this person has already handed in — so an unsubmitted pick has no
      // period of its own and the picked span is the window.
      final period = periods.isEmpty
          ? (span == null
                ? null
                : ApprovalPeriod(
                    start: span.start,
                    end: span.end,
                    type: 'FREE',
                  ))
          : periods.firstWhere(
              (candidate) => candidate.contains(anchor),
              orElse: () => periods.first,
            );
      _period = period;
      if (period != null) {
        _from = DateTime(
          period.start.year,
          period.start.month,
          period.start.day,
        );
        final days = period.end.difference(period.start).inDays + 1;
        _to = days > _maxGridDays
            ? addDays(_from, _maxGridDays - 1)
            : DateTime(period.end.year, period.end.month, period.end.day);
      }
    } on ApiFailure {
      // The grid is still worth drawing. Leaving the period null is what makes
      // the switcher and the submit action disappear rather than lie.
      if (mounted) _period = null;
    }
  }

  void _shiftWeek(int direction) {
    setState(() {
      _from = addDays(_from, 7 * direction);
      _to = addDays(_from, 6);
    });
    unawaited(_load());
  }

  /// One period back or forward.
  ///
  /// Moves the *anchor* one day past the current period's edge and re-asks, which
  /// is how you find a neighbour when a period's length is not fixed: a month is
  /// four lengths, a semi-monthly period four more.
  void _shiftPeriod(int direction) {
    final period = _period;
    if (period == null) return;
    setState(() {
      _anchor = direction < 0
          ? addDays(period.start, -1)
          : addDays(period.end, 1);
    });
    unawaited(_load());
  }

  void _previousWeek() => _shiftWeek(-1);

  void _nextWeek() => _shiftWeek(1);

  /// FREE rhythm: pick the span to show and, if its hours are complete, hand in.
  Future<void> _pickFreeSpan() async {
    final picked = await showGlassDateRangePicker(
      context,
      title: context.t('time.approval.pickSpan'),
      initialRange: _freeSpan ?? DateTimeRange(start: _from, end: _to),
      // A year back is what the server accepts for an entry, and today is the
      // far end: a span that reached into the future would be a period nobody
      // could have worked yet.
      firstDate: DateTime.now().subtract(const Duration(days: 366)),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _freeSpan = picked;
      _anchor = picked.start;
    });
    unawaited(_load());
  }

  void _openModuleMenu(Rect? anchor) => unawaited(
    showTimeViewMenu<Never>(
      context,
      anchor: anchor,
      current: TimeView.timesheet,
    ),
  );

  /// A new entry, on the week the sheet is showing.
  ///
  /// Nine in the morning on today when the week contains it, and on the week's
  /// first day otherwise — the same rule the calendar's button follows, so the
  /// module's one "new entry" means one thing wherever it is pressed.
  Future<void> _newEntry() async {
    final today = DateTime.now();
    final at = DateTime(today.year, today.month, today.day);
    final day = !at.isBefore(_from) && !at.isAfter(_to) ? at : _from;
    final start = DateTime(day.year, day.month, day.day, 9);
    final saved = await showTimeEntrySheet(
      context,
      span: (start: start, end: start.add(const Duration(hours: 1))),
    );
    if (saved == null || !mounted) return;
    unawaited(_load());
  }

  /// Back to the week that contains today. Also re-fetches when it is already
  /// on screen, so the action doubles as a refresh rather than doing nothing.
  void _goToToday() {
    final today = DateTime.now();
    setState(() {
      _anchor = DateTime(today.year, today.month, today.day);
      _freeSpan = null;
      _from = weekStartFor(context, today);
      _to = addDays(_from, 6);
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

  /// Whose row this is.
  ///
  /// Three different nobodies, and they must not be confused. No id at all is
  /// time that never belonged to a person — the pre-2.0 smart-commit
  /// remainders are the only entries written without an owner, and calling
  /// those a deleted user would assert that somebody was erased. An id the
  /// directory answered about but does not carry *is* an erased account, since
  /// entries keep the id as a pseudonym. And an id nobody has been asked about
  /// yet is neither, so it stays blank until the answer arrives.
  String _userLabel(String id) {
    if (id.isEmpty) return context.t('time.legacySource');
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
    final compact = context.isCompact;
    // [PageChrome] carries two things the shell owns. `fullWidth`, because a
    // seven-day grid wants the whole page rather than the reading column. And
    // on a phone the controls themselves, docked into the glass app bar the way
    // the audit log docks its filters: laid out down the page they cost a third
    // of the screen before a single row of the week is visible, and the bar is
    // already blurring that band.
    //
    // Its title and actions are deliberately not used. The shell draws those in
    // the sub-page bar, and a destination in the nav has no sub-page bar, so on
    // a wide window they would never appear at all — which is why a top-level
    // page wears its own head, the way Reports, Gantt and Board do.
    return PageChrome(
      fullWidth: true,
      // The module's three views live under the app bar's title on a phone —
      // the docked row below is the one line this page is allowed, and it is
      // spent on the week it is showing. Off the module (the plain
      // `/timesheet`) there is nothing to switch between.
      onTitleTap: compact && widget.moduleView ? _openModuleMenu : null,
      // Left, like the module's other two pages. The week this sheet is showing
      // is what the docked row below says; the title above it is the name of a
      // place, and it belongs where the eye starts rather than wherever the
      // wider of the two flanking slots leaves it.
      titleLeading: true,
      // Compact only: the module's pages are nav destinations, so a wide
      // window builds no sub-page bar and would drop these on the floor. A
      // wide window reaches both ways of adding time without this button — a
      // cell is opened by tapping it, and the timer lives on the bar above —
      // so only the phone needs one, and it asks which.
      actions: compact && widget.moduleView
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('time.add.title'),
                primary: true,
                // The module's one "+", shared by all three of its pages: an
                // entry in the week on screen, or the timer. See
                // [showTimeAddMenu].
                onTap: (anchor) => unawaited(
                  showTimeAddMenu(
                    context,
                    anchor: anchor,
                    onNewEntry: _newEntry,
                    onTimerStopped: _load,
                  ),
                ),
              ),
            ]
          : const [],
      bottom: compact ? _dockedBar(admin) : null,
      bottomHeight: compact ? kGlassDockRow : 0,
      child: compact
          ? _body()
          : Column(
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
                    title: context.t(
                      widget.moduleView ? 'nav.time' : 'timesheet.title',
                    ),
                    actions: [
                      if (widget.moduleView) ...[
                        const TimeViewSwitcher(current: TimeView.timesheet),
                        const SizedBox(width: 8),
                      ],
                      _todayButton(),
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

  /// Back to the current week — and a re-read while it is at it, so it doubles
  /// as refresh. Amber only when there is somewhere to come back from.
  Widget _todayButton() => _isCurrentWeek
      ? GhostButton(
          icon: LucideIcons.calendarCheck,
          label: context.t('timesheet.today'),
          onPressed: _goToToday,
          collapseToIcon: true,
        )
      : PrimaryButton(
          icon: LucideIcons.calendarCheck,
          label: context.t('timesheet.today'),
          onPressed: _goToToday,
          collapseToIcon: true,
        );

  /// The phone's controls, in one row inside the app bar's blur: the week and
  /// its arrows on a glass pill, then a pill each for what would otherwise be
  /// two full-width fields. Real glass, in the band the bar is already blurring
  /// — the same shape the audit log's docked filters use, so a reader meets one
  /// toolbar idiom in the app and not two. A set filter wears the amber wash,
  /// so a narrowing nobody meant cannot be mistaken for an empty week.
  Widget _dockedBar(bool admin) {
    final localizations = MaterialLocalizations.of(context);
    // Centred in the band's height, and the `Align` is load-bearing: the bar
    // hands the reserved height down as a *tight* constraint, which a
    // `SizedBox` cannot come in under. Without it the pills grew to the full
    // row and read as a taller, softer control than the identical pills on the
    // calendar and the list. [kGlassDockRow] is that reserved height, shared,
    // so no page can pick its own and put the same row at a different height.
    // Across the band it starts at the leading edge, under a title that does
    // the same.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: kGlassControlHeight,
        child: ListView(
          scrollDirection: Axis.horizontal,
          // The gutter is the scroller's own padding, so the last pill can come
          // fully into view at the display edge instead of being clipped by an
          // inset around the whole row.
          padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
          children: [
            // One pill, two meanings, and the label says which: a period when
            // this instance submits them, a week otherwise. A FREE rhythm has no
            // grid to step through, so the pill opens the span picker instead of
            // carrying arrows that would imply one.
            if (_period != null && !_policy.approvalRhythm.hasGrid)
              GlassPill(
                height: kGlassControlHeight,
                onTap: _pickFreeSpan,
                child: _PillLabel(
                  icon: LucideIcons.calendarRange,
                  label: _windowLabel(localizations),
                  active: false,
                ),
              )
            else
              GlassStepperPill(
                label: Text(
                  _windowLabel(localizations),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backTooltip: context.t(
                  _period != null
                      ? 'time.approval.previousPeriod'
                      : 'timesheet.previousWeek',
                ),
                forwardTooltip: context.t(
                  _period != null
                      ? 'time.approval.nextPeriod'
                      : 'timesheet.nextWeek',
                ),
                onBack: _period != null
                    ? () => _shiftPeriod(-1)
                    : _previousWeek,
                onForward: _period != null ? () => _shiftPeriod(1) : _nextWeek,
              ),
            const SizedBox(width: 8),
            GlassPill(
              active: !_isCurrentWeek,
              height: kGlassControlHeight,
              onTap: _goToToday,
              child: _PillLabel(
                icon: LucideIcons.calendarCheck,
                label: context.t('timesheet.today'),
                active: !_isCurrentWeek,
              ),
            ),
            if (admin) ...[
              const SizedBox(width: 8),
              _DockedFilterPill(
                icon: LucideIcons.userRound,
                label: _userFilterLabel ?? context.t('timesheet.allUsers'),
                active: _userFilter != null,
                onTap: _pickUser,
              ),
              const SizedBox(width: 8),
              _DockedFilterPill(
                icon: LucideIcons.folderKanban,
                label:
                    _projectFilterLabel ?? context.t('timesheet.allProjects'),
                active: _projectFilter != null,
                onTap: _pickProject,
              ),
            ],
          ],
        ),
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

  /// What the window is called.
  ///
  /// The server's period, when there is one: "March 2026", "CW 12", "1 – 15
  /// March". Never derived from a type name here — the dates are the server's and
  /// so is the rhythm they came from; the app only formats them for the reader.
  String _windowLabel(MaterialLocalizations localizations) {
    final period = _period;
    if (period != null) {
      return formatPeriod(context, period.start, period.end);
    }
    return '${localizations.formatCompactDate(_from)} – '
        '${localizations.formatCompactDate(_to)}';
  }

  /// The rhythm's own name, for the line under the switcher.
  String? _rhythmLabel() {
    final period = _period;
    if (period == null) return null;
    return context.t('time.approval.rhythm.${period.type}');
  }

  Widget _weekNav(MaterialLocalizations localizations) {
    final period = _period;
    if (period != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_policy.approvalRhythm.hasGrid) ...[
            IconButton(
              onPressed: () => _shiftPeriod(-1),
              tooltip: context.t('time.approval.previousPeriod'),
              icon: Icon(backChevron(context)),
            ),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _windowLabel(localizations),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _rhythmLabel() ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _shiftPeriod(1),
              tooltip: context.t('time.approval.nextPeriod'),
              icon: Icon(forwardChevron(context)),
            ),
          ] else
            // FREE: there is no grid to step through, so the span is picked. The
            // arrows would be a lie about a rhythm that does not exist.
            GhostButton(
              icon: LucideIcons.calendarRange,
              label: _windowLabel(localizations),
              onPressed: _pickFreeSpan,
            ),
        ],
      );
    }
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
        // On a phone the grid scrolls *under* the glass app bar, which now
        // carries the controls, so it starts below the whole band — a gutter
        // clear of it, the same distance every other scrolling page keeps
        // (see `pagePadding`). On wide the head and the toolbar sit in the
        // page and have already spent that room.
        context.isCompact ? context.topGutter + context.pageGutter : 0,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Above the grid whether or not there are rows: "this period is open
          // and holds nothing" is an answer, and a person looking for the submit
          // action must not have to book an hour to find it.
          if (_period != null) ...[
            _periodBand(_period!),
            const SizedBox(height: 10),
          ],
          if (_rows.isEmpty)
            // Capped rather than stretched: a full-width empty card on a desk
            // monitor is a lot of nothing, and the sentence has to be findable.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: HiveEmptyState(
                  title: context.t('timesheet.title'),
                  // Two sentences, because the window is two different things: a
                  // week on the plain route, a submission period in the module
                  // once approvals are on. "In this week" over a month is a
                  // sentence that contradicts the switcher right above it — and
                  // the rhythm is the operator's decision, so no copy may assume
                  // one.
                  message: context.t(
                    _period == null ? 'timesheet.empty' : 'timesheet.emptyPeriod',
                  ),
                  card: false,
                ),
              ),
            )
          else ...[
            if (_total > _rows.length) ...[
              _TruncatedRows(shown: _rows.length, total: _total),
              const SizedBox(height: 10),
            ],
            _table(),
          ],
        ],
      ),
    );
  }

  /// Where this period stands, and what can be done about it.
  ///
  /// One card above the grid: a chip per project, then the action. The chips are
  /// per project because that is who approves — a lead signs off the time booked
  /// against their project and has no business seeing the rest of somebody's
  /// month — and a single "period status" would have to pick one of them to show.
  Widget _periodBand(ApprovalPeriod period) {
    final submittable = period.submittable;
    final withdrawable = period.withdrawable;
    final mine = _userFilter == null || _userFilter == _editableUserId;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.fileCheck2,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatPeriod(context, period.start, period.end),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                fmtDuration(context, period.minutes),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          if (_periodExceedsGrid) ...[
            const SizedBox(height: 8),
            Text(
              context.t('time.approval.gridClamped'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (period.projects.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              context.t('time.approval.nothingToSubmit'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final project in period.projects)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.projectKey ??
                            project.projectName ??
                            context.t('time.fmt.none'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ApprovalStatusChip(
                        status: project.status,
                        note: project.note,
                      ),
                    ],
                  ),
              ],
            ),
          ],
          // Only about one's own time. An administrator reading somebody else's
          // rows is reading a report; handing in on their behalf would be signing
          // a statement that is theirs to make.
          if (mine && (submittable.isNotEmpty || withdrawable.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (submittable.isNotEmpty)
                  PrimaryButton(
                    icon: LucideIcons.send,
                    label: context.t('time.approval.submitAction'),
                    onPressed: () => unawaited(_submitPeriod(period)),
                  ),
                for (final pending in withdrawable)
                  GhostButton(
                    icon: LucideIcons.undo2,
                    label: context.t(
                      'time.approval.withdrawFor',
                      variables: {
                        'project':
                            pending.projectKey ??
                            pending.projectName ??
                            context.t('time.fmt.none'),
                      },
                    ),
                    onPressed: () => unawaited(_withdraw(pending.approvalId!)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitPeriod(ApprovalPeriod period) async {
    final submitted = await ApprovalActions.submit(
      context,
      periodStart: period.start,
      periodEnd: period.end,
      projectIds: [for (final project in period.submittable) project.projectId],
    );
    if (submitted && mounted) unawaited(_load());
  }

  Future<void> _withdraw(String approvalId) async {
    final withdrawn = await ApprovalActions.withdraw(context, approvalId);
    if (withdrawn && mounted) unawaited(_load());
  }

  /// The grid. It scrolls sideways inside its own card — a week of columns plus
  /// two label columns does not fit a phone — while the page itself never does.
  Widget _table() {
    final localizations = MaterialLocalizations.of(context);
    final days = [for (var i = 0; i < 7; i++) addDays(_from, i)];
    final editable = _editableUserId;
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
                  for (final day in days) _dayCell(row, day, editable),
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

  /// One day of one row, with a lock where the day cannot be written.
  ///
  /// The lock is drawn rather than discovered: a cell that opens a form and is
  /// then refused is a worse way to learn that a period is closed, and the glyph
  /// carries the reason on its tooltip — the same vocabulary the refusal would
  /// have used, which is the whole point of there being one.
  DataCell _dayCell(TimesheetRow row, DateTime day, String? editable) {
    final own = editable != null && row.userId == editable;
    final lock = own ? _lockFor(row, day) : null;
    if (lock != null) {
      return DataCell(
        Tooltip(
          message: LockNotice.reasonOf(context, lock),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.lock, size: 11, color: AppColors.inkFaint),
              const SizedBox(width: 4),
              Text(
                _cell(row, day),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return DataCell(
      Text(_cell(row, day)),
      // Only your own hours, and only in the module. Somebody else's row is a
      // report; the server would refuse the write anyway, and a cell that opens
      // a form before being told no is a worse way to learn that.
      onTap: own ? () => _openCell(row, day) : null,
    );
  }

  /// Why this cell cannot be written, or null when it can.
  ///
  /// The lock date first, then the period — the same order the server resolves
  /// them in, and for the same reason: a day an administrator has archived stays
  /// archived whatever a submission says about it.
  TimeLockInfo? _lockFor(TimesheetRow row, DateTime day) {
    final policy = context.read<TimePolicyCubit>().state;
    if (policy.isLocked(day)) {
      return TimeLockInfo(reason: 'lockDate', lockDate: policy.lockBefore);
    }
    final period = _period;
    if (period == null || row.projectId == null || !period.contains(day)) {
      return null;
    }
    for (final project in period.projects) {
      if (project.projectId != row.projectId) continue;
      if (project.status?.freezes ?? false) {
        return TimeLockInfo(
          reason: 'approval',
          approvalId: project.approvalId,
          periodStart: period.start,
          periodEnd: period.end,
        );
      }
    }
    return null;
  }

  Widget _memberCell(TimesheetRow row) {
    final user = _users[row.userId];
    final name = _userLabel(row.userId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (user == null)
          // The same treatment the issue timeline gives these two, so a reader
          // who meets both in one session reads them the same: a commit mark
          // for time that never had an owner, a crossed-out figure for an
          // account that had one and closed it.
          HiveAvatar(
            name: name,
            size: 24,
            background: AppColors.inkFaint,
            glyph: Icon(
              row.userId.isEmpty
                  ? LucideIcons.gitCommitHorizontal
                  : LucideIcons.userX,
              size: 12,
              color: Colors.white,
            ),
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

  /// Whose rows answer a tap, or null when none do.
  ///
  /// The module's page only, and only the reader's own row: an entry is filed by
  /// the person who worked, and a timesheet cell is a shortcut to filing one,
  /// not a way to file on somebody's behalf.
  ///
  /// Read once per table rather than per cell — the answer changes once a
  /// session, and a hundred rows of seven days asked it seven hundred times on
  /// every rebuild.
  String? get _editableUserId {
    if (!widget.moduleView) return null;
    return context.read<AuthBloc>().state.user?.id;
  }

  Future<void> _openCell(TimesheetRow row, DateTime day) async {
    final changed = await showTimesheetCellSheet(
      context,
      day: day,
      projectId: row.projectId,
      projectLabel: _projectLabel(row.projectId),
    );
    if (changed && mounted) unawaited(_load());
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

/// Says how much of the matrix is on screen when it is not all of it.
///
/// Only ever seen by an administrator looking at a whole instance: a person's
/// own week is a handful of rows. But a timesheet is a record somebody may have
/// to stand behind, and a view that silently stops at the hundredth row does not
/// look any different from a complete one.
class _TruncatedRows extends StatelessWidget {
  const _TruncatedRows({required this.shown, required this.total});

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.accentLine),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.info, size: 15, color: AppColors.accentStrong),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.t(
              'timesheet.truncated',
              variables: {'shown': '$shown', 'total': '$total'},
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
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

/// A pill's contents when it reads as one control: glyph, label, chevron.
class _PillLabel extends StatelessWidget {
  const _PillLabel({
    required this.icon,
    required this.label,
    required this.active,
    this.chevron = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final tint = active ? AppColors.accentStrong : AppColors.inkSoft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.accentStrong : AppColors.ink,
            ),
          ),
          if (chevron) ...[
            const SizedBox(width: 5),
            Icon(LucideIcons.chevronDown, size: 14, color: tint),
          ],
        ],
      ),
    );
  }
}

/// One docked filter: a glass pill that opens the shared filter panel anchored
/// to itself, and wears the amber wash while it is narrowing anything.
class _DockedFilterPill extends StatelessWidget {
  const _DockedFilterPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Builder(
        builder: (pillContext) => GlassPill(
          active: active,
          height: kGlassControlHeight,
          onTap: () {
            final box = pillContext.findRenderObject() as RenderBox?;
            onTap(
              box != null && box.hasSize
                  ? box.localToGlobal(Offset.zero) & box.size
                  : Rect.zero,
            );
          },
          child: _PillLabel(
            icon: icon,
            label: label,
            active: active,
            chevron: true,
          ),
        ),
      ),
    );
  }
}
