import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hinata_repository.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final HinataRepository _repo;
  late final PagedCubit<AppNotification> _cubit;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _repo = context.read<HinataRepository>();
    _cubit = PagedCubit<AppNotification>(
      (page, size) => _repo.notificationsPage(page: page, size: size),
      pageSize: 25,
      keyOf: (n) => n.id,
    )..load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cubit.close();
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      PagedCubit<AppNotification>,
      PagedState<AppNotification>
    >(
      bloc: _cubit,
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: _cubit.load,
          child: AsyncView(
            isLoading: state.isLoading,
            hasData: state.hasData,
            errorKey: state.errorKey,
            onRetry: _cubit.load,
            builder: (context) {
              final notifications = state.items;
              return ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: context.pagePadding,
                children: [
                  SectionHeader(title: context.t('notifications.title')),
                  const SizedBox(height: 12),
                  if (notifications.isEmpty)
                    HiveEmptyState(
                      title: context.t('notifications.title'),
                      message: context.t('notifications.empty'),
                    ),
                  for (final notification in notifications)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SoftCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        onTap: () => _open(notification),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: notification.read
                                    ? Colors.transparent
                                    : AppColors.accentOrange,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notification.title,
                                    style: TextStyle(
                                      fontWeight: notification.read
                                          ? FontWeight.w500
                                          : FontWeight.w800,
                                    ),
                                  ),
                                  if ((notification.body ?? '').isNotEmpty)
                                    Text(
                                      notification.body!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (state.isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: HiveLoader(size: 30)),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.read) {
      try {
        await _repo.markNotificationRead(notification.id);
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
}
