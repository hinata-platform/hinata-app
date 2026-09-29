import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/repositories/org_settings_repository.dart';
import '../../core/responsive/golden_columns.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../admin/admin_cards.dart';
import '../admin/admin_form_helpers.dart' show AdminNote;
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import 'org_link_card.dart';
import 'org_deadline_basis_card.dart';
import 'organization_cubit.dart';
import 'time_tracking/time_tracking_section.dart';

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
  const OrganizationScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        OrganizationCubit(context.read<OrgSettingsRepository>())..load(),
    child: const OrganizationView(),
  );
}

class OrganizationView extends StatelessWidget {
  const OrganizationView({super.key});

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
    return PageChrome(
      title: context.t('org.title'),
      contentMax: goldenContentMax,
      actions: [
        if (settings != null)
          PageAction(
            icon: LucideIcons.save,
            label: context.t('common.save'),
            onTap: (_) => unawaited(_save(context, templates: templates)),
            primary: true,
            busy: state.saving,
          ),
      ],
      child: _body(context, state, templates: templates),
    );
  }

  Widget _body(
    BuildContext context,
    OrganizationState state, {
    required bool templates,
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
            Text(
              context.t('org.subtitle'),
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 16),
            OrgTimeTrackingSection(
              // A save hands back a fresh block; a new key gives the controls
              // that hold their own text the values the server kept.
              key: ObjectKey(settings),
              timeTracking: settings.timeTracking,
              // The page owns the columns. The organisation's own cards come
              // first, then the time-tracking cards under the note that is
              // about them alone.
              layout: (context, cards) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminCards(
                    cards: {
                      if (templates)
                        'deadlines': OrgDeadlineBasisCard(
                          value: state.basis,
                          // Known only while the organisation follows it:
                          // then what is in force is the platform's answer.
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
                    },
                  ),
                  const SizedBox(height: 28),
                  AdminCards(
                    note: AdminNote(text: context.t('admin.timeTracking.hint')),
                    cards: cards,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
