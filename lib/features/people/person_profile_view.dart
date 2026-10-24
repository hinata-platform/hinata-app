import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/person_profile.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_type.dart';
import '../../core/theme/hue_colors.dart' show colorFromHex;
import '../../core/util/dates.dart';
import '../../core/util/zone_clock.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/user_pronouns.dart';
import '../teams/team_widgets.dart' show teamIcon;

/// What a person's profile does when somebody acts on it. The view only says
/// which; the page decides how.
class PersonProfileActions {
  const PersonProfileActions({
    required this.openIssues,
    required this.openTeam,
    required this.openProject,
    this.writeEmail,
    this.toggleBlock,
    this.report,
    this.suspend,
    this.liftSuspension,
    this.close,
  });

  final VoidCallback openIssues;
  final void Function(String teamId) openTeam;
  final void Function(String projectId) openProject;

  /// Null where no address is known to the reader.
  final VoidCallback? writeEmail;

  /// Blocks the person, or lifts the block (HIN-168). Null on one's own
  /// profile and where the server does not know blocking.
  final VoidCallback? toggleBlock;

  /// Reports the person (HIN-173), beside the row on a wide window. Null
  /// where blocking is, and on a removed profile.
  final void Function(Rect? anchor)? report;

  /// Opens a case to suspend the person (HIN-174). Null unless the reader
  /// moderates, and never on one's own profile or an administrator's.
  final VoidCallback? suspend;

  /// Lifts the person's suspension, with a reason. Null unless the reader
  /// moderates and the account is suspended.
  final VoidCallback? liftSuspension;

  /// The side panel's close button; null on a page, which has its back button.
  final VoidCallback? close;
}

/// A person's profile (HIN-165): who they are, what the reader shares with
/// them, where their day stands, and what to do next.
///
/// Dumb: renders [profile] and forwards taps through [actions]. [admin] is the
/// account's administration, only ever passed for a reader who holds the
/// platform role. [padding] carries the page's gutters, including the bottom
/// inset, so the last row scrolls clear of the navigation.
class PersonProfileView extends StatelessWidget {
  const PersonProfileView({
    super.key,
    required this.profile,
    required this.actions,
    required this.clockReady,
    required this.padding,
    this.blocked = false,
    this.admin,
    this.now,
  });

  final PersonProfile profile;
  final PersonProfileActions actions;
  final bool clockReady;
  final EdgeInsets padding;

  /// Whether the reader blocks this person, which turns the privacy row into
  /// lifting it.
  final bool blocked;
  final Widget? admin;

  /// The moment the local time is told for; now when null (tests pin it).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final teams = p.sharedTeams;
    final projects = p.sharedProjects;
    return ListView(
      padding: padding,
      children: [
        _Header(profile: p, onClose: actions.close),
        const SizedBox(height: 18),
        _Facts(profile: p, clockReady: clockReady, now: now),
        const SizedBox(height: 22),
        _SectionLabel(context.t('people.actions')),
        const SizedBox(height: 8),
        _LinkRow(
          icon: LucideIcons.circleCheckBig,
          label: context.t(p.self ? 'people.issuesSelf' : 'people.issues'),
          onTap: actions.openIssues,
        ),
        if (actions.writeEmail != null)
          _LinkRow(
            icon: LucideIcons.mail,
            label: context.t('people.email'),
            detail: p.email,
            onTap: actions.writeEmail!,
          ),
        if (teams.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel(
            context.t(p.self ? 'people.ownTeams' : 'people.sharedTeams'),
          ),
          const SizedBox(height: 8),
          for (final team in teams)
            _LinkRow(
              icon: teamIcon(team.icon ?? 'hexagon'),
              label: team.name,
              detail: team.key,
              onTap: () => actions.openTeam(team.id),
            ),
        ],
        if (projects.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel(
            context.t(p.self ? 'people.ownProjects' : 'people.sharedProjects'),
          ),
          const SizedBox(height: 8),
          for (final project in projects)
            _LinkRow(
              leading: _ProjectKey(project: project),
              label: project.name,
              onTap: () => actions.openProject(project.id),
            ),
        ],
        if (teams.isEmpty && projects.isEmpty && !p.self) ...[
          const SizedBox(height: 22),
          Text(
            context.t('people.noneShared'),
            style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
          ),
        ],
        if (actions.toggleBlock != null || actions.report != null) ...[
          const SizedBox(height: 22),
          _SectionLabel(context.t('blocks.profile.section')),
          const SizedBox(height: 8),
          if (actions.toggleBlock != null)
            _LinkRow(
              icon: blocked ? LucideIcons.userCheck : LucideIcons.userX,
              label: context.t(
                blocked ? 'blocks.profile.unblock' : 'blocks.profile.block',
              ),
              detail: blocked
                  ? context.t(
                      'blocks.profile.unblockDetail',
                      variables: {'name': p.displayName},
                    )
                  : context.t('blocks.profile.blockDetail'),
              onTap: actions.toggleBlock!,
            ),
          if (actions.report case final report?)
            Builder(
              builder: (rowContext) => _LinkRow(
                icon: LucideIcons.flag,
                label: context.t('moderation.report.action'),
                detail: context.t(
                  'moderation.report.personDetail',
                  variables: {'name': p.displayName},
                ),
                onTap: () => report(_rectOf(rowContext)),
              ),
            ),
        ],
        if (actions.suspend != null || actions.liftSuspension != null) ...[
          const SizedBox(height: 22),
          _SectionLabel(context.t('moderation.queue.title')),
          const SizedBox(height: 8),
          if (actions.liftSuspension case final lift?)
            _LinkRow(
              icon: LucideIcons.userCheck,
              label: context.t('moderation.suspension.lift'),
              detail: p.suspension?.until == null
                  ? context.t('moderation.suspension.indefinite')
                  : context.t(
                      'moderation.suspension.until',
                      variables: {
                        'date': recentMoment(context, p.suspension!.until!),
                      },
                    ),
              onTap: lift,
            )
          else if (actions.suspend case final suspend?)
            _LinkRow(
              icon: LucideIcons.userX,
              label: context.t('moderation.suspension.suspend'),
              detail: context.t('moderation.suspension.suspendDetail'),
              onTap: suspend,
            ),
        ],
        if (admin != null) ...[
          const SizedBox(height: 28),
          _SectionLabel(context.t('people.admin')),
          const SizedBox(height: 14),
          admin!,
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile, this.onClose});

  final PersonProfile profile;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final badges = <String>[
      for (final role in p.roles)
        switch (role) {
          'ADMIN' => context.t('admin.um.roleAdmin'),
          'ORG_ADMIN' => context.t('admin.um.orgAdminTitle'),
          'MODERATOR' => context.t('people.role.moderator'),
          _ => context.t('people.role.member'),
        },
      if (!p.active) context.t('people.deactivated'),
      if (p.self) context.t('people.you'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HiveAvatar(name: p.displayName, imageUrl: p.avatarUrl, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Semantics(
                    header: true,
                    child: Text(
                      p.displayName,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: AppType.heading,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '@${p.username}',
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: AppType.label,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      PronounsLabel(
                        pronouns: p.pronouns,
                        fontSize: AppType.label,
                        leadingGap: 8,
                      ),
                    ],
                  ),
                  if (p.title != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.title!,
                      style: TextStyle(
                        fontSize: AppType.body,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: context.t('common.close'),
                onPressed: onClose,
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
              ),
          ],
        ),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final badge in badges) _Badge(badge)],
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: AppType.caption,
        fontWeight: FontWeight.w700,
        color: AppColors.inkSoft,
      ),
    ),
  );
}

