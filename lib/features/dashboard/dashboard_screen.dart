import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/hinata_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/team_models.dart' show Team;
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart' show HexMark;
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/status_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassAnchoredPopover, GlassModalHeader, GlassModalFooter;

/// Exact segment colours for the completion donut / KPIs (design "Liquid Glass").
const _cDone = Color(0xFF2E8B62);
const _cProgress = Color(0xFFD9A032);
const _cBacklog = Color(0xFF6B6890);
const _cToday = Color(0xFF4E6FD0);
const _cAmberHi = Color(0xFFF0C464);
const _cAmberLo = Color(0xFFD9A032);
const _heroInk = Color(0xF2FFFFFF); // ~95% white — hero text on navy glass

/// Card-to-card gap on the dashboard grid.
const double _gap = 18;

/// Width of the edit-mode picker fields and their anchored popovers (kept equal
/// so the dropdown lines up exactly under its field).
const double _kPickerWidth = 300;

/// Stable card keys for show/hide personalisation. `hero` is the anchor card
/// (with the board picker) and is never hideable.
abstract final class _Card {
  static const hero = 'hero';
  static const focus = 'focus';
  static const git = 'git';
  static const kpis = 'kpis';
  static const completion = 'completion';
  static const tracker = 'tracker';
  static const ranking = 'ranking';
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => const _DashboardView();
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  late final FetchCubit<DashboardData> _cubit;

  bool _editing = false;
  bool _saving = false;

  /// The pending personalisation while [_editing]; seeded from the saved prefs
  /// on entering edit mode. Scope/board changes re-fetch for a live preview;
  /// card show/hide is applied purely client-side.
  DashboardPrefs _draft = DashboardPrefs.empty;

  // Loaded once for the scope pickers (never blocks the dashboard itself).
  List<Project> _projects = const [];
  List<Team> _teams = const [];

  HinataRepository get _repo => context.read<HinataRepository>();

