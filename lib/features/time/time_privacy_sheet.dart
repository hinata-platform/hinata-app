import 'dart:async';

import '../../core/docs/docs_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/time_privacy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../../core/models/time_privacy_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/timer_surfaces/surface_platform.dart';
import '../../core/timer_surfaces/timer_surface_prefs.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart';
import '../../core/theme/app_type.dart';
import 'timer_surface_options.dart';

/// "Who sees my time data?" and the privacy notice of the module (Art. 12–14
/// DSGVO), as one sheet.
///
/// Opened from Settings → Time tracking at any time, and once on first use with
/// an "Understood" that records the moment the person was informed. That button
/// is proof of information, not consent: working time is not processed on
/// consent, and nothing about the module changes if somebody closes the sheet.
Future<void> showTimePrivacySheet(
  BuildContext context, {
  bool firstUse = false,
}) {
  final privacy = context.read<TimePrivacyCubit>();
  // The sheet sits on the root navigator, above whatever provided these.
  final surfaces = maybeTimerSurfacePrefs(context);
  return showGlassModal<void>(
    context,
    adaptive: true,
    width: 560,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider<TimePrivacyCubit>.value(value: privacy),
        if (surfaces != null)
          BlocProvider<TimerSurfacePrefsCubit>.value(value: surfaces),
      ],
      child: TimePrivacyBody(firstUse: firstUse),
    ),
  );
}

/// Opens the notice once per session for somebody who has never confirmed it.
///
/// Called by every view of the module when it opens, because whichever comes
/// first is the first use. The notice is a state and not a route: no link leads
/// to it, and a screenshot script that only walks routes never sees it.
void offerTimePrivacyNotice(BuildContext context) {
  final privacy = context.read<TimePrivacyCubit>();
  unawaited(
    privacy.ensureLoaded().then((_) {
      if (!context.mounted || !privacy.takeFirstUseOffer()) return;
      unawaited(showTimePrivacySheet(context, firstUse: true));
    }),
  );
}

class TimePrivacyBody extends StatefulWidget {
  const TimePrivacyBody({super.key, this.firstUse = false});

  final bool firstUse;

  @override
  State<TimePrivacyBody> createState() => _TimePrivacyBodyState();
}

class _TimePrivacyBodyState extends State<TimePrivacyBody> {
  /// Whether the last read failed with nothing held from before, which is the
  /// one case where the sheet would otherwise spin for as long as it is open.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// The visibility is computed from the policies in force, so a sheet opened on
  /// purpose reads it again. On first use it was read a moment ago.
  Future<void> _load() async {
    final privacy = context.read<TimePrivacyCubit>();
    if (_failed) setState(() => _failed = false);
    final held = widget.firstUse
        ? await privacy.ensureLoaded()
        : await privacy.refresh();
    if (mounted && !held) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.shieldCheck,
          title: context.t('time.privacy.title'),
          subtitle: context.t(
            widget.firstUse
                ? 'time.privacy.firstUseSubtitle'
                : 'time.privacy.subtitle',
          ),
        ),
        BlocBuilder<TimePrivacyCubit, TimePrivacy?>(
          builder: (context, privacy) {
            if (privacy == null && _failed) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('time.privacy.loadFailed'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppType.label,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      icon: LucideIcons.refreshCw,
                      label: context.t('common.retry'),
                      onPressed: () => unawaited(_load()),
                    ),
                  ],
                ),
              );
            }
            if (privacy == null) {
              // Padded, not centred: a Center under a bounded height takes all of
              // it, and a loading sheet would open at full height.
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: HiveLoader(size: 34),
              );
            }
            return Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Heading(text: context.t('time.privacy.whoSees')),
                    const SizedBox(height: 6),
                    TimeVisibilityPanel(visibility: privacy.visibility),
                    if (_surfaces case final surfaces?) ...[
                      const SizedBox(height: 18),
                      _Heading(text: context.t('time.surface.device.heading')),
                      const SizedBox(height: 6),
                      TimerSurfacesDevicePanel(
                        prefs: surfaces,
                        platform: SurfacePlatform.current,
                      ),
                    ],
                    const SizedBox(height: 18),
                    _Heading(text: context.t('time.privacy.notice')),
                    const SizedBox(height: 6),
                    HinataMarkdownPreview(
                      markdown: privacy.notice,
                      fontSize: AppType.label,
                    ),
                    const SizedBox(height: 10),
                    const DocsLink(
                      slug: DocsPage.timeTrackingPrivacy,
                      labelKey: 'docs.timeTrackingPrivacy',
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: widget.firstUse
                ? PrimaryButton(
                    icon: LucideIcons.check,
                    label: context.t('time.privacy.understood'),
                    onPressed: () => _acknowledge(context),
                  )
                : GhostButton(
                    icon: LucideIcons.x,
                    label: context.t('common.close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
          ),
        ),
      ],
    );
  }

  /// The person's switches for the timer outside the app, where this device
  /// has any surface and somebody provided them.
  TimerSurfacePrefsCubit? get _surfaces {
    if (!hasTimerSurfaces(SurfacePlatform.current)) return null;
    return maybeTimerSurfacePrefs(context);
  }

  Future<void> _acknowledge(BuildContext context) async {
    final accepted = await context.read<TimePrivacyCubit>().acknowledge();
    if (!context.mounted) return;
    if (!accepted) {
      showGlassToast(
        context,
        context.t('time.privacy.acknowledgeFailed'),
        kind: GlassToastKind.error,
      );
      return;
    }
    Navigator.of(context).maybePop();
  }
}

