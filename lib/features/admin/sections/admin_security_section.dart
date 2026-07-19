import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../admin_form_helpers.dart';

/// Security hardening settings: password policy, session lifetime, rate limiting.
class AdminSecuritySection extends StatefulWidget {
  const AdminSecuritySection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminSecuritySection> createState() => _AdminSecuritySectionState();
}

class _AdminSecuritySectionState extends State<AdminSecuritySection> {
  Map<String, dynamic> get _sec =>
      (widget.settings['security'] ??= <String, dynamic>{})
          as Map<String, dynamic>;

  int _intVal(String key, int def) => (_sec[key] as int?) ?? def;
  bool _boolVal(String key, {required bool def}) => (_sec[key] as bool?) ?? def;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Password policy ─────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.keyRound,
          title: context.t('admin.passwordPolicy'),
          subtitle: context.t('admin.passwordPolicyHint'),
          children: [
            AdminNumberField(
              label: context.t('admin.passwordMinLength'),
              value: _intVal('passwordMinLength', 10),
              min: 8,
              max: 128,
              suffix: context.t('admin.chars'),
              onChanged: (v) => setState(() => _sec['passwordMinLength'] = v),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ─── Brute-force protection ───────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.shieldX,
          title: context.t('admin.bruteForce'),
          subtitle: context.t('admin.bruteForceHint'),
          children: [
            AdminToggle(
              label: context.t('admin.rateLimitEnabled'),
              subtitle: context.t('admin.rateLimitSubtitle'),
              value: _boolVal('rateLimitEnabled', def: true),
              onChanged: (v) => setState(() => _sec['rateLimitEnabled'] = v),
            ),
            const SizedBox(height: 4),
            AdminNumberField(
              label: context.t('admin.maxLoginAttempts'),
              value: _intVal('maxLoginAttempts', 5),
              min: 1,
              max: 50,
              suffix: context.t('admin.attempts'),
              onChanged: (v) => setState(() => _sec['maxLoginAttempts'] = v),
            ),
            AdminNumberField(
              label: context.t('admin.lockoutMinutes'),
              value: _intVal('lockoutMinutes', 15),
              min: 1,
              max: 1440,
              suffix: context.t('admin.minutes'),
              onChanged: (v) => setState(() => _sec['lockoutMinutes'] = v),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ─── Session ─────────────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.timer,
          title: context.t('admin.sessionPolicy'),
          subtitle: context.t('admin.sessionPolicyHint'),
          children: [
            AdminNumberField(
              label: context.t('admin.sessionLifetime'),
              value: _intVal('sessionLifetimeHours', 168),
              min: 1,
              max: 8760,
              suffix: context.t('admin.hours'),
              onChanged: (v) =>
                  setState(() => _sec['sessionLifetimeHours'] = v),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ─── OWASP info box ──────────────────────────────────────
        AdminNote(
          text: context.t('admin.owaspNote'),
          icon: LucideIcons.shieldCheck,
        ),
      ],
    );
  }
}