  /// Re-fetch when an issue is created/changed elsewhere (e.g. the global
  /// nav-rail "new issue" button, which can't reach this screen's cubit).
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<DashboardData>(
      () => _repo.dashboard(override: _editing ? _draft : null),
    )..load();
    _issueSub = IssueEvents.instance.changes.listen((_) => _cubit.load());
    _loadPickerData();
  }

  Future<void> _loadPickerData() async {
    try {
      final projects = await _repo.projects();
      final teams = await _repo.teams();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _teams = teams;
      });
    } catch (_) {
      // Pickers simply stay empty — the dashboard still works.
    }
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _cubit.close();
    super.dispose();
  }

  void _enterEdit(DashboardData data) {
    setState(() {
      _draft = data.prefs;
      _editing = true;
    });
  }

  Future<void> _finishEdit() async {
    setState(() => _saving = true);
    try {
      await _repo.saveDashboardPrefs(_draft);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      _cubit.load(); // reload with the persisted prefs (no override)
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.t('dashboard.saved'))));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.t('dashboard.saveError'))));
    }
  }

  /// A scope/board change: update the draft and re-fetch for live preview.
  void _applyScope(DashboardPrefs next) {
    setState(() => _draft = next);
    _cubit.load();
  }

  /// Card show/hide is client-side only — no server round trip.
  void _toggleCard(String key) {
    setState(() =>
        _draft = _draft.toggleCard(key, hidden: !_draft.isHidden(key)));
  }

  @override
  Widget build(BuildContext context) {
    // The ambient backdrop is painted app-wide by the shell; the dashboard just
    // renders its (glass) content on top of it.
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<DashboardData>, FetchState<DashboardData>>(
        builder: (context, state) {
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            edgeOffset: context.topGutter,
            onRefresh: () => _cubit.load(),
            child: AsyncView(
              isLoading: state.isLoading,
              hasData: state.hasData,
              errorKey: state.errorKey,
              onRetry: () => _cubit.load(),
              builder: (context) => _content(context, state.data!),
            ),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, DashboardData data) {
    final wide = !context.isCompact;
    // Effective personalisation: the live draft while editing, else the saved
    // snapshot from the server.
    final prefs = _editing ? _draft : data.prefs;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        20 + context.topGutter,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, data),
          if (_editing) ...[
            const SizedBox(height: 16),
            _EditToolbar(
              boards: data.boards,
              draft: _draft,
              projects: _projects,
              teams: _teams,
              onChanged: _applyScope,
            ),
          ],
          const SizedBox(height: 22),
          if (wide) _wideGrid(context, data, prefs) else _stack(context, data, prefs),
        ],
      ),
    );
  }

  // Greeting + the responsive "Customize" toggle, aligned to the title's row.
  Widget _header(BuildContext context, DashboardData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Greeting(sprint: data.activeBoard)),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _CustomizeButton(
            editing: _editing,
            saving: _saving,
            compact: context.isCompact,
            onPressed: () => _editing ? _finishEdit() : _enterEdit(data),
          ),
        ),
      ],
    );
  }

  // Desktop / tablet: golden-ratio two columns (1.618 : 1).
  Widget _wideGrid(BuildContext context, DashboardData data, DashboardPrefs prefs) {
    final left = <(String, Widget)>[
      (_Card.hero, _sprintCard(data.activeBoard)),
      (_Card.focus, _FocusCard(issues: data.todayTasks)),
      if (data.gitActivity.isNotEmpty) (_Card.git, _GitCard(events: data.gitActivity)),
    ];
    final right = <(String, Widget)>[
      (_Card.kpis, _Kpis(today: data.todayCount, completion: data.completion, projectIds: prefs.projectIds)),
      (_Card.completion, _CompletionCard(completion: data.completion)),
      (_Card.tracker, _TrackerCard(week: data.tracker, month: data.trackerMonth)),
      (_Card.ranking, _LeaderboardCard(ranking: data.ranking)),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1618, child: _column(left, prefs)),
        const SizedBox(width: _gap + 3),
        Expanded(flex: 1000, child: _column(right, prefs)),
      ],
    );
  }

  // Phone: one column.
  Widget _stack(BuildContext context, DashboardData data, DashboardPrefs prefs) {
    final items = <(String, Widget)>[
      (_Card.hero, _sprintCard(data.activeBoard)),
      (_Card.kpis, _Kpis(today: data.todayCount, completion: data.completion, projectIds: prefs.projectIds)),
      (_Card.focus, _FocusCard(issues: data.todayTasks)),
      (_Card.completion, _CompletionCard(completion: data.completion)),
      (_Card.tracker, _TrackerCard(week: data.tracker, month: data.trackerMonth)),
      if (data.gitActivity.isNotEmpty) (_Card.git, _GitCard(events: data.gitActivity)),
      (_Card.ranking, _LeaderboardCard(ranking: data.ranking)),
    ];
    return _column(items, prefs);
  }

  /// Builds a column from `(cardKey, widget)` pairs: in view mode hidden cards
  /// are dropped (and their gap with them); in edit mode every card renders,
  /// wrapped with a show/hide toggle (hidden ones dimmed).
  Widget _column(List<(String, Widget)> items, DashboardPrefs prefs) {
    final children = <Widget>[];
    for (final (key, widget) in items) {
      final hidden = prefs.isHidden(key);
      if (!_editing && hidden) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: _gap));
      children.add(_editableCard(key, widget, hidden));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _editableCard(String key, Widget child, bool hidden) {
    // The hero is the personalisation anchor (holds the board picker) — always on.
    if (!_editing || key == _Card.hero) return child;
    return _HideableCard(hidden: hidden, onToggle: () => _toggleCard(key), child: child);
  }

  Widget _sprintCard(DashboardBoard? sprint) =>
      sprint == null ? const _SprintEmpty() : _SprintHero(sprint: sprint);
}

// ══════════════════════════ Glass card ═════════════════════════════════════

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(21),
    this.gradient,
    this.borderColor,
    this.onTap,
  });

  static const double _radius = 26;

  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark
        ? Colors.white.withValues(alpha: .09)
        : Colors.white.withValues(alpha: .55);
    final border = borderColor ??
        (dark
            ? Colors.white.withValues(alpha: .13)
            : Colors.white.withValues(alpha: .62));
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: border),
      ),
      child: child,
    );
    if (onTap != null) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(_radius),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D2B55).withValues(alpha: dark ? .48 : .26),
            blurRadius: 40,
            spreadRadius: -24,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: content,
        ),
      ),
    );
  }
}

BoxDecoration _innerTile(bool dark) => BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: .045)
          : Colors.white.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: .07)
            : Colors.white.withValues(alpha: .55),
      ),
    );

// ══════════════════════════ Greeting header ════════════════════════════════

