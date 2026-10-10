import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/repositories/org_settings_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/settings_split.dart';
import '../admin/admin_cards.dart';
import '../admin/admin_form_helpers.dart' show AdminNote;
import '../admin/sections/admin_audit_section.dart';
import '../admin/sections/audit_log_cubit.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import 'holidays/holidays_screen.dart';
import 'org_link_card.dart';
import 'org_deadline_basis_card.dart';
import 'organization_cubit.dart';
import 'time_tracking/time_tracking_section.dart';
import '../../core/widgets/folded_hint.dart';
import '../../core/theme/app_type.dart';

/// Organisation (HIN-129): what an organisation admin keeps for the whole
/// organisation, apart from the platform's admin area.
///
/// The time-tracking policies with their catalogues (tags, holidays, lock
/// exceptions, corrections, backfill grants), absence management, the privacy
/// notice and, while project templates are on, the default basis of new
/// relative deadlines. Nothing here opens a project, a team or anybody's
/// content: the role manages rules, not what people wrote.
///
/// The router lets only organisation admins in; the server answers anyone else
/// with 403 `error.org.adminOnly` all the same.
class OrganizationScreen extends StatelessWidget {
  const OrganizationScreen({super.key, this.initialSection});

  /// The section a wide window opens on, by its name (`?section=capture`).
  /// Unknown names, and those of entries that lead to a page of their own,
  /// fall back to the first section. A phone shows every card anyway.
  final String? initialSection;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        OrganizationCubit(context.read<OrgSettingsRepository>())..load(),
    child: OrganizationView(initialSection: initialSection),
  );
}

class OrganizationView extends StatefulWidget {
  const OrganizationView({super.key, this.initialSection});

  final String? initialSection;

  @override
  State<OrganizationView> createState() => _OrganizationViewState();
}

class _OrganizationViewState extends State<OrganizationView> {
  /// The section open on a wide window. Held here, above the time-tracking
  /// section, because a save rebuilds that one under a new key; the draft
  /// itself lives in the cubit's settings, so moving between sections loses
  /// nothing that was not saved yet.
  late OrgSection _section = OrgSection.values.firstWhere(
    (s) => s.name == widget.initialSection,
    orElse: () => OrgSection.values.first,
  );

  void _select(OrgSection section) {
    setState(() => _section = section);
  }

  Future<void> _save(BuildContext context, {required bool templates}) async {
    final error = await context.read<OrganizationCubit>().save(
      templates: templates,
    );
    if (!context.mounted) return;
    if (error != null) {
      showGlassErrorToast(context, context.t(error));
      return;
    }
    // /meta reports the module flag and the deadline basis; re-read it so the
    // switch just flipped shows up behind the page, not after a restart.
    context.read<AppConfigBloc>().add(const MetaRefreshRequested(force: true));
    // And the time rules, so a lock date that just moved greys out the frozen
    // days without waiting for the next sign-in.
    unawaited(context.read<TimePolicyCubit>().refresh());
    showGlassToast(
      context,
      context.t('admin.saved'),
      kind: GlassToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final templates = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.projectTemplates ?? false,
    );
    final state = context.watch<OrganizationCubit>().state;
    final settings = state.settings;
    return ResponsiveBuilder(
      builder: (context, size) {
        final compact = size == LayoutSize.compact;
        return PageChrome(
          // On a wide window the bar names the open section, as in the admin
          // area; the rail carries the page's name.
          title: compact || settings == null
              ? context.t('org.title')
              : context.t(_section.labelKey),
          actions: [
            // The log saves nothing; Save would only puzzle there.
            if (settings != null && (compact || _section.savable))
              PageAction(
                icon: LucideIcons.save,
                label: context.t('common.save'),
                onTap: (_) => unawaited(_save(context, templates: templates)),
                primary: true,
                busy: state.saving,
              ),
          ],
          child: _body(context, state, templates: templates, compact: compact),
        );
      },
    );
  }

