import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  List<SsoProvider> _providers = const [];

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    try {
      final providers = await context.read<HivoraRepository>().ssoProviders();
      if (mounted) setState(() => _providers = providers);
    } catch (_) {
      // SSO buttons are optional; password login stays available.
    }
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final organization =
        context.select((AppConfigBloc bloc) => bloc.state.meta?.organizationName);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: BlocConsumer<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state.errorKey != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t(state.errorKey!))),
                    );
                  }
                },
                builder: (context, state) {
                  final busy = state.status == AuthStatus.authenticating;
                  return SoftCard(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            organization ?? 'Hivora',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.t('auth.subtitle'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _identifier,
                            enabled: !busy,
                            autofillHints: const [AutofillHints.username],
                            decoration: InputDecoration(
                              labelText: context.t('auth.identifier'),
                              prefixIcon: const Icon(Icons.person_rounded),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? context.t('errors.required')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            enabled: !busy,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: context.t('auth.password'),
                              prefixIcon: const Icon(Icons.lock_rounded),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? context.t('errors.required')
                                : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: busy ? null : _submit,
                            child: busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(context.t('auth.signIn')),
                          ),
                          if (_providers.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    context.t('auth.or'),
                                    style: const TextStyle(
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 16),
                            for (final provider in _providers)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: OutlinedButton.icon(
                                  onPressed:
                                      busy ? null : () => _launchSso(provider),
                                  icon: const Icon(Icons.shield_rounded, size: 18),
                                  label: Text(context.t('auth.continueWith',
                                      variables: {'provider': provider.displayName})),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      context
          .read<AuthBloc>()
          .add(LoginSubmitted(_identifier.text.trim(), _password.text));
    }
  }

  Future<void> _launchSso(SsoProvider provider) async {
    final serverUrl = context.read<AuthBloc>().storage.serverUrl ?? '';
    // The server redirects back into the app via hivora://auth-callback.
    await launchUrl(Uri.parse('$serverUrl${provider.loginUrl}'),
        mode: LaunchMode.externalApplication);
  }
}
