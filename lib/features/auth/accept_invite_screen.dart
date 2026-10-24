import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/util/server_link.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart' show showGlassErrorToast;
import 'auth_shell.dart';
import 'auth_flow_cubit.dart';
import 'sso_launch.dart';

/// Lands here from the invitation deep link (web URL or `hinata://invite`).
/// Validates the invitation, lets the invitee set a password in the app's UI,
/// then signs them in. [server] (carried by the link) points a freshly opened
/// web/app at the right backend.
///
/// Where the server has SSO, the invitee can join with it instead: the sign-in
/// carries the invitation, which proves the address, and completes it. With
/// local sign-in off that is the only way, as a password could not be used
/// (HIN-179).
class AcceptInviteScreen extends StatelessWidget {
  const AcceptInviteScreen({super.key, required this.token, this.server});

  final String token;
  final String? server;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => AuthFlowCubit(context.read<AuthRepository>()),
    child: _AcceptInviteScreenBody(token: token, server: server),
  );
}

class _AcceptInviteScreenBody extends StatefulWidget {
  const _AcceptInviteScreenBody({required this.token, this.server});

  final String token;
  final String? server;

  @override
  State<_AcceptInviteScreenBody> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<_AcceptInviteScreenBody> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _obscure = true;
  String? _email;
  String? _loadError; // token invalid/expired
  String? _submitError;
  List<SsoProvider> _providers = const [];
  bool _providersFailed = false;

  /// Id of the SSO provider currently launching, or null.
  String? _launchingSsoId;

  @override
  void initState() {
    super.initState();
    // After the first frame, not during initState: the first thing _init does
    // is apply the server named in the link, which reads localized strings —
    // and an inherited-widget lookup from a state that is still being created
    // trips an assertion that an async method swallows into its future, so the
    // screen would sit on its spinner forever. Same reason verify_email_screen
    // defers.
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    await _applyServer();
    if (!mounted) return;
    await _loadInfo();
  }

  /// Point a freshly opened web/app at the backend named in the link before any
  /// API call resolves — validated + consent-gated (see [applyServerFromLink]).
  Future<void> _applyServer() => applyServerFromLink(context, widget.server);

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final flow = context.read<AuthFlowCubit>();
    final providers = _loadProviders(flow);
    try {
      final info = await flow.inviteInfo(widget.token);
      await providers;
      if (!mounted) return;
      setState(() {
        _email = info.email;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = failure.message;
      });
    }
  }

  /// The SSO providers an invitee can join with. A failed lookup only matters
  /// where SSO is the only way in, and is said there with a retry.
  Future<void> _loadProviders(AuthFlowCubit flow) async {
    try {
      final providers = await flow.ssoProviders();
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _providersFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _providersFailed = true);
    }
  }

  Future<void> _joinWithSso(SsoProvider provider) async {
    final storage = context.read<AuthBloc>().storage;
    setState(() => _launchingSsoId = provider.id);
    try {
      // As on the login screen: let the loader reach the screen before the
      // web app hands this tab to the provider.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      final launched = await launchSso(storage, provider, invite: widget.token);
      if (!mounted) return;
      // On the web a launched sign-in has left this page; anywhere else the
      // browser took over, and the buttons come back for a retry.
      if (!kIsWeb || !launched) setState(() => _launchingSsoId = null);
      if (!launched) {
        showGlassErrorToast(context, context.t('auth.ssoLaunchFailed'));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _launchingSsoId = null);
      showGlassErrorToast(context, context.t('auth.ssoLaunchFailed'));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final tokens = await context.read<AuthFlowCubit>().acceptInvite(
        widget.token,
        _password.text,
      );
      if (!mounted) return;
      // Password set — let the password manager offer to save the new
      // credential for this account.
      TextInput.finishAutofillContext();
      context.read<AuthBloc>().add(
        SsoTokensReceived(tokens.access, tokens.refresh),
      );
      context.go('/dashboard');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      maxContentWidth: 460,
      child: AuthGlassCard(
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: HiveLoader()),
              )
            : _loadError != null
            ? _invalid(context)
            : _form(context),
      ),
    );
  }

  Widget _invalid(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.mailWarning, size: 40, color: AppColors.danger),
        const SizedBox(height: 16),
        Text(
          context.t('invite.invalidTitle'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.t('invite.invalidBody'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: Text(context.t('invite.goToLogin')),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final passwordMin = context.select(
      (AppConfigBloc b) => b.state.meta?.passwordMinLength ?? 10,
    );
    final localAuth = context.select(
      (AppConfigBloc b) => b.state.meta?.localAuthEnabled ?? true,
    );
    final busy = _submitting || _launchingSsoId != null;
    return Form(
      key: _formKey,
      // Lets a password manager capture the new password (and offer to save it
      // for this invited account) on submit.
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t('invite.title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.t(
                localAuth ? 'invite.subtitle' : 'invite.subtitleSso',
                variables: {'email': _email ?? ''},
              ),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (localAuth) ...[
              const SizedBox(height: 20),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofocus: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: context.t('invite.passwordLabel'),
                  hintText: context.t('invite.passwordHint'),
                  prefixIcon: const Icon(LucideIcons.lock),
                  suffixIcon: IconButton(
                    tooltip: context.t(
                      _obscure ? 'auth.showPassword' : 'auth.hidePassword',
                    ),
                    icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) => (v ?? '').length >= passwordMin
                    ? null
                    : context.t(
                        'errors.passwordTooShort',
                        variables: {'min': passwordMin},
                      ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 8),
                Text(
                  context.t(_submitError!),
                  style: TextStyle(color: AppColors.dangerInk),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: _submitting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: HiveLoader(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Text(context.t('invite.createAccount')),
              ),
            ],
            if (localAuth && _providers.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      context.t('auth.or'),
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
            ],
            if (_providers.isNotEmpty) const SizedBox(height: 12),
            for (final provider in _providers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _joinWithSso(provider),
                  icon: _launchingSsoId == provider.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: HiveLoader(size: 18, strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.shield, size: 18),
                  label: Text(
                    _launchingSsoId == provider.id
                        ? context.t('auth.signingIn')
                        : context.t(
                            'invite.joinWith',
                            variables: {'provider': provider.displayName},
                          ),
                  ),
                ),
              ),
            // SSO is the only way in here, so a lookup that failed or found
            // nothing must say so: silence would be a dead end.
            if (!localAuth && _providers.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                context.t(
                  _providersFailed
                      ? 'auth.ssoLoadFailed'
                      : 'auth.ssoOnlyNoProviders',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              if (_providersFailed)
                TextButton.icon(
                  onPressed: () =>
                      _loadProviders(context.read<AuthFlowCubit>()),
                  icon: const Icon(LucideIcons.refreshCw, size: 15),
                  label: Text(context.t('common.retry')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
