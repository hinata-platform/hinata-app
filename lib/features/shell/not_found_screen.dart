import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/hive_empty_state.dart';

/// What the app shows for a link that leads nowhere.
///
/// The router had no `errorBuilder` at all, which meant an unknown path drew an
/// empty page under the brand mark — the app looked broken rather than
/// unhelpful. Two different kinds of nowhere end up here:
///
///  • a path that matched no route, rendered outside the shell, which is why
///    this brings its own canvas ([standalone]);
///  • a route that exists but whose module is switched off on this server — a
///    deep link into the extended time-tracking module while its platform flag
///    is off. That one is rendered *inside* the shell, which already paints the
///    canvas and the chrome around it.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.standalone = true});

  /// Whether this page has to paint the app canvas itself. False when the shell
  /// is already doing it around us.
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: HiveEmptyState(
            title: context.t('notFound.title'),
            message: context.t('notFound.message'),
            action: FilledButton.icon(
              onPressed: () => context.go('/dashboard'),
              icon: const Icon(LucideIcons.house, size: 18),
              label: Text(context.t('notFound.home')),
            ),
          ),
        ),
      ),
    );
    if (!standalone) return body;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackground(dark: dark)),
          Positioned.fill(child: SafeArea(child: body)),
        ],
      ),
    );
  }
}