/// The computed visibility as sentences, one per rule.
///
/// Sentences, never raw switches: "leadsSeeMemberEntries: false" tells a person
/// nothing, "Leads of your projects see project totals only" tells them what
/// they wanted to know. Two lines are always there, because they are true on
/// every instance; the rest follow the policies.
class TimeVisibilityPanel extends StatelessWidget {
  const TimeVisibilityPanel({super.key, required this.visibility});

  final TimeVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final v = visibility;
    final rows = <(IconData, String)>[
      (LucideIcons.user, context.t('time.privacy.row.self')),
      (LucideIcons.shieldCheck, context.t('time.privacy.row.admins')),
      (LucideIcons.eyeOff, context.t('time.privacy.row.members')),
      (
        LucideIcons.users,
        context.t(
          v.leadsSeeEntries
              ? 'time.privacy.row.leadsSee'
              : 'time.privacy.row.leadsTotals',
        ),
      ),
      if (v.approvalsEnabled)
        (LucideIcons.stamp, context.t('time.privacy.row.approvals')),
      if (v.workloadReports)
        (
          LucideIcons.chartColumn,
          context.t('time.privacy.row.workloadReports'),
        ),
      if (v.alerts)
        (LucideIcons.bellRing, context.t('time.privacy.row.alerts')),
      if (v.targetReminders)
        (LucideIcons.target, context.t('time.privacy.row.targetReminders')),
      if (v.arbzgHints)
        (LucideIcons.scale, context.t('time.privacy.row.arbzgHints')),
      if (v.lateEntryHintDays != null)
        (
          LucideIcons.clockAlert,
          context.t('time.privacy.row.lateEntry', count: v.lateEntryHintDays),
        ),
      if (v.foreignChangesRecorded)
        (LucideIcons.history, context.t('time.privacy.row.foreignChanges')),
      (
        LucideIcons.timer,
        context.t(
          v.timerEventsRecorded
              ? 'time.privacy.row.timerRecorded'
              : 'time.privacy.row.timerNotRecorded',
        ),
      ),
      if (v.entryCreationRecorded)
        (LucideIcons.filePlus, context.t('time.privacy.row.entryCreation')),
      (
        LucideIcons.trash2,
        v.entryRetentionMonths > 0
            ? context.t(
                'time.privacy.row.entryRetention',
                count: v.entryRetentionMonths,
              )
            : context.t('time.privacy.row.entryKept'),
      ),
      if (v.descriptionRetentionMonths > 0)
        (
          LucideIcons.eraser,
          context.t(
            'time.privacy.row.descriptionRetention',
            count: v.descriptionRetentionMonths,
          ),
        ),
      (
        LucideIcons.calendarClock,
        context.t('time.privacy.row.maxDaysBack', count: v.maxDaysBack),
      ),
    ];
    final absences = v.absences;
    final absenceRows = absences == null
        ? const <(IconData, String)>[]
        : <(IconData, String)>[
            (
              LucideIcons.usersRound,
              context.t(
                'time.privacy.absence.calendar.${absences.calendar.name}',
              ),
            ),
            (
              LucideIcons.users,
              context.t(
                absences.leadsSeeSpans
                    ? 'time.privacy.absence.leadsSee'
                    : 'time.privacy.absence.leadsDoNot',
              ),
            ),
            if (absences.bandForPlanners)
              (LucideIcons.chartColumn, context.t('time.privacy.absence.band')),
            (
              LucideIcons.shieldCheck,
              context.t(
                absences.keepersNamed
                    ? 'time.privacy.absence.keepersNamed'
                    : 'time.privacy.absence.keepersAdmins',
              ),
            ),
            // HIN-119: the report on balances, the rate, and how long a sick
            // day keeps saying "sick".
            if (absences.report)
              (LucideIcons.chartPie, context.t('time.privacy.absence.report')),
            if (absences.report && absences.leadsSeeSpans)
              (
                LucideIcons.usersRound,
                context.t('time.privacy.absence.reportLeads'),
              ),
            if (absences.rateForKeepers)
              (LucideIcons.percent, context.t('time.privacy.absence.rate')),
            if (absences.sickDetailMonths > 0)
              (
                LucideIcons.eraser,
                context.t(
                  'time.privacy.absence.sickDetail',
                  variables: {'count': absences.sickDetailMonths},
                ),
              ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, sentence) in rows) _sentence(icon, sentence),
        if (absenceRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Heading(text: context.t('time.privacy.absence.heading')),
          const SizedBox(height: 4),
          for (final (icon, sentence) in absenceRows) _sentence(icon, sentence),
        ],
      ],
    );
  }

  Widget _sentence(IconData icon, String sentence) =>
      _sentenceRow(icon, sentence);

  static Widget _sentenceRow(IconData icon, String sentence) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: AppColors.inkSoft),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            sentence,
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.45,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

