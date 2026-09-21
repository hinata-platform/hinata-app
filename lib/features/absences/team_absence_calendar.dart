/// Who in a group is away when: the team absence calendar page (HIN-118).
///
/// A planning view, not a register. It shows spans of days and never times,
/// and sorts people by name, never by how much they were away (R10). This file
/// is the page with its controls; the band draws a wide window
/// (`team_absence_band.dart`), the agenda a phone (`team_absence_agenda.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/blocs/team_absence_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/team_absence_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/project_picker.dart';
import '../sprint/modals/glass_modal.dart';
import '../../core/util/dates.dart';
import 'team_absence_agenda.dart';
import 'team_absence_band.dart';

/// The calendar with its own controls: which group, which month or quarter,
/// and — for who plans — the capacity that is left above the rows.
class TeamAbsenceCalendar extends StatefulWidget {
  const TeamAbsenceCalendar({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  State<TeamAbsenceCalendar> createState() => _TeamAbsenceCalendarState();
}

class _TeamAbsenceCalendarState extends State<TeamAbsenceCalendar> {
  TeamAbsenceScope _scope = TeamAbsenceScope.mine;
  bool _quarter = false;

  /// Only the people with something to show in the window, as the reference
  /// planners offer it: on a team of forty, the six who are away.
  bool _awayOnly = false;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  late final TeamAbsenceRowsCubit _rows;
  late final FetchCubit<CapacityBand?> _band;

  /// Whether the page is laid out as the phone agenda rather than the band.
  bool _compact = false;
  bool _started = false;

  DateTime get _from => _month;
  DateTime get _to =>
      DateTime(_month.year, _month.month + (_quarter ? 3 : 1), 0);

  @override
  void initState() {
    super.initState();
    final repository = context.read<AbsenceRepository>();
    _rows = TeamAbsenceRowsCubit(
      (page, size) => repository.teamCalendar(
        from: _from,
        to: _to,
        scope: _scope,
        // The agenda lists only who is away, so a phone never asks for the rest.
        awayOnly: _awayOnly || _compact,
        page: page,
        size: size,
      ),
    );
    _band = FetchCubit<CapacityBand?>(() async {
      try {
        return await repository.capacityBand(
          from: _from,
          to: _to,
          scope: _scope,
          // The agenda shows a week per card; the server adds the week up.
          resolution: _compact
              ? CapacityResolution.week
              : CapacityResolution.day,
        );
      } on ApiFailure catch (failure) {
        // Not somebody who plans this group, or a group too small to add up
        // without showing one person: the band is simply not shown.
        if (failure.statusCode == 403) return null;
        rethrow;
      }
    });
  }

  @override
  void dispose() {
    unawaited(_rows.close());
    unawaited(_band.close());
    super.dispose();
  }

  void _reload() {
    unawaited(_loadRows());
    unawaited(_band.load());
  }

  Future<void> _loadRows() => _compact ? _rows.loadAll() : _rows.load();

  void _move(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _reload();
  }

  /// Whether the window on screen holds today, so "Today" has nothing to do.
  bool get _showsToday {
    final today = dateOnly(DateTime.now());
    return !today.isBefore(_from) && !today.isAfter(_to);
  }

  void _setQuarter(bool quarter) {
    setState(() => _quarter = quarter);
    _reload();
  }

  void _today() {
    final now = DateTime.now();
    setState(() => _month = DateTime(now.year, now.month));
    _reload();
  }

  Future<void> _pickScope(Rect? anchor) async {
    const mine = '';
    const project = '@project';
    List<({String id, String name})> teams = const [];
    try {
      teams = [
        for (final team in await context.read<TeamRepository>().teams())
          (id: team.id, name: team.name),
      ];
    } on ApiFailure {
      // Without the teams the picker still offers the reader's projects.
    }
    if (!mounted) return;
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('absence.team.group'),
      anchorRect: anchor,
      options: [
        (
          value: mine,
          child: _OptionRow(
            icon: LucideIcons.folderKanban,
            label: context.t('absence.team.myProjects'),
          ),
        ),
        for (final team in teams)
          (
            value: 'team:${team.id}',
            child: _OptionRow(icon: LucideIcons.users, label: team.name),
          ),
        (
          value: project,
          child: _OptionRow(
            icon: LucideIcons.search,
            label: context.t('absence.team.pickProject'),
          ),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    TeamAbsenceScope next;
    if (picked == mine) {
      next = TeamAbsenceScope.mine;
    } else if (picked == project) {
      final projects = await showProjectPicker(
        context,
        anchorRect: anchor ?? Rect.zero,
        selected: {?_scope.projectId},
        titleKey: 'absence.team.pickProject',
        multi: false,
      );
      if (projects == null || projects.isEmpty || !mounted) return;
      next = TeamAbsenceScope(
        projectId: projects.first.id,
        label: projects.first.name,
      );
    } else {
      final id = picked.substring(5);
      next = TeamAbsenceScope(
        teamId: id,
        label: teams.firstWhere((team) => team.id == id).name,
      );
    }
    setState(() => _scope = next);
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first read waits for the layout: a phone asks only for who is away.
    final compact = context.isCompact;
    if (!_started) {
      _started = true;
      _compact = compact;
      _reload();
    } else if (compact != _compact) {
      _compact = compact;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final period = _quarter
        ? '${DateFormat.MMM(locale).format(_from)} – '
              '${DateFormat.yMMM(locale).format(_to)}'
        : DateFormat.yMMMM(locale).format(_from);
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GlassFilterPill(
                icon: _scope.teamId != null
                    ? LucideIcons.users
                    : LucideIcons.folderKanban,
                label: _scope.label ?? context.t('absence.team.myProjects'),
                active: _scope != TeamAbsenceScope.mine,
                onTap: (anchor) => unawaited(_pickScope(anchor)),
              ),
              GlassSwitchBar(
                compact: true,
                maxWidth: 220,
                chips: [
                  GlassSwitchChip(
                    label: context.t('absence.team.month'),
                    active: !_quarter,
                    onTap: _quarter ? () => _setQuarter(false) : null,
                  ),
                  const SizedBox(width: 2),
                  GlassSwitchChip(
                    label: context.t('absence.team.quarter'),
                    active: _quarter,
                    onTap: _quarter ? null : () => _setQuarter(true),
                  ),
                ],
              ),
              _PeriodNav(
                label: period,
                onPrevious: () => _move(_quarter ? -3 : -1),
                onNext: () => _move(_quarter ? 3 : 1),
              ),
              if (!_showsToday)
                GlassFilterPill(
                  icon: LucideIcons.calendarCheck,
                  label: context.t('absence.team.today'),
                  active: false,
                  chevron: false,
                  onTap: (_) => _today(),
                ),
              if (!_compact)
                GlassFilterPill(
                  icon: LucideIcons.userX,
                  label: context.t('absence.team.awayOnly'),
                  active: _awayOnly,
                  chevron: false,
                  onTap: (_) {
                    setState(() => _awayOnly = !_awayOnly);
                    unawaited(_loadRows());
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child:
                BlocBuilder<TeamAbsenceRowsCubit, PagedState<TeamAbsenceRow>>(
                  bloc: _rows,
                  builder: (context, rows) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(child: _content(rows)),
                      if (!_compact && rows.items.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const TeamAbsenceLegend(),
                      ],
                      if (_rows.truncated) ...[
                        const SizedBox(height: 6),
                        Text(
                          context.t('absence.team.truncated'),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _content(PagedState<TeamAbsenceRow> rows) {
    if (!rows.hasData && rows.errorKey == null) {
      return const Center(child: HiveLoader(size: 32));
    }
    if (rows.errorKey != null && rows.items.isEmpty) {
      return HiveEmptyState(
        title: context.t('absence.team.errorTitle'),
        message: context.t(rows.errorKey!),
      );
    }
    // The agenda has something to say even with nobody away: every week is
    // there, with its capacity and "everybody is here".
    if (rows.items.isEmpty && !_compact) {
      return HiveEmptyState(
        title: context.t('absence.team.emptyTitle'),
        message: context.t('absence.team.emptyMessage'),
      );
    }
    return BlocBuilder<FetchCubit<CapacityBand?>, FetchState<CapacityBand?>>(
      bloc: _band,
      builder: (context, band) => _compact
          ? TeamAbsenceAgenda(
              from: _from,
              to: _to,
              rows: rows.items,
              capacity: band.data,
            )
          : TeamAbsenceBand(
              from: _from,
              to: _to,
              rows: rows.items,
              capacity: band.data,
              onNearEnd: rows.hasMore
                  ? () => unawaited(_rows.loadMore())
                  : null,
            ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.inkSoft),
      const SizedBox(width: 10),
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

/// Back, the period, forward — one glass capsule, as the calendars of the
/// references group them. Each arrow is its own 48-point target inside it.
class _PeriodNav extends StatelessWidget {
  const _PeriodNav({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Arrow(
          icon: LucideIcons.chevronLeft,
          tooltip: context.t('absence.team.previous'),
          onTap: onPrevious,
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        _Arrow(
          icon: LucideIcons.chevronRight,
          tooltip: context.t('absence.team.next'),
          onTap: onNext,
        ),
      ],
    );
    // The capsule is drawn at the toolbar's 36 points; the arrows take 48 by
    // 48 to hit (WCAG 2.5.8 and a thumb), reaching past it above and below.
    return SizedBox(
      height: _Arrow.extent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            top: (_Arrow.extent - kGlassControlHeight) / 2,
            bottom: (_Arrow.extent - kGlassControlHeight) / 2,
            child: GlassPill(
              height: kGlassControlHeight,
              child: SizedBox.expand(),
            ),
          ),
          row,
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  static const extent = 48.0;

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: extent,
          height: extent,
          child: Icon(icon, size: 16, color: AppColors.inkSoft),
        ),
      ),
    ),
  );
}
