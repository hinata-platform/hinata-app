import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/admin_user_models.dart';
import '../../sprint/modals/glass_modal.dart'
    show showGlassToast, GlassToastKind;
import 'user_management_cubit.dart';
import 'user_management_modals.dart';
import 'user_management_widgets.dart';

/// Every lifecycle action on an account, each behind the same confirmation,
/// toast and reload wherever it is offered.
///
/// The admin area's directory and a person's profile (HIN-165) both hand
/// these to [UserAdminSections]; what differs between them is only how they
/// learn about the people involved ([usersFor], [nameById],
/// [isLastActiveAdmin]) and what they reload afterwards ([reload]).
/// [openDrawer] and [clearSelection] are the directory's: the drawer it opens
/// on a row, and forgetting a bulk selection once the action is done. A
/// profile has neither.
UserActions buildUserActions(
  BuildContext context, {
  required UserManagementCubit users,
  required String? currentUserId,
  required bool Function(AdminUser u) isLastActiveAdmin,
  required String? Function(String? id) nameById,
  required List<AdminUser> Function(List<String> ids) usersFor,
  required Future<void> Function() reload,
  void Function(AdminUser u, UserActions actions)? openDrawer,
  VoidCallback? clearSelection,
}) {
  void toast(String key) {
    if (!context.mounted) return;
    showGlassToast(context, context.t(key), kind: GlassToastKind.success);
  }

  void toastError(String message) {
    if (!context.mounted) return;
    // context.t is idempotent for already-localized text but maps a fallback
    // key like 'errors.unexpected' (an ApiFailure.message) to real copy.
    showGlassToast(context, context.t(message), kind: GlassToastKind.error);
  }

  Future<void> run(
    Future<void> Function() action,
    String successKey, {
    bool clearSel = false,
  }) async {
    try {
      await action();
      if (clearSel) clearSelection?.call();
      toast(successKey);
      await reload();
    } on ApiFailure catch (failure) {
      toastError(failure.message);
    }
  }

  late final UserActions actions;
  return actions = UserActions(
    currentUserId: currentUserId,
    isLastActiveAdmin: isLastActiveAdmin,
    nameById: nameById,
    openDrawer: (u) => openDrawer?.call(u, actions),
    openEdit: (u) async {
      final result = await showEditModal(context, u);
      if (result == null) return;
      await run(
        () => users.updateDetails(
          u.id,
          displayName: result.name,
          title: result.title,
          email: result.email,
        ),
        'admin.um.toastProfileUpdated',
      );
    },
    activate: (ids) => run(
      () => users.setStatus(ids, UserStatus.active),
      ids.length == 1
          ? 'admin.um.toastActivated'
          : 'admin.um.toastActivatedMany',
      clearSel: true,
    ),
    approve: (ids) =>
        run(() => users.approve(ids), 'admin.um.approved', clearSel: true),
    openDeactivate: (ids) async {
      if (!await showDeactivateModal(context, usersFor(ids))) return;
      await run(
        () => users.setStatus(ids, UserStatus.disabled),
        'admin.um.toastDeactivated',
        clearSel: true,
      );
    },
    setRole: (ids, role) => run(
      () => users.setRole(ids, role),
      role == AdminRole.admin
          ? 'admin.um.toastPromoted'
          : 'admin.um.toastDemoted',
      clearSel: true,
    ),
    setOrgAdmin: (ids, orgAdmin) async {
      final involved = usersFor(ids);
      if (!await confirmOrgAdminChange(context, involved, grant: orgAdmin)) {
        return false;
      }
      if (!context.mounted) return false;
      try {
        await users.setOrgAdmin(ids, orgAdmin);
      } on ApiFailure catch (failure) {
        toastError(failure.message);
        return false;
      }
      clearSelection?.call();
      toast(
        orgAdmin
            ? 'admin.um.toastOrgAdminGranted'
            : 'admin.um.toastOrgAdminRevoked',
      );
      await reload();
      return true;
    },
    setModerator: (ids, moderator) async {
      final involved = usersFor(ids);
      if (!await confirmModeratorChange(context, involved, grant: moderator)) {
        return false;
      }
      if (!context.mounted) return false;
      try {
        await users.setModerator(ids, moderator);
      } on ApiFailure catch (failure) {
        toastError(failure.message);
        return false;
      }
      clearSelection?.call();
      toast(
        moderator
            ? 'admin.um.toastModeratorGranted'
            : 'admin.um.toastModeratorRevoked',
      );
      await reload();
      return true;
    },
    openDemote: (ids) async {
      if (!await showRevokeAdminModal(context, usersFor(ids))) return;
      await run(
        () => users.setRole(ids, AdminRole.user),
        'admin.um.toastDemoted',
        clearSel: true,
      );
    },
    openResend: (ids) async {
      if (!await showResendModal(context, usersFor(ids))) return;
      await run(
        () => users.resendInvites(ids),
        'admin.um.toastInviteResent',
        clearSel: true,
      );
    },
    openReset: (ids) async {
      if (!await showResetModal(context, usersFor(ids))) return;
      await run(
        () => users.sendPasswordReset(ids),
        'admin.um.toastResetSent',
        clearSel: true,
      );
    },
    revokeSessions: (ids) => run(
      () => users.revokeSessions(ids),
      'admin.um.toastSessionsRevoked',
      clearSel: true,
    ),
    openUnlinkSso: (u) async {
      if (!await showUnlinkSsoModal(context, u)) return;
      await run(() => users.unlinkSso(u.id), 'admin.um.toastSsoUnlinked');
    },
    openDelete: (ids) async {
      if (!await showDeleteModal(context, usersFor(ids))) return;
      await run(
        () => users.delete(ids),
        'admin.um.toastDeleted',
        clearSel: true,
      );
    },
  );
}
