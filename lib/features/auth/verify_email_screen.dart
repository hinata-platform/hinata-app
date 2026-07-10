import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';

/// Lands here from the email-verification deep link (web URL or
/// `hinata://verify-email`). Confirms the token, then either signs the user in
/// (normal flow) or shows a "waiting for admin approval" state. [server] (carried
/// by the link) points a freshly opened web/app at the right backend.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.token, this.server});

  final String token;
  final String? server;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

enum _Phase { verifying, pending, invalid }

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  _Phase _phase = _Phase.verifying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  Future<void> _verify() async {
    if (widget.token.isEmpty) {
      setState(() => _phase = _Phase.invalid);
      return;
    }
    // Point a freshly opened web/app at the backend named in the link first.
    final server = widget.server;
    if (server != null && server.isNotEmpty) {
      final storage = context.read<AppStorage>();
      if (storage.serverUrl != server) {
        await storage.setServerUrl(server);
        if (!mounted) return;
        context.read<AppConfigBloc>().add(ServerUrlSubmitted(server));
      }
    }
    try {
      final result =
          await context.read<AuthRepository>().verifyEmail(widget.token);
      if (!mounted) return;
      if (result.pendingApproval || result.access == null || result.refresh == null) {
        setState(() => _phase = _Phase.pending);
        return;
      }
      // Verified & active → sign in and head to the dashboard.
      context.read<AuthBloc>().add(SsoTokensReceived(result.access!, result.refresh!));
      context.go('/dashboard');
    } on ApiFailure {
      if (!mounted) return;
      setState(() => _phase = _Phase.invalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SoftCard(
                padding: const EdgeInsets.all(32),
                child: switch (_phase) {
                  _Phase.verifying => _verifying(context),
                  _Phase.pending => _pending(context),
                  _Phase.invalid => _invalid(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _verifying(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const HiveLoader(size: 34),
        const SizedBox(height: 18),
        Text(
          context.t('verifyEmail.verifying'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _pending(BuildContext context) {
    return _Message(
      icon: LucideIcons.clock,
      color: AppColors.accentStrong,
      title: context.t('verifyEmail.pendingTitle'),
      body: context.t('verifyEmail.pendingBody'),
      actionLabel: context.t('verifyEmail.goToLogin'),
      onAction: () => context.go('/login'),
    );
  }

  Widget _invalid(BuildContext context) {
    return _Message(
      icon: LucideIcons.triangleAlert,
      color: AppColors.danger,
      title: context.t('verifyEmail.invalidTitle'),
      body: context.t('verifyEmail.invalidBody'),
      actionLabel: context.t('verifyEmail.goToLogin'),
      onAction: () => context.go('/login'),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 40, color: color),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
