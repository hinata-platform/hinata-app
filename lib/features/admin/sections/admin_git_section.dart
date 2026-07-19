import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/git_dev_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import '../../git/widgets/provider_glyph.dart';
import '../admin_form_helpers.dart';

/// Admin → Git integration.
///
/// Configures the server-side plumbing that turns the emulated demo mode into a
/// real integration: one OAuth app per provider (client id + secret), the public
/// webhook base URL and the token-encryption secret. Everything is stored in the
/// shared admin-settings draft under the `git` key and persisted by the shell's
/// Save button; secrets are WRITE_ONLY (blank = keep stored), and the read-only
/// `*Configured` flags come back from the server so each provider can show
/// whether it is live or still emulated.
class AdminGitSection extends StatelessWidget {
  const AdminGitSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  Map<String, dynamic> get _git =>
      (settings['gitIntegration'] ??= <String, dynamic>{})
          as Map<String, dynamic>;

  bool _flag(String key) => _git[key] == true;

  @override
  Widget build(BuildContext context) {
    final git = _git;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminNote(text: context.t('admin.gitHint')),
        const SizedBox(height: 16),

        // ── Provider OAuth apps ───────────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.gitBranch,
          title: context.t('admin.gitProvidersTitle'),
          subtitle: context.t('admin.gitProvidersHint'),
          children: [
            _GitProviderBlock(
              provider: GitProvider.github,
              name: 'GitHub',
              idKey: 'githubClientId',
              secretKey: 'githubClientSecret',
              live: _flag('githubConfigured'),
              scopes: const ['repo', 'read:org'],
              git: git,
            ),
            _GitProviderBlock(
              provider: GitProvider.gitlab,
              name: 'GitLab',
              idKey: 'gitlabClientId',
              secretKey: 'gitlabClientSecret',
              live: _flag('gitlabConfigured'),
              scopes: const ['api', 'read_repository', 'write_repository'],
              git: git,
            ),
            _GitProviderBlock(
              provider: GitProvider.bitbucket,
              name: 'Bitbucket',
              idKey: 'bitbucketClientId',
              secretKey: 'bitbucketClientSecret',
              live: _flag('bitbucketConfigured'),
              scopes: const ['repository', 'pullrequest', 'webhook'],
              git: git,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Webhooks & encryption ─────────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.webhook,
          title: context.t('admin.gitWebhookTitle'),
          subtitle: context.t('admin.gitWebhookHint'),
          children: [
            AdminField(
              label: context.t('admin.gitWebhookUrl'),
              initialValue: (git['webhookBaseUrl'] as String?) ?? '',
              hint: 'https://track.example.com/api/v1',
              keyboardType: TextInputType.url,
              onChanged: (v) => git['webhookBaseUrl'] = v,
            ),
            AdminField(
              label: context.t('admin.gitTokenSecret'),
              initialValue: '',
              isSecret: true,
              hint: context.t('admin.gitTokenSecretHint'),
              onChanged: (v) => git['tokenSecret'] = v,
            ),
            _TokenSecretStatus(configured: _flag('tokenSecretConfigured')),
            const SizedBox(height: 10),
            AdminNote(
              text: context.t('admin.gitTokenSecretWarning'),
              icon: LucideIcons.triangleAlert,
              tone: AdminNoteTone.warning,
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────── Provider block ──────────────────────────────

/// One provider's OAuth-app credentials, in a collapsible tile that mirrors the
/// SSO `ProviderTile` shape but leads with the brand glyph + a live/demo status
/// pill instead of an enable switch (a provider is "enabled" by having creds).
class _GitProviderBlock extends StatelessWidget {
  const _GitProviderBlock({
    required this.provider,
    required this.name,
    required this.idKey,
    required this.secretKey,
    required this.live,
    required this.scopes,
    required this.git,
  });

  final GitProvider provider;
  final String name;
  final String idKey;
  final String secretKey;
  final bool live;
  final List<String> scopes;
  final Map<String, dynamic> git;

  @override
  Widget build(BuildContext context) {
    // The tinted surface is a Material (not a plain Container) so the inner
    // ListTile's ink/background paints correctly and Flutter raises no
    // "background may be invisible" assertion.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceMuted,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: live ? AppColors.accentLine : AppColors.hairline2,
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            // Demo providers start open to invite configuration; live ones collapse.
            initiallyExpanded: !live,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
            title: Row(
              children: [
                ProviderGlyph(provider: provider, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        provider.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.inkFaint,
                          fontFamily: AppTheme.fontMono,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(live: live),
              ],
            ),
            children: [
              AdminField(
                label: context.t('admin.gitClientId'),
                initialValue: (git[idKey] as String?) ?? '',
                onChanged: (v) => git[idKey] = v,
              ),
              AdminField(
                label: context.t('admin.gitClientSecret'),
                initialValue: '',
                isSecret: true,
                onChanged: (v) => git[secretKey] = v,
              ),
              _ScopeRow(scopes: scopes),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Small pieces ────────────────────────────────

/// Live (green) / Demo (amber) status pill, hue-driven so it stays theme-aware.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final hue = live ? 155 : 45;
    final label = context.t(
      live ? 'admin.gitStatusLive' : 'admin.gitStatusDemo',
    );
    // Capped width + a Flexible label so an over-long status can never push the
    // provider-tile header past its bounds; it ellipsizes inside the pill. The
    // cap is small enough that the fixed header parts (glyph + pill) still fit a
    // cramped tablet split-pane, letting the name Expanded absorb the rest.
    return Container(
      constraints: const BoxConstraints(maxWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: hueSoft(hue),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: hueBorder(hue)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: hueColor(hue),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: hueChipText(hue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Requested OAuth scopes as reflowing mono chips (never overflows).
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({required this.scopes});

  final List<String> scopes;

  @override
  Widget build(BuildContext context) {
    // Label stacked above the chips: a horizontal layout can never overflow, and
    // the chips reflow onto as many rows as the width needs.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('admin.gitScopes'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final scope in scopes)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.hairline2),
                ),
                child: Text(
                  scope,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: AppTheme.fontMono,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Token-secret effective status: custom secret set (green) vs default (amber).
class _TokenSecretStatus extends StatelessWidget {
  const _TokenSecretStatus({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final hue = configured ? 155 : 45;
    final label = context.t(
      configured ? 'admin.gitTokenSecretSet' : 'admin.gitTokenSecretDefault',
    );
    return Row(
      children: [
        Icon(
          configured ? LucideIcons.circleCheck : LucideIcons.circleAlert,
          size: 14,
          color: hueInk(hue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}