class _Greeting extends StatelessWidget {
  const _Greeting({required this.sprint});
  final DashboardBoard? sprint;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final first = (user?.displayName ?? '').trim().split(' ').first;
    final hour = DateTime.now().hour;
    final key = hour < 11
        ? 'dashboard.greetMorning'
        : hour < 18
            ? 'dashboard.greetAfternoon'
            : 'dashboard.greetEvening';
    final greeting = context.t(key, variables: {'name': first}).trim();
    final date = _dateLabel(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting.endsWith(',') ? greeting.substring(0, greeting.length - 1) : greeting,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: context.isCompact ? 27 : 34,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.8,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
          child: (sprint != null && sprint!.isSprint && sprint!.days > 0)
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$date · '),
                    Text(
                      context.t('dashboard.sprintDay', variables: {
                        'day': '${sprint!.day}',
                        'days': '${sprint!.days}',
                      }),
                      style: const TextStyle(
                        color: AppColors.accentStrong,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Text(date),
        ),
      ],
    );
  }

  String _dateLabel(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    try {
      return DateFormat.MMMMEEEEd(code).format(DateTime.now());
    } catch (_) {
      return DateFormat.MMMMEEEEd().format(DateTime.now());
    }
  }
}

// ══════════════════════════ Sprint hero ════════════════════════════════════

class _SprintHero extends StatelessWidget {
  const _SprintHero({required this.sprint});
  final DashboardBoard sprint;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final ring = _ProgressRing(pct: sprint.progressPercent, size: compact ? 104 : 150);
    return _GlassCard(
      padding: EdgeInsets.all(compact ? 20 : 26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xE01E1C3A), Color(0xD12D2B55)],
      ),
      borderColor: Colors.white.withValues(alpha: .14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Honeycomb watermark: large + pushed far off the bottom-right corner
          // so only a soft curve shows — reads as texture, never a cut-off logo.
          Positioned(
            right: -220,
            bottom: -240,
            child: IgnorePointer(
              child: Opacity(
                opacity: .07,
                child: HexMark(size: 460, color: AppColors.accent),
              ),
            ),
          ),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: _badge(context)), ring],
                ),
                const SizedBox(height: 14),
                _body(context),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_badge(context), const SizedBox(height: 14), _body(context)],
                  ),
                ),
                const SizedBox(width: 22),
                ring,
              ],
            ),
        ],
      ),
    );
  }

  Widget _badge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            context.t(sprint.isSprint ? 'dashboard.activeSprint' : 'dashboard.kanbanBoard'),
            style: const TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFFEBCF8F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          sprint.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: _heroInk,
          ),
        ),
        if ((sprint.goal ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            sprint.goal!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: .72),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (sprint.isSprint) ...[
              _chip(LucideIcons.calendarDays,
                  context.t('dashboard.dayChip', variables: {'day': '${sprint.day}', 'days': '${sprint.days}'})),
              _chip(LucideIcons.gauge,
                  context.t('dashboard.spChip', variables: {'done': '${sprint.points}', 'total': '${sprint.pointsTotal}'})),
            ],
            _chip(LucideIcons.circleCheck,
                context.t('dashboard.issuesChip', variables: {'done': '${sprint.issuesDone}', 'total': '${sprint.issuesTotal}'})),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _boardButton(context),
            const SizedBox(width: 14),
            if (sprint.members.isNotEmpty)
              Flexible(child: _AvatarStack(members: sprint.members)),
          ],
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: .7)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: _heroInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(
          sprint.boardId.isNotEmpty ? '/boards/${sprint.boardId}' : '/board',
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE4AC3E), Color(0xFFCE9526)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD9A032).withValues(alpha: .35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.columns3, size: 15, color: Color(0xFF2A2410)),
              const SizedBox(width: 8),
              Text(
                context.t('dashboard.toBoard'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2A2410),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SprintEmpty extends StatelessWidget {
  const _SprintEmpty();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.goal, color: AppColors.accentStrong, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            context.t('dashboard.noSprint'),
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('dashboard.noSprintMessage'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF2A2410),
            ),
            onPressed: () => context.go('/board'),
            child: Text(context.t('dashboard.planSprint')),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<SprintMember> members;

  static const _size = 30.0;
  static const _ring = 2.0;
  static const _outer = _size + _ring * 2; // 34 — ring sits outside the avatar
  static const _step = _outer * 0.68; // overlap; leaves the initials readable

  @override
  Widget build(BuildContext context) {
    final shown = members.take(5).toList();
    final extra = members.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      height: _outer,
      width: _outer + (count - 1) * _step,
      child: Stack(
        children: [
          for (final (i, m) in shown.indexed)
            Positioned(
              left: i * _step,
              child: _ringed(HiveAvatar(name: m.displayName, imageUrl: m.avatarUrl, size: _size)),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * _step,
              child: _ringed(Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .16),
                ),
                child: Text(
                  '+$extra',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _heroInk),
                ),
              )),
            ),
        ],
      ),
    );
  }

  // A solid ring drawn *around* (not over) the avatar so initials stay intact.
  Widget _ringed(Widget child) => Container(
        padding: const EdgeInsets.all(_ring),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF262450)),
        child: child,
      );
}

