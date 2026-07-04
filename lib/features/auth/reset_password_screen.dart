import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hinata_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';

/// Lands here from the reset deep link (web URL or `hinata://reset-password`).
/// Lets the user choose a new password in the app's UI, then signs them in.
/// [server] (carried by the link) points a freshly opened web/app at the right
/// backend.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token, this.server});

  final String token;
  final String? server;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyServer();
  }

  /// Point a freshly opened web/app at the backend named in the link.
  Future<void> _applyServer() async {
    final server = widget.server;
    if (server == null || server.isEmpty) return;
    final storage = context.read<AppStorage>();
    if (storage.serverUrl != server) {
      await storage.setServerUrl(server);
      if (mounted) context.read<AppConfigBloc>().add(ServerUrlSubmitted(server));
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final tokens = await context
          .read<HinataRepository>()
          .acceptPasswordReset(widget.token, _password.text);
      if (!mounted) return;
      context.read<AuthBloc>().add(SsoTokensReceived(tokens.access, tokens.refresh));
      context.go('/dashboard');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalid = widget.token.isEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SoftCard(
                padding: const EdgeInsets.all(32),
                child: invalid ? _invalid(context) : _form(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _invalid(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.triangleAlert, size: 40, color: AppColors.danger),
        const SizedBox(height: 16),
        Text(
          context.t('reset.invalidTitle'),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.t('reset.invalidBody'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: Text(context.t('reset.goToLogin')),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.t('reset.title'),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('reset.subtitle'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.t('reset.passwordLabel'),
              hintText: context.t('reset.passwordHint'),
              prefixIcon: const Icon(LucideIcons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v ?? '').length >= 10
                ? null
                : context.t('errors.passwordTooShort'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: context.t('reset.confirmLabel'),
              prefixIcon: const Icon(LucideIcons.lock),
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (v) => (v == _password.text)
                ? null
                : context.t('errors.passwordsDoNotMatch'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              context.t(_error!),
              style: const TextStyle(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: HiveLoader(strokeWidth: 2, color: Colors.white),
                  )
                : Text(context.t('reset.updatePassword')),
          ),
        ],
      ),
    );
  }
}
