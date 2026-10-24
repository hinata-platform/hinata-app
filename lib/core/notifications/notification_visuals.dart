import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// Leading icon + tint for a notification type. Cases match the server's
/// `Notification.Type` enum; the loose legacy tokens are kept as fallbacks.
(IconData, Color) notificationVisual(String type) => switch (type
    .toUpperCase()) {
  'MENTION' => (LucideIcons.atSign, AppColors.stReview),
  'ISSUE_ASSIGNED' ||
  'ASSIGN' ||
  'ASSIGNED' ||
  'ASSIGNMENT' => (LucideIcons.userCheck, AppColors.stTodo),
  'ISSUE_COMMENTED' ||
  'COMMENT' => (LucideIcons.messageSquare, AppColors.stProgress),
  'COMMENT_REPLY' || 'REPLY' => (LucideIcons.reply, AppColors.stReview),
  'ISSUE_UPDATED' => (LucideIcons.refreshCw, AppColors.accentBlue),
  'ISSUE_INGESTED' => (LucideIcons.inbox, AppColors.accentTeal),
  'SPRINT_STARTED' ||
  'SPRINT_COMPLETED' => (LucideIcons.goal, AppColors.accentPurple),
  'ISSUE_DUE_SOON' ||
  'DUE' ||
  'DEADLINE' => (LucideIcons.calendarDays, AppColors.priHigh),
  'DIGEST' => (LucideIcons.newspaper, AppColors.accentBlue),
  'SECURITY_ALERT' => (LucideIcons.shieldAlert, AppColors.priHigh),
  'TEAM_ADDED' ||
  'TEAM_ROLE_CHANGED' ||
  'TEAM_REMOVED' => (LucideIcons.usersRound, AppColors.accentBlue),
  'PROJECT_ADDED' => (LucideIcons.folderPlus, AppColors.accentPurple),
  'TIME_TARGET_REMINDER' => (LucideIcons.alarmClock, AppColors.accentBlue),
  'TIME_BUDGET_ALERT' => (LucideIcons.gauge, AppColors.priHigh),
  'TIME_ESTIMATE_REACHED' => (LucideIcons.hourglass, AppColors.priHigh),
  'TIME_TIMER_AUTO_STOPPED' => (LucideIcons.timerOff, AppColors.inkSoft),
  'TIMESHEET_SUBMITTED' ||
  'TIMESHEET_APPROVED' ||
  'TIMESHEET_REJECTED' ||
  'TIMESHEET_REOPENED' => (LucideIcons.clipboardCheck, AppColors.accentTeal),
  'TIME_CORRECTION_REQUESTED' ||
  'TIME_CORRECTION_ANSWERED' ||
  'TIME_BACKFILL_REQUESTED' => (LucideIcons.fileClock, AppColors.accentTeal),
  'TIME_ENTRY_SHARED' ||
  'TIME_SHARE_ACCEPTED' => (LucideIcons.userPlus, AppColors.accentTeal),
  'ACCOUNT_ACTIVATED' ||
  'ACCOUNT_DEACTIVATED' ||
  'ACCOUNT_ROLE_CHANGED' ||
  'ACCOUNT_DELETED' => (LucideIcons.shieldCheck, AppColors.inkSoft),
  'REVIEW' ||
  'REVIEW_REQUEST' => (LucideIcons.messageSquareText, AppColors.stReview),
  // Shift planning (HIN-27): every type of the module is one family; the
  // waiting list's three (HIN-162) say with their glyph what happened.
  'SHIFT_PROMOTED' => (LucideIcons.circleArrowUp, AppColors.accentTeal),
  'SHIFT_WAITLIST_SKIPPED' => (LucideIcons.skipForward, AppColors.accentTeal),
  'SHIFT_WAITLIST_EXPIRED' => (LucideIcons.timerOff, AppColors.accentTeal),
  final shift when shift.startsWith('SHIFT_') => (
    LucideIcons.calendarClock,
    AppColors.accentTeal,
  ),
  // Moderation, for members (HIN-173): a report looked at, a notice about
  // their own content, and a change to that notice.
  'MODERATION_DECISION' => (LucideIcons.circleCheck, AppColors.inkSoft),
  'MODERATION_NOTICE' => (LucideIcons.shieldAlert, AppColors.accentInk),
  'MODERATION_NOTICE_UPDATED' => (LucideIcons.rotateCcw, AppColors.accentInk),
  // For moderators (HIN-174): a new case, cases waiting long, an appeal, a
  // second person asked for, a word to the team; for admins, a warning.
  'MODERATION_CASE_OPENED' => (LucideIcons.flag, AppColors.accentInk),
  'MODERATION_CASE_OVERDUE' => (LucideIcons.alarmClock, AppColors.accentInk),
  'MODERATION_APPEAL_FILED' => (LucideIcons.rotateCcw, AppColors.accentInk),
  'MODERATION_CONFIRM_REQUESTED' => (
    LucideIcons.usersRound,
    AppColors.accentInk,
  ),
  'MODERATION_TEAM_NOTE' => (LucideIcons.info, AppColors.accentInk),
  'MODERATION_ADMIN_ALERT' => (LucideIcons.shield, AppColors.accentInk),
  _ => (LucideIcons.bell, AppColors.inkSoft),
};

/// Compact relative time ("now", "8m", "2h", "3d", "5w").
String? notificationTimeAgo(DateTime? time) {
  if (time == null) return null;
  final diff = DateTime.now().difference(time);
  if (diff.isNegative || diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}

/// Where a notification opens: its own [link] when it carries an in-app route,
/// otherwise the place its [type] belongs to.
///
/// Every server notification names a link today. The fallback is for a push
/// that arrives without one, which the shift module's generic pushes may do
/// (HIN-46): a `SHIFT_*` push still lands on "Meine Schichten" rather than
/// opening the app on whatever page was last shown.
String? notificationTarget(String? link, String? type) {
  if (link != null && link.startsWith('/') && link.length > 1) return link;
  final kind = (type ?? '').toUpperCase();
  if (kind.startsWith('SHIFT_')) return '/shifts';
  if (kind == 'MODERATION_ADMIN_ALERT') return '/admin/users';
  if (kind.startsWith('MODERATION_CASE_') ||
      kind == 'MODERATION_APPEAL_FILED' ||
      kind == 'MODERATION_CONFIRM_REQUESTED' ||
      kind == 'MODERATION_TEAM_NOTE') {
    return '/moderation';
  }
  return null;
}
