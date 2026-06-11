import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';

/// Edits the SSO blocks of the server settings document in place.
/// Mirrors the backend ServerSettings structure (oidc/oauth2/saml/ldap).
class AdminSsoSection extends StatefulWidget {
  const AdminSsoSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminSsoSection> createState() => _AdminSsoSectionState();
}

class _AdminSsoSectionState extends State<AdminSsoSection> {
  Map<String, dynamic> _section(String name) =>
      (widget.settings[name] ??= <String, dynamic>{}) as Map<String, dynamic>;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('admin.sso'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text(context.t('admin.ssoHint'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        _ProviderTile(
          title: 'OpenID Connect',
          section: _section('oidc'),
          fields: const [
            ('issuerUri', 'Issuer URI', false),
            ('clientId', 'Client ID', false),
            ('clientSecret', 'Client Secret', true),
            ('scopes', 'Scopes', false),
          ],
          onChanged: () => setState(() {}),
        ),
        _ProviderTile(
          title: 'OAuth 2.0',
          section: _section('oauth2'),
          fields: const [
            ('authorizationUri', 'Authorization URI', false),
            ('tokenUri', 'Token URI', false),
            ('userInfoUri', 'User-Info URI', false),
            ('clientId', 'Client ID', false),
            ('clientSecret', 'Client Secret', true),
          ],
          onChanged: () => setState(() {}),
        ),
        _ProviderTile(
          title: 'SAML',
          section: _section('saml'),
          fields: const [
            ('idpMetadataUri', 'IdP Metadata URL', false),
            ('entityId', 'Entity ID', false),
          ],
          onChanged: () => setState(() {}),
        ),
        _ProviderTile(
          title: 'LDAP',
          section: _section('ldap'),
          fields: const [
            ('url', 'URL (ldaps://...)', false),
            ('baseDn', 'Base DN', false),
            ('managerDn', 'Manager DN', false),
            ('managerPassword', 'Manager Password', true),
            ('userSearchBase', 'User Search Base', false),
            ('userSearchFilter', 'User Search Filter', false),
          ],
          onChanged: () => setState(() {}),
        ),
        _ProviderTile(
          title: 'Kerberos',
          section: _section('kerberos'),
          fields: const [
            ('servicePrincipal', 'Service Principal', false),
            ('keytabLocation', 'Keytab Location', false),
          ],
          onChanged: () => setState(() {}),
        ),
        _ProviderTile(
          title: 'CAS',
          section: _section('cas'),
          fields: const [
            ('serverUrlPrefix', 'CAS Server URL', false),
            ('serviceUrl', 'Service URL', false),
          ],
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }
}

class AdminEmailIngestSection extends StatefulWidget {
  const AdminEmailIngestSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminEmailIngestSection> createState() =>
      _AdminEmailIngestSectionState();
}

class _AdminEmailIngestSectionState extends State<AdminEmailIngestSection> {
  @override
  Widget build(BuildContext context) {
    final section = (widget.settings['emailIngest'] ??= <String, dynamic>{})
        as Map<String, dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('admin.emailIngest'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text(context.t('admin.emailIngestHint'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        _ProviderTile(
          title: 'IMAP',
          section: section,
          fields: const [
            ('host', 'Host', false),
            ('username', 'Username', false),
            ('password', 'Password', true),
            ('folder', 'Folder', false),
            ('defaultProjectId', 'Default Project ID', false),
          ],
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }
}

/// Expandable provider block: enable switch + text fields bound to the map.
class _ProviderTile extends StatefulWidget {
  const _ProviderTile({
    required this.title,
    required this.section,
    required this.fields,
    required this.onChanged,
  });

  final String title;
  final Map<String, dynamic> section;

  /// (jsonKey, label, isSecret)
  final List<(String, String, bool)> fields;
  final VoidCallback onChanged;

  @override
  State<_ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends State<_ProviderTile> {
  @override
  Widget build(BuildContext context) {
    final enabled = widget.section['enabled'] == true;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 16),
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        leading: Switch(
          value: enabled,
          activeTrackColor: AppColors.navy,
          onChanged: (value) {
            setState(() => widget.section['enabled'] = value);
            widget.onChanged();
          },
        ),
        children: [
          for (final (key, label, secret) in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextFormField(
                initialValue: (widget.section[key] as String?) ?? '',
                obscureText: secret,
                decoration: InputDecoration(
                  labelText: label,
                  helperText: secret ? context.t('admin.secretHint') : null,
                ),
                onChanged: (value) => widget.section[key] = value,
              ),
            ),
        ],
      ),
    );
  }
}
