import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hinata_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';

/// Public "forgot password" entry point (logged-out). Emails a reset link that
/// deep-links back into [ResetPasswordScreen]. The confirmation is intentionally
/// neutral (doesn't reveal whether the address exists).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<HinataRepository>().requestPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _sent = true;
      });
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SoftCard(
                padding: const EdgeInsets.all(32),
                child: _sent ? _sentView(context) : _form(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('forgotPassword.title'),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('forgotPassword.subtitle'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _email,
            enabled: !_submitting,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: context.t('forgotPassword.email'),
              prefixIcon: const Icon(LucideIcons.mail),
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (v) => (v != null && v.contains('@'))
                ? null
                : context.t('errors.invalidEmail'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              context.t(_error!),
              style: const TextStyle(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: HiveLoader(strokeWidth: 2, color: Colors.white),
                  )
                : Text(context.t('forgotPassword.submit')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting ? null : () => context.go('/login'),
            child: Text(context.t('forgotPassword.backToSignIn')),
          ),
        ],
      ),
    );
  }

  Widget _sentView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(LucideIcons.mailCheck, size: 40, color: AppColors.accentStrong),
        const SizedBox(height: 16),
        Text(
          context.t('forgotPassword.sentTitle'),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.t('forgotPassword.sentBody',
              variables: {'email': _email.text.trim()}),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: Text(context.t('forgotPassword.backToSignIn')),
        ),
      ],
    );
  }
}
