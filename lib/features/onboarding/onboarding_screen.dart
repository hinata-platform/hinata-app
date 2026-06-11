import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';

/// One-time feature tour shown after the first successful server connection.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.storage, required this.onDone});

  final AppStorage storage;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage(this.icon, this.titleKey, this.bodyKey, this.color);

  final IconData icon;
  final String titleKey;
  final String bodyKey;
  final Color color;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = [
    _OnboardingPage(Icons.folder_special_rounded, 'onboarding.projects.title',
        'onboarding.projects.body', AppColors.pastelBlue),
    _OnboardingPage(Icons.timer_rounded, 'onboarding.time.title',
        'onboarding.time.body', AppColors.pastelLavender),
    _OnboardingPage(Icons.stacked_bar_chart_rounded, 'onboarding.gantt.title',
        'onboarding.gantt.body', AppColors.pastelPeach),
    _OnboardingPage(Icons.table_chart_rounded, 'onboarding.timesheets.title',
        'onboarding.timesheets.body', AppColors.pastelMint),
    _OnboardingPage(Icons.view_kanban_rounded, 'onboarding.boards.title',
        'onboarding.boards.body', AppColors.pastelBlue),
    _OnboardingPage(Icons.insights_rounded, 'onboarding.reports.title',
        'onboarding.reports.body', AppColors.pastelLavender),
    _OnboardingPage(Icons.dashboard_rounded, 'onboarding.dashboards.title',
        'onboarding.dashboards.body', AppColors.pastelPeach),
    _OnboardingPage(Icons.menu_book_rounded, 'onboarding.knowledge.title',
        'onboarding.knowledge.body', AppColors.pastelMint),
  ];

  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(context.t('onboarding.skip')),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                color: page.color,
                                borderRadius: BorderRadius.circular(48),
                              ),
                              child: Icon(page.icon,
                                  size: 72, color: AppColors.navy),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              context.t(page.titleKey),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.t(page.bodyKey),
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(color: AppColors.textSecondary, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.navy
                                : AppColors.navy.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (isLast) {
                                _finish();
                              } else {
                                _controller.nextPage(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            },
                            child: Text(context
                                .t(isLast ? 'onboarding.start' : 'onboarding.next')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish() async {
    await widget.storage.setOnboardingDone();
    widget.onDone();
  }
}