// ══════════════════════════ Progress ring ══════════════════════════════════

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.pct, this.size = 148});
  final double pct;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 1400),
        curve: hiveEase,
        builder: (_, v, _) => Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(size: Size.square(size), painter: _RingPainter(v)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(v * 100).round()}%',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: size < 120 ? 22 : 29,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: _heroInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.t('dashboard.sprintCompleted'),
                  style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: .7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.pct);
  final double pct;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .13);
    canvas.drawCircle(center, radius, track);
    if (pct <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [_cAmberHi, _cAmberLo],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * pct, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ══════════════════════════ KPIs ═══════════════════════════════════════════

class _Kpis extends StatelessWidget {
  const _Kpis({
    required this.today,
    required this.completion,
    this.projectIds = const [],
  });
  final int today;
  final ProjectCompletion completion;

  /// The dashboard's active project scope, forwarded so the Issues page shows
  /// exactly the same set the counts were computed from.
  final List<String> projectIds;

  void _open(BuildContext context, String view) {
    final scope = projectIds.isEmpty ? '' : '&projects=${projectIds.join(',')}';
    context.go('/issues?view=$view$scope');
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _KpiCard(label: context.t('dashboard.kpiToday'), value: today, icon: LucideIcons.inbox, hue: _cToday, onTap: () => _open(context, 'today')),
      _KpiCard(label: context.t('dashboard.inProgress'), value: completion.inProgress, icon: LucideIcons.loader, hue: AppColors.accentStrong, onTap: () => _open(context, 'inprogress')),
      _KpiCard(label: context.t('dashboard.backlog'), value: completion.backlog, icon: LucideIcons.layers, hue: _cBacklog, onTap: () => _open(context, 'backlog')),
      _KpiCard(label: context.t('dashboard.done'), value: completion.done, icon: LucideIcons.circleCheckBig, hue: _cDone, onTap: () => _open(context, 'done')),
    ];
    if (context.isCompact) {
      return SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 156, child: items[i]),
        ),
      );
    }
    return Column(
      children: [
        Row(children: [
          Expanded(child: items[0]),
          const SizedBox(width: _gap),
          Expanded(child: items[1]),
        ]),
        const SizedBox(height: _gap),
        Row(children: [
          Expanded(child: items[2]),
          const SizedBox(width: _gap),
          Expanded(child: items[3]),
        ]),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.hue,
    this.onTap,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color hue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: hue.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 15, color: hue),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _CountUp(
                value: value,
                style: TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 31,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.5,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutQuart,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}

// ══════════════════════════ Focus list ═════════════════════════════════════

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.issues});
  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.focus'),
            actionLabel: context.t('dashboard.allIssues'),
            onAction: () => context.go('/issues'),
          ),
          const SizedBox(height: 14),
          if (issues.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(context.t('dashboard.noTasks'), style: TextStyle(color: AppColors.inkSoft)),
            )
          else
            for (final issue in issues.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _FocusItem(issue: issue),
              ),
        ],
      ),
    );
  }
}

