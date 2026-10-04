import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/repositories/notification_repository.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/notifications/notification_swipe.dart';
import '../../core/notifications/notification_visuals.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../../core/widgets/hive_widgets.dart' show forwardChevron;
import '../shell/page_chrome.dart';
import 'notifications_cubit.dart';
import '../../core/theme/app_type.dart';

/// Full notification centre: the paged feed grouped into time buckets
/// (today / yesterday / this week / …), rendered as iOS-style inset grouped
/// cards with per-type icon chips and unread accents.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        NotificationsCubit(context.read<NotificationRepository>())..load(),
    child: const _NotificationsBody(),
  );
}

class _NotificationsBody extends StatefulWidget {
  const _NotificationsBody();

  @override
  State<_NotificationsBody> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<_NotificationsBody> {
  late final NotificationsCubit _cubit;
  final ScrollController _scroll = ScrollController();
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<NotificationsCubit>();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Infinite scroll: pull the next page as the user nears the bottom.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 480) {
      _cubit.loadMore();
    }
  }

  Future<void> _markAllRead(List<AppNotification> items) async {
    final hasUnread = items.any((n) => !n.read);
    if (!hasUnread || _markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _cubit.markAllRead();
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
    if (mounted) setState(() => _markingAll = false);
  }

  /// A tear-off rather than a closure, so the bar's action compares equal from
  /// one build to the next and the chrome is not re-published every frame.
  void _markAllFromBar(Rect? _) => _markAllRead(_cubit.state.items);

  Future<void> _delete(AppNotification notification) async {
    try {
      await _cubit.delete(notification.id);
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _toggleRead(AppNotification notification) async {
    try {
      if (notification.read) {
        await _cubit.markUnread(notification.id);
      } else {
        await _cubit.markRead(notification.id);
      }
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.read) {
      try {
        await _cubit.markRead(notification.id);
      } catch (_) {
        // Non-critical; the list refresh below reflects server truth.
      }
      _cubit.load();
    }
    // Every notification type carries a relative in-app route in `link`
    // (issues, teams, admin approvals, …) — the same field pushed via FCM and
    // rendered as the email CTA, so this is not limited to issue mentions.
    final link = notification.link;
    if (link != null && link.isNotEmpty && link.startsWith('/') && mounted) {
      context.go(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCubit, PagedState<AppNotification>>(
      bloc: _cubit,
      builder: (context, state) {
        final compact = context.isCompact;
        final unread = state.items.where((n) => !n.read).length;
        return PageChrome(
          title: context.t('notifications.title'),
          // A phone's bar has room for one action, and this page has exactly
          // one. While it runs the button spins rather than vanishing, so a
          // second tap has nothing to land on. Nothing unread, nothing to do.
          actions: compact && unread > 0
              ? [
                  PageAction(
                    icon: LucideIcons.checkCheck,
                    label: context.t('notifications.markAllRead'),
                    primary: true,
                    busy: _markingAll,
                    onTap: _markAllFromBar,
                  ),
                ]
              : const [],
          child: _feed(context, state, compact: compact),
        );
      },
    );
  }

  Widget _feed(
    BuildContext context,
    PagedState<AppNotification> state, {
    required bool compact,
  }) {
    return RefreshIndicator(
      onRefresh: _cubit.load,
      child: AsyncView(
        isLoading: state.isLoading,
        hasData: state.hasData,
        errorKey: state.errorKey,
        onRetry: _cubit.load,
        builder: (context) {
          final notifications = state.items;
          final unreadCount = notifications.where((n) => !n.read).length;
          final groups = _groupByBucket(notifications);
          final showEmpty = notifications.isEmpty;
          final showLoader = state.isLoadingMore;
          // Lazy builder instead of a concrete children list: the feed paginates
          // (infinite scroll), so as pages accumulate only the on-screen group
          // cards should be built, not every past group up-front.
          final itemCount =
              1 + (showEmpty ? 1 : 0) + groups.length + (showLoader ? 1 : 0);
          return ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: context.pagePadding,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _head(
                  context,
                  unreadCount: unreadCount,
                  onMarkAll: compact ? null : () => _markAllRead(notifications),
                );
              }
              var i = index - 1;
              if (showEmpty) {
                if (i == 0) {
                  return HiveEmptyState(
                    title: context.t('notifications.title'),
                    message: context.t('notifications.empty'),
                  );
                }
                i -= 1;
              }
              if (i < groups.length) {
                final group = groups[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GroupLabel(
                      label: context.t(
                        'notifications.group.${group.bucket.key}',
                      ),
                    ),
                    SoftCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var j = 0; j < group.items.length; j++) ...[
                            if (j > 0)
                              Divider(
                                height: 1,
                                indent: 62,
                                color: AppColors.hairline2,
                              ),
                            NotificationSwipe(
                              notification: group.items[j],
                              onDelete: _delete,
                              onToggleRead: _toggleRead,
                              child: _NotificationTile(
                                notification: group.items[j],
                                onTap: () => _open(group.items[j]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                );
              }
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: HiveLoader(size: 30)),
              );
            },
          );
        },
      ),
    );
  }

  /// The count of unread items, and on a wide window the action beside it.
  ///
  /// No title: the bar above already says "Notifications", on a phone and on
  /// a wide window alike, since this is a sub-page. The count is information,
  /// not a heading, so it is one quiet line. On a phone the action lives in
  /// the bar ([onMarkAll] is null); on a wide window the bar's own action
  /// would sit at the far end of the window, so it stays by the count.
  Widget _head(
    BuildContext context, {
    required int unreadCount,
    required VoidCallback? onMarkAll,
  }) {
    if (unreadCount == 0) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.t(
                'notifications.unreadCount',
                variables: {'count': '$unreadCount'},
              ),
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          if (onMarkAll != null)
            TextButton.icon(
              onPressed: _markingAll ? null : onMarkAll,
              style: TextButton.styleFrom(foregroundColor: AppColors.accentInk),
              icon: const Icon(LucideIcons.checkCheck, size: 16),
              label: Text(
                context.t('notifications.markAllRead'),
                style: const TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── time bucketing ─────────────────────────────

enum _Bucket {
  today('today'),
  yesterday('yesterday'),
  thisWeek('thisWeek'),
  thisMonth('thisMonth'),
  earlier('earlier');

  const _Bucket(this.key);
  final String key;
}

_Bucket _bucketOf(DateTime? createdAt, DateTime now) {
  if (createdAt == null) return _Bucket.earlier;
  final local = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (!day.isBefore(today)) return _Bucket.today;
  if (!day.isBefore(today.subtract(const Duration(days: 1)))) {
    return _Bucket.yesterday;
  }
  // Calendar week starting Monday, matching the local convention.
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (!day.isBefore(weekStart)) return _Bucket.thisWeek;
  if (day.year == today.year && day.month == today.month) {
    return _Bucket.thisMonth;
  }
  return _Bucket.earlier;
}

class _NotificationGroup {
  const _NotificationGroup(this.bucket, this.items);
  final _Bucket bucket;
  final List<AppNotification> items;
}

/// Splits the (already newest-first) feed into contiguous time buckets,
/// preserving order inside each group.
List<_NotificationGroup> _groupByBucket(List<AppNotification> items) {
  final now = DateTime.now();
  final groups = <_NotificationGroup>[];
  for (final n in items) {
    final bucket = _bucketOf(n.createdAt, now);
    if (groups.isNotEmpty && groups.last.bucket == bucket) {
      groups.last.items.add(n);
    } else {
      groups.add(_NotificationGroup(bucket, [n]));
    }
  }
  return groups;
}

// ─────────────────────────────── widgets ──────────────────────────────────

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: AppType.caption,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    final (icon, tint) = notificationVisual(notification.type);
    final ago = notificationTimeAgo(notification.createdAt);
    return Semantics(
      button: true,
      // Unread shows only as weight and tint; say it too.
      value: unread ? context.t('notifications.unread') : null,
      child: Material(
        color: unread ? AppColors.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.soft(tint),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 17, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppType.label,
                                height: 1.35,
                                color: AppColors.ink,
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (ago != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              ago,
                              style: TextStyle(
                                fontSize: AppType.caption,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ],
                          if (unread) ...[
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.accentStrong,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if ((notification.body ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          notification.body!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.label,
                            height: 1.4,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Icon(
                    forwardChevron(context),
                    size: 15,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
