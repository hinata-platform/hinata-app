import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';

/// A centred pair of links to the public legal pages (terms of service +
/// privacy policy), used as a footer in the auth area (login / register).
///
/// Navigates via [GoRouter] so the URL becomes the clean public path
/// (`/terms-of-service`, `/privacy-policy`) and the pages are reachable
/// directly by their address.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 13,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.textSecondary,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        InkWell(
          onTap: () => context.go('/terms-of-service'),
          child: Text(context.t('auth.termsOfService'), style: linkStyle),
        ),
        Text('·', style: TextStyle(color: AppColors.textSecondary)),
        InkWell(
          onTap: () => context.go('/privacy-policy'),
          child: Text(context.t('auth.privacyPolicy'), style: linkStyle),
        ),
      ],
    );
  }
}