class _FocusItem extends StatelessWidget {
  const _FocusItem({required this.issue});
  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compact = context.isCompact;
    final hasEstimate = issue.estimateMinutes != null && issue.estimateMinutes! > 0;
    final progress = hasEstimate
        ? (issue.spentMinutes / issue.estimateMinutes!).clamp(0.0, 1.0)
        : 0.0;
    final due = dueLabel(issue.dueDate);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showIssueDetailSheet(
          context,
          issueId: issue.id,
          onChanged: () => context.read<FetchCubit<DashboardData>>().load(),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: _innerTile(dark),
          child: Row(
            children: [
              TypeGlyph(type: issue.type, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      issue.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        IdMono(issue.readableId),
                        if (due != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            due.text,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11,
                              color: due.late ? AppColors.danger : AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!compact && hasEstimate) ...[
                const SizedBox(width: 10),
                SizedBox(width: 64, child: HiveProgress(value: progress, height: 5)),
              ],
              const SizedBox(width: 10),
              if (issue.assigneeId != null) HiveAvatar(name: issue.assigneeId!, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════ Completion donut ═══════════════════════════════

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completion});
  final ProjectCompletion completion;

  @override
  Widget build(BuildContext context) {
    final segs = <(String, int, Color)>[
      (context.t('dashboard.done'), completion.done, _cDone),
      (context.t('dashboard.inProgress'), completion.inProgress, _cProgress),
      (context.t('dashboard.backlog'), completion.backlog, _cBacklog),
    ];
    final total = completion.total;
    final donePct = (completion.donePercent * 100).round();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.projectProgress'),
            subLabel: context.t('dashboard.issuesCount', variables: {'count': '$total'}),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: total == 0 ? 0.0 : 1.0),
                      duration: const Duration(milliseconds: 1200),
                      curve: hiveEase,
                      builder: (_, t, _) => CustomPaint(
                        size: const Size.square(132),
                        painter: _DonutPainter([for (final (_, v, c) in segs) (v.toDouble(), c)], t),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CountUp(
                          value: donePct,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          context.t('dashboard.resolved'),
                          style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, value, color) in segs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                              ),
                            ),
                            Text(
                              '${total == 0 ? 0 : (value / total * 100).round()}%',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.t);
  final List<(double, Color)> segments;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 15.0;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final total = segments.fold<double>(0, (s, e) => s + e.$1);
    if (total <= 0 || t <= 0) return;
    const gap = 0.07;
    double start = -math.pi / 2;
    for (final (value, color) in segments) {
      if (value <= 0) continue;
      final frac = value / total;
      final full = 2 * math.pi * frac;
      final sweep = math.max(0.0, full - gap) * t;
      if (sweep > 0) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color;
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, paint);
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.t != t || old.segments != segments;
}

// ══════════════════════════ Focus-time tracker ═════════════════════════════

class _TrackerCard extends StatefulWidget {
  const _TrackerCard({required this.week, required this.month});
  final List<TrackerDay> week;
  final List<TrackerWeek> month;

  @override
  State<_TrackerCard> createState() => _TrackerCardState();
}

class _TrackerCardState extends State<_TrackerCard> {
  int _range = 0; // 0 = week, 1 = month

  @override
  Widget build(BuildContext context) {
    final monthly = _range == 1 && widget.month.isNotEmpty;
    final bars = <_BarData>[];
    if (monthly) {
      for (var i = 0; i < widget.month.length; i++) {
        final w = widget.month[i];
        bars.add(_BarData(
          label: context.t('dashboard.weekLabel', variables: {'n': '${w.week}'}),
          minutes: w.focusMinutes,
          today: i == widget.month.length - 1,
        ));
      }
    } else {
      final code = Localizations.localeOf(context).languageCode;
      for (var i = 0; i < widget.week.length; i++) {
        final d = widget.week[i];
        String label;
        try {
          label = DateFormat.E(code).format(d.date);
        } catch (_) {
          label = DateFormat.E().format(d.date);
        }
        bars.add(_BarData(
          label: label.replaceAll('.', ''),
          minutes: d.focusMinutes,
          today: i == widget.week.length - 1,
        ));
      }
    }
    final totalMinutes = bars.fold<int>(0, (s, b) => s + b.minutes);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('dashboard.focusTime'),
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              Text(
                context.t('dashboard.hours', variables: {'value': _hours(context, totalMinutes)}),
                style: TextStyle(fontFamily: AppTheme.fontMono, fontSize: 12, color: AppColors.inkSoft),
              ),
              const SizedBox(width: 10),
              _Segmented(
                options: [context.t('dashboard.week'), context.t('dashboard.month')],
                index: _range,
                onChanged: (i) => setState(() => _range = i),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(height: 150, child: _Bars(bars: bars)),
        ],
      ),
    );
  }

  String _hours(BuildContext context, int minutes) {
    final v = (minutes / 60).toStringAsFixed(1);
    return Localizations.localeOf(context).languageCode == 'de' ? v.replaceAll('.', ',') : v;
  }
}

class _BarData {
  const _BarData({required this.label, required this.minutes, required this.today});
  final String label;
  final int minutes;
  final bool today;
}

