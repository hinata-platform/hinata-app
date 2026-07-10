import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import 'admin_form_helpers.dart';

/// SSO provider configuration (OIDC, OAuth2, SAML, LDAP, Kerberos, CAS).
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
        AdminSectionCard(
          icon: LucideIcons.lock,
          title: context.t('admin.sso'),
          subtitle: context.t('admin.ssoHint'),
          children: [
            ProviderTile(
              title: 'OpenID Connect',
              subtitle: context.t('admin.oidcSubtitle'),
              section: _section('oidc'),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                ('issuerUri', 'Issuer URI', false),
                ('clientId', 'Client ID', false),
                ('clientSecret', 'Client Secret', true),
                ('scopes', 'Scopes', false),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'OAuth 2.0',
              subtitle: context.t('admin.oauth2Subtitle'),
              section: _section('oauth2'),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                ('authorizationUri', 'Authorization URI', false),
                ('tokenUri', 'Token URI', false),
                ('userInfoUri', 'User-Info URI', false),
                ('clientId', 'Client ID', false),
                ('clientSecret', 'Client Secret', true),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'SAML 2.0',
              subtitle: context.t('admin.samlSubtitle'),
              section: _section('saml'),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                ('idpMetadataUri', 'IdP Metadata URL', false),
                ('entityId', 'Entity ID', false),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'LDAP / Active Directory',
              subtitle: context.t('admin.ldapSubtitle'),
              section: _section('ldap'),
              fields: const [
                ('url', 'URL (ldaps://…)', false),
                ('baseDn', 'Base DN', false),
                ('managerDn', 'Manager DN', false),
                ('managerPassword', 'Manager Password', true),
                ('userSearchBase', 'User Search Base', false),
                ('userSearchFilter', 'User Search Filter', false),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'Kerberos / SPNEGO',
              subtitle: context.t('admin.kerberosSubtitle'),
              section: _section('kerberos'),
              fields: const [
                ('servicePrincipal', 'Service Principal', false),
                ('keytabLocation', 'Keytab Location', false),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'CAS',
              subtitle: context.t('admin.casSubtitle'),
              section: _section('cas'),
              fields: const [
                ('serverUrlPrefix', 'CAS Server URL', false),
                ('serviceUrl', 'Service URL', false),
              ],
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ],
    );
  }
}
