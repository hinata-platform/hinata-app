import 'package:flutter/material.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/repositories/auth_repository.dart';
import 'auth_shell.dart';

/// Landing screen for the SSO flow: after a successful identity-provider login
/// the server redirects to `<origin>/auth-callback?code=...` (web) or
/// `hinata://auth-callback?code=...` (native). The `code` is a single-use
/// handoff token; this screen redeems it for the real access/refresh pair via a
/// POST (so bearer tokens never travel in the URL) and hands them to
/// [AuthBloc], which routes the now-authenticated user to the dashboard.
class SsoCallbackScreen extends StatefulWidget {
  const SsoCallbackScreen({
    super.key,
    this.code,
    required this.accessToken,
    required this.refreshToken,
  });

  /// Single-use handoff code; redeemed for the token pair. Preferred path.
  final String? code;

  /// Legacy fallback: tokens directly in the URL (older server redirects).
  final String? accessToken;
  final String? refreshToken;

  @override
  State<SsoCallbackScreen> createState() => _SsoCallbackScreenState();
}

class _SsoCallbackScreenState extends State<SsoCallbackScreen> {
  @override
  void initState() {
    super.initState();
    final code = widget.code;
    final access = widget.accessToken;
    final refresh = widget.refreshToken;
    if (code != null && code.isNotEmpty) {
      _redeem(code);
    } else if (access != null && refresh != null) {
      // Legacy redirect that still carried tokens in the URL.
      context.read<AuthBloc>().add(SsoTokensReceived(access, refresh));
    } else {
      // Nothing usable in the URL: back to login.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AuthBloc>().add(const AuthChecked());
      });
    }
  }

  Future<void> _redeem(String code) async {
    try {
      final pair = await context.read<AuthRepository>().exchangeSso(code);
      if (!mounted) return;
      context.read<AuthBloc>().add(
        SsoTokensReceived(pair.access, pair.refresh),
      );
    } catch (_) {
      // Invalid/expired/replayed code — fall back to the login screen.
      if (!mounted) return;
      context.read<AuthBloc>().add(const AuthChecked());
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
