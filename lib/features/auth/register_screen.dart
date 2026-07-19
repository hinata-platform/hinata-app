import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../connect/server_switcher.dart';
import '../legal/legal_links.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import 'auth_shell.dart';

/// Public self-registration. Collects the new account's details, then shows a
/// "confirm your email" state — the account is only usable once the emailed
/// verification link is opened (see [VerifyEmailScreen]).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  bool _resending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _username.dispose();
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
      await context.read<AuthRepository>().register(
        email: _email.text.trim(),
        username: _username.text.trim(),
        displayName: _displayName.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      // Account created — let the password manager offer to save the new
      // username/password it just captured.
      TextInput.finishAutofillContext();
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

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await context.read<AuthRepository>().resendVerification(
        _email.text.trim(),
      );
      if (!mounted) return;
      showGlassToast(
        context,
        context.t('register.resent'),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      maxContentWidth: 460,
      child: AuthGlassCard(child: _sent ? _sentView(context) : _form(context)),
    );
  }

  Widget _form(BuildContext context) {
    final meta = context.select((AppConfigBloc b) => b.state.meta);
    final organization = meta?.organizationName;
    return Form(
      key: _formKey,
      // Groups every credential field so a password manager can capture the
      // whole set and offer to save it once the account is created.
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ServerSelectorButton(),
            const SizedBox(height: 16),
            Text(
              organization ?? 'Hinata',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('register.subtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _displayName,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.t('register.displayName'),
                hintText: context.t('register.displayNameHint'),
                prefixIcon: const Icon(LucideIcons.user),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.t('errors.required')
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.t('register.email'),
                prefixIcon: const Icon(LucideIcons.mail),
              ),
              validator: (v) => (v != null && v.contains('@'))
                  ? null
                  : context.t('errors.invalidEmail'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _username,
              enabled: !_submitting,
              autofillHints: const [AutofillHints.newUsername],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.t('register.username'),
                hintText: context.t('register.usernameHint'),
                prefixIcon: const Icon(LucideIcons.atSign),
              ),
              validator: (v) =>
                  RegExp(r'^[a-zA-Z0-9._-]{3,40}$').hasMatch(v ?? '')
                  ? null
                  : context.t('errors.invalidUsername'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              enabled: !_submitting,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.t('register.password'),
                hintText: context.t('register.passwordHint'),
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
              enabled: !_submitting,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: context.t('register.confirmPassword'),
                prefixIcon: const Icon(LucideIcons.lock),
              ),
              onFieldSubmitted: (_) => _submit(),
              validator: (v) => (v == _password.text)
                  ? null
                  : context.t('errors.passwordsDoNotMatch'),
            ),
            if (meta?.adminApprovalRequired ?? false) ...[
              const SizedBox(height: 16),
              _InfoNote(text: context.t('register.approvalHint')),
            ],
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
                  : Text(context.t('register.submit')),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  context.t('register.haveAccount'),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                TextButton(
                  onPressed: _submitting ? null : () => context.go('/login'),
                  child: Text(context.t('register.signIn')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.t('auth.legalNotice'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const LegalLinks(),
          ],
        ),
      ),
    );
  }

  Widget _sentView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          LucideIcons.mailCheck,
          size: 40,
          color: AppColors.accentStrong,
        ),
        const SizedBox(height: 16),
        Text(
          context.t('register.checkEmailTitle'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.t(
            'register.checkEmailBody',
            variables: {'email': _email.text.trim()},
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _resending ? null : _resend,
          icon: _resending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: HiveLoader(size: 16, strokeWidth: 2),
                )
              : const Icon(LucideIcons.send, size: 16),
          label: Text(context.t('register.resend')),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.go('/login'),
          child: Text(context.t('register.backToSignIn')),
        ),
      ],
    );
  }
}

/// A soft, amber-tinted callout used for the admin-approval hint.
class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info, size: 18, color: AppColors.accentStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
