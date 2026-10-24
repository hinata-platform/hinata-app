part of 'user_management_widgets.dart';

/// The administration of one account: its facts, its roles, the lifecycle
/// actions, its history and the danger zone.
///
/// The body of the admin area's drawer, and the admin's part of a person's
/// profile (HIN-165), so both offer the same actions with the same safeguards.
/// [onDismiss] runs before an action that opens a dialog of its own: the
/// drawer closes; a profile page stays where it is and passes none.
class UserAdminSections extends StatelessWidget {
  const UserAdminSections({
    super.key,
    required this.user,
    required this.actions,
    this.onDismiss,
  });

  final AdminUser user;
  final UserActions actions;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final lastAdmin = actions.isLastActiveAdmin(u);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _factsGrid(context, u),
        if (u.inviteExpired) ...[
          const SizedBox(height: 18),
          _expiredBanner(context, u),
        ],
        const SizedBox(height: 22),
        // The roles, each with one line on what it grants: the
        // organisation role (HIN-129) and the moderation role (HIN-26) are
        // switches of their own, beside the platform role and independent
        // of it.
        _sectionLabel(context, context.t('admin.um.roles')),
        const SizedBox(height: 12),
        OrgAdminToggle(user: u, actions: actions),
        const SizedBox(height: 8),
        ModeratorToggle(user: u, actions: actions),
        const SizedBox(height: 22),
        _sectionLabel(context, context.t('admin.um.manage')),
        const SizedBox(height: 12),
        ..._manageActions(context, u, lastAdmin),
        const SizedBox(height: 22),
        _sectionLabel(context, context.t('admin.um.activity')),
        const SizedBox(height: 12),
        ..._timeline(context, u),
        const SizedBox(height: 22),
        _sectionLabel(context, context.t('admin.um.dangerZone')),
        const SizedBox(height: 12),
        _ActRow(
          icon: LucideIcons.trash2,
          title: context.t('admin.um.deleteThisUser'),
          subtitle: context.t('admin.um.deleteThisUserSub'),
          danger: true,
          enabled: !lastAdmin,
          disabledReason: context.t('admin.um.reasonLastAdmin'),
          onTap: () {
            onDismiss?.call();
            actions.openDelete([u.id]);
          },
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Row(
    children: [
      // Flexible: under large text a long label wraps instead of running
      // past the panel's edge.
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
  );

  Widget _factsGrid(BuildContext context, AdminUser u) {
    final twoFa = u.sso
        ? context.t('admin.um.viaIdp')
        : (u.twoFA ? context.t('admin.um.enabled') : context.t('admin.um.off'));
    Widget fact(IconData ic, String k, String v) => Expanded(
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
                Icon(ic, size: 13, color: AppColors.inkFaint),
                const SizedBox(width: 5),
                // Flexible: a narrow drawer or a large text size would push a
                // long label past the tile's edge.
                Flexible(
                  child: Text(
                    k,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              v,
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
    return Column(
      children: [
        Row(
          children: [
            fact(
              LucideIcons.briefcase,
              context.t('admin.um.fieldTitle'),
              u.title.isEmpty ? '—' : u.title,
            ),
            const SizedBox(width: 10),
            fact(
              LucideIcons.activity,
              context.t('admin.um.lastActive'),
              umRelTime(context, u.lastActive),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            fact(LucideIcons.shield, context.t('admin.um.twoFa'), twoFa),
            const SizedBox(width: 10),
            fact(
              LucideIcons.monitor,
              context.t('admin.um.sessions'),
              '${u.sessions}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _expiredBanner(BuildContext context, AdminUser u) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.mailWarning, size: 16, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.t(
              'admin.um.expiredBanner',
              variables: {
                'date': umPrettyDate(context, u.invitedAt),
                'name': u.name.split(' ').first,
              },
            ),
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.4,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _manageActions(
    BuildContext context,
    AdminUser u,
    bool lastAdmin,
  ) {
    final rows = <Widget>[];
    void close() => onDismiss?.call();

    if (u.status == UserStatus.invited) {
      rows.add(
        _ActRow(
          icon: LucideIcons.send,
          accent: true,
          title: context.t('admin.um.resendInvitation'),
          subtitle: context.t('admin.um.resendInvitationSub'),
          onTap: () {
            close();
            actions.openResend([u.id]);
          },
        ),
      );
    } else if (u.status == UserStatus.active) {
      rows.add(
        _ActRow(
          icon: LucideIcons.ban,
          title: context.t('admin.um.deactivateAccount'),
          subtitle: context.t('admin.um.deactivateAccountSub'),
          onTap: () {
            close();
            actions.openDeactivate([u.id]);
          },
        ),
      );
    } else if (u.suspended) {
      // Moderation decided it, and its reasons stay there (HIN-172); the
      // admin area only ends it, with a note.
      rows.add(
        _ActRow(
          icon: LucideIcons.lockOpen,
          success: true,
          title: context.t('admin.um.liftSuspension'),
          subtitle: context.t('admin.um.liftSuspensionRowSub'),
          onTap: () {
            close();
            actions.openLiftSuspension(u);
          },
        ),
      );
    } else if (u.status == UserStatus.pendingApproval) {
      rows.add(
        _ActRow(
          icon: LucideIcons.userCheck,
          success: true,
          title: context.t('admin.um.approve'),
          subtitle: context.t('admin.approvalHint'),
          onTap: () {
            close();
            actions.approve([u.id]);
          },
        ),
      );
    } else {
      rows.add(
        _ActRow(
          icon: LucideIcons.circleCheck,
          success: true,
          title: context.t('admin.um.reactivateAccount'),
          subtitle: context.t('admin.um.reactivateAccountSub'),
          onTap: () {
            close();
            actions.activate([u.id]);
          },
        ),
      );
    }

    final isAdmin = u.role == AdminRole.admin;
    rows.add(
      _ActRow(
        icon: isAdmin ? LucideIcons.shieldMinus : LucideIcons.shieldCheck,
        title: context.t(
          isAdmin ? 'admin.um.revokeAdminRights' : 'admin.um.promoteToAdmin',
        ),
        subtitle: context.t(
          isAdmin
              ? 'admin.um.revokeAdminRightsSub'
              : 'admin.um.promoteToAdminSub',
        ),
        enabled: isAdmin ? !lastAdmin : u.status != UserStatus.invited,
        disabledReason: context.t(
          isAdmin ? 'admin.um.reasonLastAdmin' : 'admin.um.reasonPendingInvite',
        ),
        onTap: () {
          close();
          actions.setRole([u.id], isAdmin ? AdminRole.user : AdminRole.admin);
        },
      ),
    );

    if (u.status != UserStatus.invited) {
      rows.add(
        _ActRow(
          icon: LucideIcons.keyRound,
          title: context.t(
            u.sso
                ? 'admin.um.passwordManagedByIdp'
                : 'admin.um.sendPasswordReset',
          ),
          subtitle: u.sso
              ? context.t('admin.um.passwordManagedByIdpSub')
              : context.t(
                  'admin.um.sendPasswordResetSub',
                  variables: {'email': u.email},
                ),
          enabled: !u.sso,
          disabledReason: context.t('admin.um.reasonSsoManaged'),
          onTap: () {
            close();
            actions.openReset([u.id]);
          },
        ),
      );
      rows.add(
        _ActRow(
          icon: LucideIcons.logOut,
          title: context.t('admin.um.revokeAllSessions'),
          subtitle: context.t(
            'admin.um.revokeAllSessionsSub',
            variables: {'n': '${u.sessions}'},
          ),
          enabled: u.sessions > 0,
          disabledReason: context.t('admin.um.reasonNoSessions'),
          onTap: () {
            close();
            actions.revokeSessions([u.id]);
          },
        ),
      );
    }
    // Only an account that is bound has anything to undo; on an instance
    // without SSO the row never shows.
    if (u.ssoLinked) {
      rows.add(
        _ActRow(
          icon: LucideIcons.unlink,
          title: context.t('admin.um.unlinkSso'),
          subtitle: context.t('admin.um.unlinkSsoSub'),
          onTap: () {
            close();
            actions.openUnlinkSso(u);
          },
        ),
      );
    }

    return _withGaps(rows);
  }

  List<Widget> _timeline(BuildContext context, AdminUser u) {
    final entries = <(String, String)>[];
    if (u.lastActive != null) {
      entries.add((
        context.t('admin.um.tlLastActive'),
        umRelTime(context, u.lastActive),
      ));
    }
    if (u.status == UserStatus.invited) {
      final inviter = actions.nameById(u.invitedBy);
      entries.add((
        u.inviteExpired
            ? context.t('admin.um.tlInviteExpired')
            : (inviter != null
                  ? context.t(
                      'admin.um.tlInvitedBy',
                      variables: {'name': inviter.split(' ').first},
                    )
                  : context.t('admin.um.tlInvited')),
        umPrettyDate(context, u.invitedAt),
      ));
    } else if (u.joinedAt != null) {
      entries.add((
        context.t('admin.um.tlJoined'),
        umPrettyDate(context, u.joinedAt),
      ));
    }
    entries.add((
      context.t(
        'admin.um.tlCreatedVia',
        variables: {'origin': originLabel(context, u.origin)},
      ),
      umPrettyDate(context, u.joinedAt ?? u.invitedAt),
    ));

    return [
      for (var i = 0; i < entries.length; i++)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (i != entries.length - 1)
                    Expanded(
                      child: Container(width: 1.5, color: AppColors.hairline),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entries[i].$1,
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        entries[i].$2,
                        style: TextStyle(
                          fontSize: AppType.caption,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _withGaps(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 8));
      out.add(rows[i]);
    }
    return out;
  }
}