  /// The organisation's own cards, by the names the rail looks them up by.
  Map<String, Widget> _ownCards(
    BuildContext context,
    OrganizationState state, {
    required bool templates,
  }) {
    final settings = state.settings!;
    return {
      if (templates)
        'deadlines': OrgDeadlineBasisCard(
          value: state.basis,
          // Known only while the organisation follows it: then what is in
          // force is the platform's answer.
          platformDefault: settings.defaultDeadlineBasis == null
              ? settings.effectiveDeadlineBasis
              : null,
          onChanged: context.read<OrganizationCubit>().setBasis,
        ),
      'audit': const OrgLinkCard(
        icon: LucideIcons.history,
        titleKey: 'org.audit.title',
        hintKey: 'org.audit.hint',
        openKey: 'org.audit.open',
        route: '/organization/audit',
      ),
    };
  }

  Widget _body(
    BuildContext context,
    OrganizationState state, {
    required bool templates,
    required bool compact,
  }) {
    final settings = state.settings;
    if (settings == null) {
      if (state.status != OrganizationStatus.failure) {
        return const Center(child: HiveLoader());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HiveEmptyState(
            title: context.t('org.title'),
            message: context.t(state.errorKey ?? 'errors.unexpected'),
            action: OutlinedButton(
              onPressed: () =>
                  unawaited(context.read<OrganizationCubit>().load()),
              child: Text(context.t('common.retry')),
            ),
          ),
        ),
      );
    }
    final own = _ownCards(context, state, templates: templates);
    final section = OrgTimeTrackingSection(
      // A save hands back a fresh block; a new key gives the controls that
      // hold their own text the values the server kept.
      key: ObjectKey(settings),
      timeTracking: settings.timeTracking,
      layout: compact
          ? (context, cards) => _CompactCards(own: own, timeTracking: cards)
          : (context, cards) {
              final all = {...own, ...cards};
              final available = [
                for (final s in OrgSection.values)
                  if (s.cards.any(all.containsKey)) s,
              ];
              // A section that went away with the module (or with project
              // templates) gives way to the first one rather than an empty
              // pane.
              final open = available.contains(_section)
                  ? _section
                  : available.first;
              if (open != _section) {
                // The bar's title is read from the section held here.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _section = open);
                });
              }
              return _WideOrganization(
                sections: available,
                open: open,
                cards: all,
                onSelect: _select,
              );
            },
    );
    if (!compact) return section;
    // The iOS numeric keypad has no Done key: tap outside a field or drag the
    // page to put it away, as in the admin area these forms come from.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          context.pageGutter,
          context.topGutter + 14,
          context.pageGutter,
          context.bottomGutter + 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FoldedHint(
              context.t('org.subtitle'),
              style: TextStyle(
                fontSize: AppType.label,
                height: 1.4,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 16),
            section,
          ],
        ),
      ),
    );
  }
}

/// The phone's page: every card, the organisation's own first, then the
/// time-tracking ones under the note that is about them alone.
class _CompactCards extends StatelessWidget {
  const _CompactCards({required this.own, required this.timeTracking});

  final Map<String, Widget> own;
  final Map<String, Widget> timeTracking;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminCards(cards: own),
      const SizedBox(height: 28),
      AdminCards(
        note: AdminNote(text: context.t('admin.timeTracking.hint')),
        cards: timeTracking,
      ),
    ],
  );
}

