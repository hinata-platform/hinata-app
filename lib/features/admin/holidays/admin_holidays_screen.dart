import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/availability_models.dart';
import '../../../core/repositories/availability_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_filter_bar.dart' show GlassStepperPill;
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/soft_card.dart';
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart';
import 'holiday_calendar_card.dart';
import 'holiday_calendar_sheet.dart';
import 'holiday_sheet.dart';

/// Admin → Holidays (HIN-91): the instance's holiday calendars and their days.
///
/// No country logic anywhere: a region's holidays are whatever its calendar
/// holds, kept by hand or imported from a calendar address. People pick the
/// calendar they follow in their own settings; one calendar can be the default
/// for everybody who picks none.
///
/// An import runs on the server and answers at once, so this page reads the
/// calendars again every two seconds while one is importing, and stops after a
/// minute whatever the state.
class AdminHolidaysScreen extends StatefulWidget {
  const AdminHolidaysScreen({super.key});

  @override
  State<AdminHolidaysScreen> createState() => _AdminHolidaysScreenState();
}

class _AdminHolidaysScreenState extends State<AdminHolidaysScreen> {
  static const _pollEvery = Duration(seconds: 2);
  static const _pollRoundsMax = 30;

  List<HolidayCalendar> _calendars = const [];
  bool _loading = true;
  String? _errorKey;
  String? _selectedId;
  int _year = DateTime.now().year;
  List<Holiday> _holidays = const [];
  bool _holidaysLoading = false;
  Timer? _poll;
  int _pollRounds = 0;

