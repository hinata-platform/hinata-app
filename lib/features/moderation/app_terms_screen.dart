import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/hex_mark.dart';
import '../auth/auth_shell.dart';
import '../legal/legal_links.dart';

/// The app's own terms, once per device before connecting or signing in
/// (HIN-175): the zero tolerance the stores ask for, and where the terms are
/// in full. Agreeing is the only way on; the app stays here until then.
class AppTermsScreen extends StatefulWidget {
  const AppTermsScreen({
    super.key,
    required this.storage,
    required this.onDone,
  });

  final AppStorage storage;

  /// Moves on once the agreement is stored.
  final VoidCallback onDone;

  @override
  State<AppTermsScreen> createState() => _AppTermsScreenState();
}

class _AppTermsScreenState extends State<AppTermsScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    await widget.storage.setAppTermsAccepted();
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    maxContentWidth: 440,
    child: AuthGlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: HexMark(size: 40)),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              context.t('moderation.appTerms.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: AppType.display,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('moderation.appTerms.body'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.body,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => unawaited(openTermsOfService(context)),
              child: Text(context.t('moderation.appTerms.read')),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy ? null : () => unawaited(_accept()),
            child: Text(context.t('moderation.appTerms.accept')),
          ),
        ],
      ),
    ),
  );
}