class _Bars extends StatelessWidget {
  const _Bars({required this.bars});
  final List<_BarData> bars;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final max = bars.fold<int>(1, (m, b) => b.minutes > m ? b.minutes : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final b in bars)
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final areaH = c.maxHeight - 24;
                final frac = b.minutes / max;
                final target = math.max(frac * areaH, b.minutes > 0 ? 8.0 : 3.0);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: target),
                      duration: const Duration(milliseconds: 900),
                      curve: hiveEase,
                      builder: (_, h, _) => Container(
                        width: 20,
                        height: h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: b.today
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [_cAmberHi, _cAmberLo])
                              : null,
                          color: b.today
                              ? null
                              : (dark
                                  ? Colors.white.withValues(alpha: .22)
                                  : AppColors.navy.withValues(alpha: .75)),
                          boxShadow: b.today
                              ? [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(alpha: .4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      b.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 10.5,
                        color: b.today ? AppColors.accentStrong : AppColors.inkFaint,
                        fontWeight: b.today ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.options, required this.index, required this.onChanged});
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: .06) : Colors.black.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, label) in options.indexed)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: hiveEase,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: i == index ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i == index ? const Color(0xFF2A2410) : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════ Git activity ═══════════════════════════════════

class _GitCard extends StatelessWidget {
  const _GitCard({required this.events});
  final List<GitEvent> events;

  @override
  Widget build(BuildContext context) {
    final repo = events.map((e) => e.repo).firstWhere((r) => r != null && r.isNotEmpty, orElse: () => null);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.gitActivity'),
            subLabel: repo,
          ),
          const SizedBox(height: 8),
          for (final e in events.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _GitRow(event: e),
            ),
        ],
      ),
    );
  }
}

class _GitRow extends StatelessWidget {
  const _GitRow({required this.event});
  final GitEvent event;

  @override
  Widget build(BuildContext context) {
    final (icon, hue) = _kindStyle(event.kind);
    final compact = context.isCompact;
    final meta = [
      if ((event.repo ?? '').isNotEmpty) event.repo!,
      if (event.at != null) _rel(event.at!),
      if ((event.authorName ?? '').isNotEmpty) event.authorName!,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: hue.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: hue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: event.ref,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentStrong,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  ${event.text}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
              ],
            ],
          ),
        ),
        if (!compact && (event.issueKey ?? '').isNotEmpty) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: IdMono(event.issueKey!),
          ),
        ],
      ],
    );
  }

  (IconData, Color) _kindStyle(String kind) => switch (kind) {
        'pr' => (LucideIcons.eye, _cToday),
        'deploy' => (LucideIcons.rocket, _cDone),
        'merge' => (LucideIcons.circleCheckBig, Color(0xFFA45CC7)),
        _ => (LucideIcons.circleDot, AppColors.accentStrong),
      };

  String _rel(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ══════════════════════════ Team ranking ═══════════════════════════════════

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.ranking});
  final List<RankEntry> ranking;

  @override
  Widget build(BuildContext context) {
    final shown = ranking.take(5).toList();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead(
            title: context.t('dashboard.teamRanking'),
            subLabel: context.t('dashboard.thisWeek'),
          ),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(context.t('dashboard.noRanking'), style: TextStyle(color: AppColors.inkSoft)),
            ),
          for (final (i, entry) in shown.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: i == shown.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: AppColors.hairline2)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: i == 0
                        ? const Icon(LucideIcons.star, size: 14, color: AppColors.accentStrong)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 12,
                              color: AppColors.inkFaint,
                            ),
                          ),
                  ),
                  HiveAvatar(name: entry.displayName, imageUrl: entry.avatarUrl, size: 30),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (entry.title != null)
                          Text(
                            entry.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    context.t('dashboard.pointsShort', variables: {'count': '${entry.points}'}),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentStrong,
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

// ══════════════════════════ Card header ════════════════════════════════════

class _CardHead extends StatelessWidget {
  const _CardHead({required this.title, this.subLabel, this.actionLabel, this.onAction});

  final String title;
  final String? subLabel;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: AppColors.ink,
            ),
          ),
        ),
        if (subLabel != null)
          Text(
            subLabel!,
            style: TextStyle(fontFamily: AppTheme.fontMono, fontSize: 12, color: AppColors.inkFaint),
          ),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(LucideIcons.arrowRight, size: 13, color: AppColors.accentStrong),
              ],
            ),
          ),
      ],
    );
  }
}

// ══════════════════════ Customize (edit mode) ══════════════════════════════

/// The header toggle. Desktop/tablet show icon + label; mobile shows the icon
/// only. In edit mode it turns amber and becomes a "Done" (save) action.
class _CustomizeButton extends StatelessWidget {
  const _CustomizeButton({
    required this.editing,
    required this.saving,
    required this.compact,
    required this.onPressed,
  });

