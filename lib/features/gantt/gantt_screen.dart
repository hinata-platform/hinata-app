import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';

/// Zoom levels for the timeline. [week] shows individual day ticks under a
/// month band (Jira "Wochen"); [month] collapses to month columns only.
enum GanttZoom { week, month }

/// Short month names per language — kept local so we never depend on
/// `intl`'s date-symbol initialisation at runtime.
const Map<String, List<String>> _monthsShort = {
  'en': [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ],
  'de': [
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ],
};

String _monthLabel(BuildContext context, DateTime date, {bool withYear = false}) {
  final code = Localizations.localeOf(context).languageCode;
  final names = _monthsShort[code] ?? _monthsShort['en']!;
  final name = names[date.month - 1];
  return withYear ? '$name ${date.year}' : name;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

/// Interactive project timeline. Bars sit on a continuous day grid; the
/// floating switcher (bottom-right) toggles zoom and jumps to today.
class GanttScreen extends StatefulWidget {
  const GanttScreen({super.key});

  @override
  State<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends State<GanttScreen> {
  List<Project> _projects = const [];
  String? _projectId;
  List<GanttTask> _tasks = const [];
  bool _loading = true;
  String? _error;

  GanttZoom _zoom = GanttZoom.week;

  // Body drives header (horizontal) and labels (vertical); followers use
  // [NeverScrollableScrollPhysics] and mirror the body's offset.
  final _hBody = ScrollController();
  final _hHeader = ScrollController();
  final _vBody = ScrollController();
  final _vLabels = ScrollController();

  bool _didInitialScroll = false;

  static const _rowHeight = 44.0;
  static const _headerHeight = 50.0;

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() => _follow(_hHeader, _hBody.offset));
    _vBody.addListener(() => _follow(_vLabels, _vBody.offset));
    _load();
  }

  @override
  void dispose() {
    _hBody.dispose();
    _hHeader.dispose();
    _vBody.dispose();
    _vLabels.dispose();
    super.dispose();
  }

  /// Mirror [offset] onto a non-interactive follower controller, clamped to
  /// its own extent so a momentary size mismatch can never assert.
  void _follow(ScrollController follower, double offset) {
    if (!follower.hasClients) return;
    final max = follower.position.maxScrollExtent;
    final target = offset.clamp(0.0, max);
    if ((follower.offset - target).abs() > 0.5) follower.jumpTo(target);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = context.read<HivoraRepository>();
    try {
      _projects = await repository.projects();
      if (_projects.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _projectId ??= _projects.first.id;
      _tasks = await repository.gantt(_projectId!);
      _didInitialScroll = false;
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  double get _pxPerDay => switch (_zoom) {
        GanttZoom.week => 32,
        GanttZoom.month => 4.6,
      };

  double _labelWidth(BuildContext context) => context.isCompact ? 136 : 188;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              context.pageGutter, 22, context.pageGutter, 14),
          child: PageHead(
            title: context.t('gantt.title'),
            subtitle: context.t('gantt.subtitle'),
            actions: [
              if (_projects.isNotEmpty)
                _ProjectPicker(
                  projects: _projects,
                  selected: _projectId,
                  onChanged: (value) {
                    _projectId = value;
                    _load();
                  },
                ),
            ],
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: HiveLoader());
    }
    if (_error != null) {
      return Center(
          child: Text(context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary)));
    }
    if (_tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.t('gantt.empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final rawStart = _tasks
        .map((task) => task.startDate!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final rawEnd = _tasks
        .map((task) => task.dueDate ?? task.startDate!)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    // Snap the window so columns are whole units: weeks start on Monday and
    // both modes pad to full months so the band reads cleanly on each edge.
    final monthStart = _firstOfMonth(rawStart);
    DateTime chartStart;
    if (_zoom == GanttZoom.week) {
      final monday = rawStart.subtract(Duration(days: rawStart.weekday - 1));
      chartStart = _dayOnly(monday.isBefore(monthStart) ? monday : monthStart);
    } else {
      chartStart = monthStart;
    }
    final lastMonthEnd = DateTime(rawEnd.year, rawEnd.month + 1, 0);
    final chartEnd = lastMonthEnd.add(const Duration(days: 1));
    final totalDays = chartEnd.difference(chartStart).inDays;
    final timelineWidth = totalDays * _pxPerDay;
    final rowsHeight = _tasks.length * _rowHeight;

    final labelWidth = _labelWidth(context);

    // Today marker, only when it falls inside the rendered window.
    final today = _dayOnly(DateTime.now());
    final inRange =
        !today.isBefore(chartStart) && today.isBefore(chartEnd);
    final todayX = inRange
        ? today.difference(chartStart).inDays * _pxPerDay + _pxPerDay / 2
        : null;

    _maybeInitialScroll(todayX, timelineWidth);

    return Padding(
      padding: context.pagePadding,
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Column(
              children: [
                // ---- Header strip: corner + horizontally-synced axis ----
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    children: [
                      SizedBox(width: labelWidth),
                      Container(width: 1, color: AppColors.hairline),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _hHeader,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: _TimeAxis(
                            start: chartStart,
                            days: totalDays,
                            pxPerDay: _pxPerDay,
                            zoom: _zoom,
                            height: _headerHeight,
                            width: timelineWidth,
                            today: inRange ? today : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.hairline),
                // ---- Body: frozen labels + scrollable chart ----
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: labelWidth,
                        child: SingleChildScrollView(
                          controller: _vLabels,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final task in _tasks)
                                _TaskLabel(
                                  task: task,
                                  height: _rowHeight,
                                  onTap: () =>
                                      context.go('/issues/${task.id}'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, color: AppColors.hairline),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _hBody,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: timelineWidth,
                            child: SingleChildScrollView(
                              controller: _vBody,
                              child: SizedBox(
                                width: timelineWidth,
                                height: rowsHeight,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _GridPainter(
                                          start: chartStart,
                                          days: totalDays,
                                          pxPerDay: _pxPerDay,
                                          zoom: _zoom,
                                          todayX: todayX,
                                          rowHeight: _rowHeight,
                                          rowCount: _tasks.length,
                                          line: AppColors.hairline2,
                                          monthLine: AppColors.hairline,
                                          weekend: AppColors.canvas2,
                                          todayColor: AppColors.stTodo,
                                        ),
                                      ),
                                    ),
                                    for (var i = 0; i < _tasks.length; i++)
                                      _positionedBar(
                                          context, _tasks[i], i, chartStart),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // ---- Floating zoom / today switcher ----
            Positioned(
              right: 14,
              bottom: 14,
              child: _ViewSwitcher(
                zoom: _zoom,
                onZoom: (z) {
                  if (z == _zoom) return;
                  setState(() => _zoom = z);
                },
                onToday: () => _scrollToToday(todayX, timelineWidth),
                maxWidth: MediaQuery.sizeOf(context).width - 2 * context.pageGutter - 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _positionedBar(
      BuildContext context, GanttTask task, int row, DateTime chartStart) {
    final startOffset = task.startDate!.difference(chartStart).inDays;
    final duration = (task.dueDate ?? task.startDate!)
            .difference(task.startDate!)
            .inDays +
        1;
    final left = startOffset * _pxPerDay;
    final width = (duration * _pxPerDay).clamp(8.0, double.infinity);
    return Positioned(
      left: left,
      top: row * _rowHeight,
      height: _rowHeight,
      width: width,
      child: Center(
        child: _GanttBar(
          task: task,
          width: width,
          showLabel: _zoom == GanttZoom.week,
          onTap: () => context.go('/issues/${task.id}'),
        ),
      ),
    );
  }

  void _maybeInitialScroll(double? todayX, double timelineWidth) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToToday(todayX, timelineWidth, animate: false);
    });
  }

  void _scrollToToday(double? todayX, double timelineWidth,
      {bool animate = true}) {
    if (!_hBody.hasClients) return;
    final viewport = _hBody.position.viewportDimension;
    final max = _hBody.position.maxScrollExtent;
    final anchor = todayX ?? 0;
    final target = (anchor - viewport / 2).clamp(0.0, max);
    if (animate) {
      _hBody.animateTo(target,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic);
    } else {
      _hBody.jumpTo(target);
    }
  }
}

/// Compact white dropdown for choosing the active project.
class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? projects.where((p) => p.id == selected).firstOrNull?.name ??
            projects.first.name
        : projects.first.name;
    return PopupMenuButton<String>(
      initialValue: selected,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 44),
      itemBuilder: (_) => [
        for (final p in projects)
          PopupMenuItem(value: p.id, child: Text(p.name)),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded,
                size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Frozen left-column entry: readable id + title, tappable to open the issue.
class _TaskLabel extends StatelessWidget {
  const _TaskLabel(
      {required this.task, required this.height, required this.onTap});

  final GanttTask task;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12),
                    children: [
                      TextSpan(
                        text: task.readableId,
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(
                        text: task.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-tier (week) or single-tier (month) timeline header.
class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.start,
    required this.days,
    required this.pxPerDay,
    required this.zoom,
    required this.height,
    required this.width,
    required this.today,
  });

  final DateTime start;
  final int days;
  final double pxPerDay;
  final GanttZoom zoom;
  final double height;
  final double width;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final segments = _monthSegments();
    final bandHeight = zoom == GanttZoom.week ? 24.0 : height;

    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          // ---- Month band ----
          SizedBox(
            height: bandHeight,
            child: Row(
              children: [
                for (final seg in segments)
                  _MonthCell(
                    label: _monthLabel(context, seg.date,
                        withYear: seg.width * pxPerDay > 96),
                    width: seg.width * pxPerDay,
                    emphatic: zoom == GanttZoom.month,
                  ),
              ],
            ),
          ),
          // ---- Day ticks (week mode only) ----
          if (zoom == GanttZoom.week)
            SizedBox(
              height: height - bandHeight,
              child: Row(
                children: [
                  for (var i = 0; i < days; i++)
                    _DayTick(
                      date: start.add(Duration(days: i)),
                      width: pxPerDay,
                      isToday: today != null &&
                          start.add(Duration(days: i)) == today,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<({DateTime date, int width})> _monthSegments() {
    final out = <({DateTime date, int width})>[];
    var i = 0;
    while (i < days) {
      final date = start.add(Duration(days: i));
      final monthStart = _firstOfMonth(date);
      // Days remaining in this month within the rendered window.
      final endOfMonth = _daysInMonth(date);
      final consumed = date.day - 1;
      final remainInMonth = endOfMonth - consumed;
      final remainInChart = days - i;
      final span = remainInMonth < remainInChart ? remainInMonth : remainInChart;
      out.add((date: monthStart, width: span));
      i += span;
    }
    return out;
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell(
      {required this.label, required this.width, required this.emphatic});

  final String label;
  final double width;
  final bool emphatic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.hairline),
          bottom: BorderSide(color: AppColors.hairline2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(
            fontSize: emphatic ? 12 : 11,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _DayTick extends StatelessWidget {
  const _DayTick(
      {required this.date, required this.width, required this.isToday});

  final DateTime date;
  final double width;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final weekend = date.weekday >= DateTime.saturday;
    final child = Text(
      '${date.day}',
      style: TextStyle(
        fontSize: 10,
        fontWeight: isToday || date.day == 1 ? FontWeight.w800 : FontWeight.w400,
        color: isToday
            ? Colors.white
            : (weekend ? AppColors.inkSoft : AppColors.textSecondary),
      ),
    );
    return SizedBox(
      width: width,
      child: Center(
        child: isToday
            ? Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.stTodo,
                  shape: BoxShape.circle,
                ),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// Background grid: per-day hairlines (week), month boundaries, weekend
/// shading and the today line — all painted once behind every row.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.start,
    required this.days,
    required this.pxPerDay,
    required this.zoom,
    required this.todayX,
    required this.rowHeight,
    required this.rowCount,
    required this.line,
    required this.monthLine,
    required this.weekend,
    required this.todayColor,
  });

  final DateTime start;
  final int days;
  final double pxPerDay;
  final GanttZoom zoom;
  final double? todayX;
  final double rowHeight;
  final int rowCount;
  final Color line;
  final Color monthLine;
  final Color weekend;
  final Color todayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final weekendPaint = Paint()..color = weekend.withValues(alpha: 0.5);
    final dayPaint = Paint()
      ..color = line
      ..strokeWidth = 1;
    final monthPaint = Paint()
      ..color = monthLine
      ..strokeWidth = 1;
    final rowPaint = Paint()
      ..color = line.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    // Weekend shading (week mode keeps the grid readable; month mode is dense).
    if (zoom == GanttZoom.week) {
      for (var i = 0; i < days; i++) {
        final date = start.add(Duration(days: i));
        if (date.weekday >= DateTime.saturday) {
          final x = i * pxPerDay;
          canvas.drawRect(Rect.fromLTWH(x, 0, pxPerDay, size.height),
              weekendPaint);
        }
      }
    }

    // Vertical lines: emphasised on month boundaries.
    for (var i = 0; i <= days; i++) {
      final date = start.add(Duration(days: i));
      final isMonthEdge = i == 0 || i == days || date.day == 1;
      if (zoom == GanttZoom.week) {
        final x = i * pxPerDay;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height),
            isMonthEdge ? monthPaint : dayPaint);
      } else if (isMonthEdge) {
        final x = i * pxPerDay;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), monthPaint);
      }
    }

    // Horizontal row separators.
    for (var r = 1; r < rowCount; r++) {
      final y = r * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }

    // Today line.
    if (todayX != null) {
      final p = Paint()
        ..color = todayColor
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(todayX!, 0), Offset(todayX!, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.start != start ||
      old.days != days ||
      old.pxPerDay != pxPerDay ||
      old.zoom != zoom ||
      old.todayX != todayX ||
      old.rowCount != rowCount;
}

class _GanttBar extends StatelessWidget {
  const _GanttBar({
    required this.task,
    required this.width,
    required this.showLabel,
    required this.onTap,
  });

  final GanttTask task;
  final double width;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = task.resolved
        ? AppColors.stDone
        : AppColors.stateColor(task.state.toUpperCase());
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message:
            '${task.readableId} · ${task.state} · ${task.progressPercent}%',
        child: Container(
          width: width,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (task.progressPercent / 100).clamp(0.0, 1.0),
                  child:
                      Container(color: Colors.white.withValues(alpha: 0.22)),
                ),
              ),
              if (showLabel && width > 28)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      task.readableId,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating bottom-right control: a "today" action separated from the zoom
/// toggle. Horizontally scrollable internally so it can never overflow.
class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.zoom,
    required this.onZoom,
    required this.onToday,
    required this.maxWidth,
  });

  final GanttZoom zoom;
  final ValueChanged<GanttZoom> onZoom;
  final VoidCallback onToday;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.clamp(140.0, 420.0)),
      child: Material(
        color: AppColors.surface,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(color: AppColors.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SwitchChip(
                  label: context.t('gantt.today'),
                  icon: Icons.my_location_rounded,
                  active: false,
                  onTap: onToday,
                ),
                Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: AppColors.hairline,
                ),
                _SwitchChip(
                  label: context.t('gantt.week'),
                  active: zoom == GanttZoom.week,
                  onTap: () => onZoom(GanttZoom.week),
                ),
                const SizedBox(width: 2),
                _SwitchChip(
                  label: context.t('gantt.month'),
                  active: zoom == GanttZoom.month,
                  onTap: () => onZoom(GanttZoom.month),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchChip extends StatelessWidget {
  const _SwitchChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.accentStrong : AppColors.inkSoft;
    return Material(
      color: active ? AppColors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