/// The sections of the Organisation page on a wide window (HIN-110), in the
/// rail's order. Each names the cards it shows.
///
/// The first is where the page opens: the module switch, which every other
/// time-tracking section depends on.
enum OrgSection {
  module('admin.timeTracking.moduleTitle', LucideIcons.timer, _timeGroup, [
    'module',
  ]),
  capture(
    'admin.timeTracking.captureTitle',
    LucideIcons.clipboardList,
    _timeGroup,
    ['capture'],
  ),
  // The spans and days opened after the fact, and the requests that ask for
  // them: all part of the module, so they come and go with it.
  corrections('org.nav.corrections', LucideIcons.lockOpen, _timeGroup, [
    'lockExceptions',
    'corrections',
    'backfillGrants',
  ]),
  tags('admin.timeTracking.tagsTitle', LucideIcons.tag, _timeGroup, ['tags']),
  visibility(
    'admin.timeTracking.visibilityTitle',
    LucideIcons.eye,
    _timeGroup,
    ['visibility'],
  ),
  reports(
    'admin.timeTracking.reportsTitle',
    LucideIcons.chartLine,
    _timeGroup,
    ['reports'],
  ),
  billing(
    'admin.timeTracking.billingTitle',
    LucideIcons.receiptText,
    _timeGroup,
    ['billing'],
  ),
  privacy(
    'admin.timeTracking.privacyTitle',
    LucideIcons.shieldCheck,
    _timeGroup,
    ['privacy'],
  ),
  absences(
    'admin.absence.enabledTitle',
    LucideIcons.calendarOff,
    _absenceGroup,
    ['absenceManagement'],
  ),
  holidays(
    'availability.admin.cardTitle',
    LucideIcons.calendarHeart,
    _absenceGroup,
    ['holidays'],
  ),
  deadlines('org.nav.deadlines', LucideIcons.calendarClock, _generalGroup, [
    'deadlines',
  ]),
  // In the pane like every other section, as the admin area's log is; the
  // phone opens it as a page of its own through the card.
  audit('org.audit.title', LucideIcons.history, _generalGroup, ['audit']);

  const OrgSection(this.labelKey, this.icon, this.groupKey, this.cards);

  final String labelKey;
  final IconData icon;
  final String groupKey;

  /// The cards it shows, by the names the page and the time-tracking section
  /// give them. A section none of whose cards is there is not listed.
  final List<String> cards;

  bool get isTimeTracking => groupKey != _generalGroup;

  /// Whether the page's Save means anything here. The log and the holidays
  /// keep their own state and save each change as it is made.
  bool get savable => this != audit && this != holidays;
}

const String _timeGroup = 'nav.time';
const String _absenceGroup = 'absence.view.title';
const String _generalGroup = 'admin.navGeneral';

/// The rail beside the one section that is open, in one readable column.
class _WideOrganization extends StatelessWidget {
  const _WideOrganization({
    required this.sections,
    required this.open,
    required this.cards,
    required this.onSelect,
  });

  final List<OrgSection> sections;
  final OrgSection open;
  final Map<String, Widget> cards;
  final ValueChanged<OrgSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final name in open.cards)
        if (cards[name] != null) cards[name]!,
    ];
    return SettingsSplitLayout<OrgSection>(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRailHeader(title: context.t('org.title')),
          const SizedBox(height: 4),
          // The page's introduction, once: it says what the role sees, which
          // holds for every section. Folded to a line the reader can open.
          FoldedHint(
            context.t('org.subtitle'),
            title: context.t('org.title'),
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.25,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
      entries: [
        for (final s in sections)
          SettingsNavEntry(
            id: s,
            icon: s.icon,
            label: context.t(s.labelKey),
            group: context.t(s.groupKey),
          ),
      ],
      selected: open,
      onSelect: onSelect,
      // The log owns its scroll and pagination and takes the pane, as in the
      // admin area.
      bodyScrolls: open != OrgSection.audit,
      bodyMaxWidth: open == OrgSection.audit
          ? double.infinity
          : SettingsSplitLayout.formWidth,
      body: open == OrgSection.audit
          ? BlocProvider(
              create: (context) => AuditLogCubit.organization(
                context.read<OrgSettingsRepository>(),
              ),
              child: const AdminAuditSection(titleKey: 'org.audit.title'),
            )
          // In the pane like the log, so the rail stays beside it.
          : open == OrgSection.holidays
          ? const OrgHolidaysScreen(embedded: true)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // What holds for every policy below: each may stay empty and then
                // follows the server's environment.
                if (open.isTimeTracking) ...[
                  AdminNote(text: context.t('admin.timeTracking.hint')),
                  const SizedBox(height: 16),
                ],
                for (final (i, card) in shown.indexed) ...[
                  if (i > 0) const SizedBox(height: 16),
                  card,
                ],
              ],
            ),
    );
  }
}
