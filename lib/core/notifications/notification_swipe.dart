import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../models/content_models.dart';
import '../theme/app_colors.dart';

/// Standard swipe gestures for a notification row, shared by the bell popover
/// and the full notifications page:
///
/// * swipe **left** (end → start): deletes the notification;
/// * swipe **right** (start → end): toggles read ⇄ unread — the row snaps
///   back instead of dismissing, and the refreshed list reflects the new state.
class NotificationSwipe extends StatelessWidget {
  const NotificationSwipe({
    super.key,
    required this.notification,
    required this.onDelete,
    required this.onToggleRead,
    required this.child,
  });

  final AppNotification notification;

  /// Deletes the notification server-side; the caller refreshes its list.
  final Future<void> Function(AppNotification) onDelete;

  /// Flips read ⇄ unread server-side; the caller refreshes its list.
  final Future<void> Function(AppNotification) onToggleRead;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    return Dismissible(
      key: ValueKey('notification-swipe-${notification.id}'),
      direction: DismissDirection.horizontal,
      // Read-toggle (right) background.
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: AppColors.accentStrong,
        icon: unread ? LucideIcons.mailOpen : LucideIcons.mail,
        label: context.t(
          unread ? 'notifications.markRead' : 'notifications.markUnread',
        ),
      ),
      // Delete (left) background.
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: AppColors.danger,
        icon: LucideIcons.trash2,
        label: context.t('notifications.delete'),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          await onDelete(notification);
          // The caller reloads its list; the row disappears with the refresh,
          // so don't also dismiss (the reloaded tree no longer has this key).
          return false;
        }
        await onToggleRead(notification);
        return false; // snap back — the state flip shows via the refresh
      },
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final leading = alignment == Alignment.centerLeft;
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading) ...[
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!leading) ...[
            const SizedBox(width: 8),
            Icon(icon, size: 18, color: Colors.white),
          ],
        ],
      ),
    );
  }
}
