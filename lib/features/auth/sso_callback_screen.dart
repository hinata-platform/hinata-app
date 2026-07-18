import 'package:flutter/material.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import 'auth_shell.dart';

/// Landing screen for the web SSO flow: the server redirects to
/// `<origin>/#/auth-callback?access_token=...&refresh_token=...` after a
/// successful identity-provider login. The tokens are handed to [AuthBloc];
/// the router then moves the (now authenticated) user to the dashboard.
class SsoCallbackScreen extends StatefulWidget {
  const SsoCallbackScreen({
    super.key,
    required this.accessToken,
    required this.refreshToken,
  });

  final String? accessToken;
  final String? refreshToken;

  @override
  State<SsoCallbackScreen> createState() => _SsoCallbackScreenState();
}

class _SsoCallbackScreenState extends State<SsoCallbackScreen> {
  @override
  void initState() {
    super.initState();
    final access = widget.accessToken;
    final refresh = widget.refreshToken;
    if (access != null && refresh != null) {
      context.read<AuthBloc>().add(SsoTokensReceived(access, refresh));
    } else {
      // No tokens in the URL: nothing to do here, back to login.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AuthBloc>().add(const AuthChecked());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      maxContentWidth: 360,
      child: AuthGlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HiveLoader(),
            const SizedBox(height: 16),
            Text(context.t('auth.signingIn'), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