/// "On this device": what of the timer shows outside the app here, and what
/// the device keeps for it.
///
/// Next to "who sees" on purpose: a lock screen is somebody seeing it too,
/// and these copies are the one part of the time data that never reaches the
/// server.
class TimerSurfacesDevicePanel extends StatelessWidget {
  const TimerSurfacesDevicePanel({
    super.key,
    required this.prefs,
    required this.platform,
  });

  final TimerSurfacePrefsCubit prefs;
  final SurfacePlatform platform;

  void _openSettings(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).maybePop();
    router?.go('/settings?section=time');
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TimerSurfacePrefsCubit, TimerSurfacePrefs>(
        bloc: prefs,
        builder: (context, state) {
          bool on(TimerSurfaceOption option) =>
              state.consented &&
              option.availableOn(platform) &&
              option.read(state);
          final active = <(IconData, String)>[
            if (on(TimerSurfaceOption.phaseEnd))
              (LucideIcons.bellRing, 'time.surface.device.phaseEnd'),
            if (on(TimerSurfaceOption.running))
              (
                LucideIcons.timer,
                'time.surface.device.running${surfacePlace(platform)}',
              ),
            if (on(TimerSurfaceOption.titleClock))
              (LucideIcons.panelTop, 'time.surface.device.titleClock'),
            if (on(TimerSurfaceOption.running) &&
                on(TimerSurfaceOption.keepRunning))
              (LucideIcons.panelTopClose, 'time.surface.device.keepRunning'),
            // The shortcuts hear their two combinations and nothing else; the
            // panel says so, because "shortcuts from any app" sounds like more.
            if (on(TimerSurfaceOption.hotkeys))
              (LucideIcons.keyboard, 'time.surface.device.hotkeys'),
          ];
          final details =
              on(TimerSurfaceOption.running) &&
              (on(TimerSurfaceOption.details) ||
                  on(TimerSurfaceOption.lockDetails));
          final rows = <(IconData, String)>[
            if (active.isEmpty)
              (LucideIcons.bellOff, 'time.surface.device.off')
            else ...[
              ...active,
              (
                details ? LucideIcons.textSearch : LucideIcons.eyeOff,
                details
                    ? 'time.surface.device.detailsOn'
                    : 'time.surface.device.detailsOff',
              ),
              (
                LucideIcons.hardDrive,
                details
                    ? 'time.surface.device.copyDetails'
                    : 'time.surface.device.copy',
              ),
              (LucideIcons.eraser, 'time.surface.device.vanish'),
            ],
            (LucideIcons.smartphone, 'time.surface.device.stored'),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (icon, key) in rows)
                TimeVisibilityPanel._sentenceRow(icon, context.t(key)),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: GhostButton(
                  icon: LucideIcons.settings,
                  label: context.t('time.surface.device.settings'),
                  onPressed: () => _openSettings(context),
                ),
              ),
            ],
          );
        },
      );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: AppType.caption,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: AppColors.inkFaint,
    ),
  );
}
