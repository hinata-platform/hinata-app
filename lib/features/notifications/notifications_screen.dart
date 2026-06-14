import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final FetchCubit<List<AppNotification>> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit =
        FetchCubit(() => context.read<HivoraRepository>().notifications())..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<List<AppNotification>>,
          FetchState<List<AppNotification>>>(
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: _cubit.load,
            child: AsyncView(
              isLoading: state.isLoading,
              hasData: state.hasData,
              errorKey: state.errorKey,
              onRetry: _cubit.load,
              builder: (context) {
                final notifications = state.data!;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: context.pagePadding,
                  children: [
                    SectionHeader(title: context.t('notifications.title')),
                    const SizedBox(height: 12),
                    if (notifications.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          context.t('notifications.empty'),
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final notification in notifications)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SoftCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
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
                                            fontSize: 13),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _open(AppNotification notification) async {
    final repository = context.read<HivoraRepository>();
    if (!notification.read) {
      try {
        await repository.markNotificationRead(notification.id);
      } catch (_) {
        // Non-critical; the list refresh below reflects server truth.
      }
      _cubit.load();
    }
    final link = notification.link;
    if (link != null && link.startsWith('/issues/') && mounted) {
      context.go(link);
    }
  }
}