  final bool editing;
  final bool saving;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label =
        context.t(editing ? 'dashboard.done_editing' : 'dashboard.customize');
    final icon = editing ? LucideIcons.check : LucideIcons.settings2;
    final bg = editing
        ? AppColors.accent
        : (dark
            ? Colors.white.withValues(alpha: .09)
            : Colors.white.withValues(alpha: .6));
    final fg = editing ? const Color(0xFF2A2410) : AppColors.ink;
    final border = editing
        ? Colors.transparent
        : (dark
            ? Colors.white.withValues(alpha: .14)
            : Colors.white.withValues(alpha: .7));

    final Widget content = saving
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : (compact
            ? Icon(icon, size: 18, color: fg)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ));

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: saving ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            width: compact ? 40 : null,
            alignment: Alignment.center,
            padding: compact
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Wraps a card in edit mode: dims it when hidden, blocks its own interactions,
/// and overlays a show/hide eye toggle.
class _HideableCard extends StatelessWidget {
  const _HideableCard({
    required this.hidden,
    required this.onToggle,
    required this.child,
  });

  final bool hidden;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The card is inert while editing — no accidental navigation.
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: hidden ? 0.4 : 1,
            child: child,
          ),
        ),
        Positioned(top: 12, right: 12, child: _EyeToggle(hidden: hidden, onTap: onToggle)),
      ],
    );
  }
}

class _EyeToggle extends StatelessWidget {
  const _EyeToggle({required this.hidden, required this.onTap});

  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark
          ? const Color(0xFF232140).withValues(alpha: .82)
          : Colors.white.withValues(alpha: .9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            hidden ? LucideIcons.eyeOff : LucideIcons.eye,
            size: 16,
            color: hidden ? AppColors.inkSoft : AppColors.accentStrong,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════ Edit toolbar + pickers ═════════════════════════════

/// The inline edit controls: hero-board picker, data scope and team-ranking
/// scope. Every change flows out through [onChanged] (which re-fetches).
class _EditToolbar extends StatelessWidget {
  const _EditToolbar({
    required this.boards,
    required this.draft,
    required this.projects,
    required this.teams,
    required this.onChanged,
  });

  final List<DashboardBoardOption> boards;
  final DashboardPrefs draft;
  final List<Project> projects;
  final List<Team> teams;
  final ValueChanged<DashboardPrefs> onChanged;

  DashboardBoardOption? get _selectedBoard {
    for (final b in boards) {
      if (b.id == draft.boardId) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final boardLabel =
        _selectedBoard?.name ?? context.t('dashboard.heroBoardAuto');
    final projectsLabel = draft.projectIds.isEmpty
        ? context.t('dashboard.scopeAllProjects')
        : context.t('dashboard.scopeProjectsCount',
            variables: {'count': '${draft.projectIds.length}'});
    final teamsLabel = draft.teamIds.isEmpty
        ? context.t('dashboard.scopeAllTeams')
        : context.t('dashboard.scopeTeamsCount',
            variables: {'count': '${draft.teamIds.length}'});

    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 15, color: AppColors.accentStrong),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('dashboard.editHint'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final fields = <Widget>[
                _PickerField(
                  icon: LucideIcons.layoutDashboard,
                  label: context.t('dashboard.heroBoard'),
                  value: boardLabel,
                  onTap: (rect) => _pickBoard(context, rect),
                ),
                _PickerField(
                  icon: LucideIcons.folderKanban,
                  label: context.t('dashboard.dataScope'),
                  value: projectsLabel,
                  onTap: (rect) => _pickProjects(context, rect),
                ),
                _PickerField(
                  icon: LucideIcons.usersRound,
                  label: context.t('dashboard.teamScope'),
                  value: teamsLabel,
                  onTap: (rect) => _pickTeams(context, rect),
                ),
              ];
              // Compact fixed-width fields (matching the popover width) that wrap
              // instead of stretching across the whole toolbar.
              const gap = 12.0;
              final width = c.maxWidth < _kPickerWidth ? c.maxWidth : _kPickerWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [for (final f in fields) SizedBox(width: width, child: f)],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickBoard(BuildContext context, Rect anchor) async {
    final result = await showGlassAnchoredPopover<String>(
      context,
      anchorRect: anchor,
      width: _kPickerWidth,
      builder: (_) => _BoardPickerSheet(boards: boards, selected: draft.boardId),
    );
    if (result == null) return; // dismissed
    onChanged(draft.copyWith(
      boardId: result.isEmpty ? null : result,
      clearBoard: result.isEmpty,
    ));
  }

  Future<void> _pickProjects(BuildContext context, Rect anchor) async {
    final result = await showGlassAnchoredPopover<List<String>>(
      context,
      anchorRect: anchor,
      width: _kPickerWidth,
      builder: (_) => _ScopePickerSheet(
        title: context.t('dashboard.dataScope'),
        icon: LucideIcons.folderKanban,
        allLabel: context.t('dashboard.scopeAllProjects'),
        items: [for (final p in projects) (id: p.id, name: p.name)],
        selected: draft.projectIds.toSet(),
      ),
    );
    if (result == null) return;
    onChanged(draft.copyWith(projectIds: result));
  }

  Future<void> _pickTeams(BuildContext context, Rect anchor) async {
    final result = await showGlassAnchoredPopover<List<String>>(
      context,
      anchorRect: anchor,
      width: _kPickerWidth,
      builder: (_) => _ScopePickerSheet(
        title: context.t('dashboard.teamScope'),
        icon: LucideIcons.usersRound,
        allLabel: context.t('dashboard.scopeAllTeams'),
        items: [for (final t in teams) (id: t.id, name: t.name)],
        selected: draft.teamIds.toSet(),
      ),
    );
    if (result == null) return;
    onChanged(draft.copyWith(teamIds: result));
  }
}

/// A labelled, dropdown-like field that opens a picker anchored to itself on
/// tap (reports its own global rect so the popover attaches to the field).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          final rect = box != null && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : Rect.zero;
          onTap(rect);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: .05)
                : Colors.white.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: .1)
                  : Colors.white.withValues(alpha: .7),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.accentStrong),
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
                        color: AppColors.inkSoft,
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
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-select list of the caller's boards (plus "Automatic"). Pops the
/// chosen board id, an empty string for automatic, or null on cancel.
class _BoardPickerSheet extends StatelessWidget {
  const _BoardPickerSheet({required this.boards, required this.selected});