/// The person's local time and, where the reader may know it, today's absence.
class _Facts extends StatelessWidget {
  const _Facts({required this.profile, required this.clockReady, this.now});

  final PersonProfile profile;
  final bool clockReady;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final zone = profile.timezone;
    final wall = clockReady
        ? ZoneClock.wallClock(zone, now ?? DateTime.now())
        : null;
    final zoneName = zone.replaceAll('_', ' ');
    final clock = wall == null
        ? zoneName
        : context.t(
            'people.localTimeValue',
            variables: {
              'time': DateFormat.Hm(locale).format(wall),
              'zone': zoneName,
            },
          );
    final absence = profile.absenceToday;
    final tiles = <Widget>[
      _Fact(
        icon: LucideIcons.clock,
        label: context.t('people.localTime'),
        value: clock,
      ),
      if (absence != null)
        _Fact(
          icon: LucideIcons.calendarOff,
          label: context.t('people.today'),
          value: _absenceText(context, absence, locale),
        ),
    ];
    // Side by side where there is room, one above the other where the text
    // has grown or the panel is narrow.
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth < 360 * scale || tiles.length < 2;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                tiles[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 10),
              Expanded(child: tiles[1]),
            ],
          ),
        );
      },
    );
  }

  String _absenceText(BuildContext context, AbsenceToday a, String locale) {
    final type = context.t(switch (a.type.toUpperCase()) {
      'VACATION' => 'absence.type.vacation',
      'SICK' => 'absence.type.sick',
      _ => 'absence.type.other',
    });
    if (a.halfDay) {
      return context.t('people.absentHalfDay', variables: {'type': type});
    }
    if (a.to == a.from) return type;
    return context.t(
      'people.absentUntil',
      variables: {'type': type, 'date': DateFormat.MMMEd(locale).format(a.to)},
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.inkFaint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: AppType.label,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppColors.hairline)),
      ],
    ),
  );
}

/// One way onward: a team, a project, the person's issues, an e-mail.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.detail,
  });

  final IconData? icon;
  final Widget? leading;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              leading ??
                  Icon(
                    icon ?? LucideIcons.arrowRight,
                    size: 18,
                    color: AppColors.inkSoft,
                  ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: TextStyle(
                          fontSize: AppType.caption,
                          color: AppColors.inkSoft,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A project's key in its colour, as the project list shows it.
class _ProjectKey extends StatelessWidget {
  const _ProjectKey({required this.project});
  final SharedProject project;

  @override
  Widget build(BuildContext context) {
    final color = project.color == null
        ? AppColors.stBacklog
        : colorFromHex(project.color!);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            project.key ?? project.name.characters.first.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppType.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Where [context]'s box stands on screen, for a popover to hang off it.
Rect? _rectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