  AvailabilityRepository get _repository =>
      context.read<AvailabilityRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  HolidayCalendar? get _selected =>
      _calendars.where((calendar) => calendar.id == _selectedId).firstOrNull;

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _errorKey = null;
      });
    }
    final wasImporting = {
      for (final calendar in _calendars)
        if (calendar.importing) calendar.id,
    };
    try {
      final page = await _repository.calendars(size: 100);
      if (!mounted) return;
      final previousSelection = _selectedId;
      setState(() {
        _calendars = page.items;
        _loading = false;
        if (_selected == null) _selectedId = page.items.firstOrNull?.id;
      });
      final finished = wasImporting.any(
        (id) => !_calendars.any(
          (calendar) => calendar.id == id && calendar.importing,
        ),
      );
      if (_selectedId != previousSelection || finished || !quiet) {
        unawaited(_loadHolidays());
      }
      _schedulePoll();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!_calendars.any((calendar) => calendar.importing) ||
        _pollRounds >= _pollRoundsMax) {
      _pollRounds = 0;
      return;
    }
    _pollRounds++;
    _poll = Timer(_pollEvery, () {
      if (mounted) unawaited(_load(quiet: true));
    });
  }

  Future<void> _loadHolidays() async {
    final id = _selectedId;
    if (id == null) {
      setState(() => _holidays = const []);
      return;
    }
    setState(() => _holidaysLoading = true);
    try {
      final holidays = await _repository.holidays(id, year: _year);
      if (!mounted || id != _selectedId) return;
      setState(() {
        _holidays = holidays;
        _holidaysLoading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _holidaysLoading = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on ApiFailure catch (failure) {
      if (mounted) showGlassErrorToast(context, context.t(failure.message));
    }
  }

  Future<void> _editCalendar(HolidayCalendar? existing) async {
    final saved = await showHolidayCalendarSheet(context, existing: existing);
    if (saved == true && mounted) unawaited(_load(quiet: true));
  }

  Future<void> _deleteCalendar(HolidayCalendar calendar) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('availability.admin.deleteCalendar'),
      message: context.t(
        'availability.admin.deleteCalendarConfirm',
        variables: {'name': calendar.name},
      ),
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _repository.deleteCalendar(calendar.id);
      if (_selectedId == calendar.id) _selectedId = null;
      await _load(quiet: true);
    });
  }

  Future<void> _import(HolidayCalendar calendar) => _run(() async {
    final updated = await _repository.importHolidays(calendar.id, year: _year);
    if (!mounted) return;
    setState(() {
      _calendars = [
        for (final each in _calendars) each.id == updated.id ? updated : each,
      ];
      _pollRounds = 0;
    });
    _schedulePoll();
  });

  Future<void> _editHoliday(Holiday? existing) async {
    final calendar = _selected;
    if (calendar == null) return;
    final saved = await showHolidaySheet(
      context,
      calendarId: calendar.id,
      year: _year,
      existing: existing,
    );
    if (saved == true && mounted) unawaited(_loadHolidays());
  }

  Future<void> _deleteHoliday(Holiday holiday) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('availability.admin.deleteHoliday'),
      message: holiday.name,
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _repository.deleteHoliday(holiday.id);
      await _loadHolidays();
    });
  }

  void _moveYear(int by) {
    setState(() => _year += by);
    unawaited(_loadHolidays());
  }

  @override
  Widget build(BuildContext context) => PageChrome(
    title: context.t('availability.admin.pageTitle'),
    actions: [
      PageAction(
        icon: LucideIcons.plus,
        label: context.t('availability.admin.newCalendar'),
        primary: true,
        onTap: (_) => unawaited(_editCalendar(null)),
      ),
    ],
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    if (_loading && _calendars.isEmpty) {
      return const Center(child: HiveLoader());
    }
    if (_errorKey != null && _calendars.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HiveEmptyState(
            title: context.t('availability.admin.pageTitle'),
            message: context.t(_errorKey!),
            action: OutlinedButton(
              onPressed: () => unawaited(_load()),
              child: Text(context.t('common.retry')),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: context.topGutter,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          context.pageGutter,
          context.topGutter + 16,
          context.pageGutter,
          context.bottomGutter + 32,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.t('availability.admin.intro'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_calendars.isEmpty)
                    HiveEmptyState(
                      title: context.t('availability.admin.noCalendars'),
                      message: context.t(
                        'availability.admin.noCalendarsMessage',
                      ),
                      action: FilledButton.icon(
                        onPressed: () => unawaited(_editCalendar(null)),
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: Text(
                          context.t('availability.admin.newCalendar'),
                        ),
                      ),
                    )
                  else ...[
                    for (final calendar in _calendars) ...[
                      HolidayCalendarCard(
                        calendar: calendar,
                        year: _year,
                        selected: calendar.id == _selectedId,
                        onSelect: () {
                          setState(() => _selectedId = calendar.id);
                          unawaited(_loadHolidays());
                        },
                        onImport: () => unawaited(_import(calendar)),
                        onEdit: () => unawaited(_editCalendar(calendar)),
                        onDelete: () => unawaited(_deleteCalendar(calendar)),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 14),
                    _holidayList(context),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _holidayList(BuildContext context) {
    final calendar = _selected;
    if (calendar == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              context.t(
                'availability.admin.holidaysOf',
                variables: {'name': calendar.name},
              ),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassStepperPill(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '$_year',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  onBack: () => _moveYear(-1),
                  onForward: () => _moveYear(1),
                  backTooltip: context.t('availability.admin.previousYear'),
                  forwardTooltip: context.t('availability.admin.nextYear'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(_editHoliday(null)),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: Text(context.t('availability.admin.addHoliday')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_holidaysLoading && _holidays.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: HiveLoader(size: 30)),
          )
        else if (_holidays.isEmpty)
          SoftCard(
            padding: const EdgeInsets.all(8),
            child: HiveEmptyState(
              title: context.t(
                'availability.admin.noHolidays',
                variables: {'year': '$_year'},
              ),
              message: context.t('availability.admin.noHolidaysMessage'),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            ),
          )
        else
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final holiday in _holidays)
                  _HolidayRow(
                    holiday: holiday,
                    onEdit: () => unawaited(_editHoliday(holiday)),
                    onDelete: () => unawaited(_deleteHoliday(holiday)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HolidayRow extends StatelessWidget {
  const _HolidayRow({
    required this.holiday,
    required this.onEdit,
    required this.onDelete,
  });

  final Holiday holiday;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(holiday.date);
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            SizedBox(
              width: context.isCompact ? 96 : 130,
              child: Text(
                date,
                style: TextStyle(
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    holiday.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (holiday.halfDay || holiday.imported)
                    Text(
                      [
                        if (holiday.halfDay)
                          context.t('availability.admin.halfDay'),
                        if (holiday.imported)
                          context.t('availability.admin.imported'),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.t('availability.admin.deleteHoliday'),
              onPressed: onDelete,
              icon: Icon(
                LucideIcons.trash2,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