  final List<DashboardBoardOption> boards;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.layoutDashboard,
          title: context.t('dashboard.heroBoard'),
          subtitle: context.t('dashboard.editHint'),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              _ChoiceRow(
                icon: LucideIcons.sparkles,
                label: context.t('dashboard.heroBoardAuto'),
                selected: selected == null,
                onTap: () => Navigator.of(context).pop(''),
              ),
              for (final b in boards)
                _ChoiceRow(
                  icon: b.isScrum ? LucideIcons.zap : LucideIcons.columns3,
                  label: b.name,
                  selected: b.id == selected,
                  onTap: () => Navigator.of(context).pop(b.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Multi-select scope list with an "All" reset row. Pops the selected ids
/// (empty ⇒ all), or null on cancel.
class _ScopePickerSheet extends StatefulWidget {
  const _ScopePickerSheet({
    required this.title,
    required this.icon,
    required this.allLabel,
    required this.items,
    required this.selected,
  });

  final String title;
  final IconData icon;
  final String allLabel;
  final List<({String id, String name})> items;
  final Set<String> selected;

  @override
  State<_ScopePickerSheet> createState() => _ScopePickerSheetState();
}

class _ScopePickerSheetState extends State<_ScopePickerSheet> {
  late final Set<String> _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: widget.icon,
          title: widget.title,
          subtitle: context.t('dashboard.editHint'),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            children: [
              _ChoiceRow(
                icon: LucideIcons.layoutGrid,
                label: widget.allLabel,
                selected: _sel.isEmpty,
                onTap: () => setState(_sel.clear),
              ),
              for (final it in widget.items)
                _ChoiceRow(
                  icon: LucideIcons.check,
                  showIcon: false,
                  label: it.name,
                  selected: _sel.contains(it.id),
                  onTap: () => setState(() =>
                      _sel.contains(it.id) ? _sel.remove(it.id) : _sel.add(it.id)),
                ),
            ],
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.apply'),
          onConfirm: () => Navigator.of(context).pop(_sel.toList()),
        ),
      ],
    );
  }
}

/// A selectable row for the pickers: leading glyph, label, trailing check.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.showIcon = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent.withValues(alpha: .5) : AppColors.hairline,
            ),
          ),
          child: Row(
            children: [
              if (showIcon && icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.accentStrong : AppColors.inkSoft,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 16, color: AppColors.accentStrong),
            ],
          ),
        ),
      ),
    );
  }
}

