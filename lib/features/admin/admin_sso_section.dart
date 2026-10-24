import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/moderation_models.dart' show OpenWay;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import 'admin_form_helpers.dart';
import 'sections/admin_moderation_entry.dart';

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

  /// Which attribute of the directory carries which profile field. Shared by
  /// every provider so an account arrives with a real name and position instead
  /// of just an address — see [ProviderTile.note] for the syntax.
  List<(String, String, bool)> get _mappingFields => [
    ('emailAttribute', context.t('admin.ssoField.emailAttribute'), false),
    (
      'displayNameAttribute',
      context.t('admin.ssoField.displayNameAttribute'),
      false,
    ),
    ('titleAttribute', context.t('admin.ssoField.titleAttribute'), false),
  ];

  List<(String, String)> get _mappingToggles => [
    ('syncProfileOnLogin', context.t('admin.ssoField.syncProfileOnLogin')),
  ];

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
              note: context.t('admin.ssoMappingHint'),
              footer: _ProviderAdmission(
                way: 'oidc',
                section: _section('oidc'),
                onChanged: () => setState(() {}),
              ),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                ('issuerUri', context.t('admin.ssoField.issuerUri'), false),
                ('clientId', context.t('admin.ssoField.clientId'), false),
                (
                  'clientSecret',
                  context.t('admin.ssoField.clientSecret'),
                  true,
                ),
                ('scopes', context.t('admin.ssoField.scopes'), false),
                ..._mappingFields,
              ],
              toggles: _mappingToggles,
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'OAuth 2.0',
              subtitle: context.t('admin.oauth2Subtitle'),
              section: _section('oauth2'),
              note: context.t('admin.ssoMappingHint'),
              footer: _ProviderAdmission(
                way: 'oauth2',
                section: _section('oauth2'),
                onChanged: () => setState(() {}),
              ),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                (
                  'authorizationUri',
                  context.t('admin.ssoField.authorizationUri'),
                  false,
                ),
                ('tokenUri', context.t('admin.ssoField.tokenUri'), false),
                ('userInfoUri', context.t('admin.ssoField.userInfoUri'), false),
                ('clientId', context.t('admin.ssoField.clientId'), false),
                (
                  'clientSecret',
                  context.t('admin.ssoField.clientSecret'),
                  true,
                ),
                ..._mappingFields,
              ],
              toggles: _mappingToggles,
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'SAML 2.0',
              subtitle: context.t('admin.samlSubtitle'),
              section: _section('saml'),
              note: context.t('admin.ssoMappingHint'),
              footer: _ProviderAdmission(
                way: 'saml',
                section: _section('saml'),
                onChanged: () => setState(() {}),
              ),
              fields: [
                ('displayName', context.t('admin.displayName'), false),
                (
                  'idpMetadataUri',
                  context.t('admin.ssoField.idpMetadataUri'),
                  false,
                ),
                ('entityId', context.t('admin.ssoField.entityId'), false),
                ..._mappingFields,
              ],
              toggles: _mappingToggles,
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'LDAP / Active Directory',
              subtitle: context.t('admin.ldapSubtitle'),
              section: _section('ldap'),
              note: context.t('admin.ssoMappingHint'),
              footer: _ProviderAdmission(
                way: 'ldap',
                section: _section('ldap'),
                onChanged: () => setState(() {}),
              ),
              fields: [
                ('url', context.t('admin.ssoField.ldapUrl'), false),
                ('baseDn', context.t('admin.ssoField.baseDn'), false),
                ('managerDn', context.t('admin.ssoField.managerDn'), false),
                (
                  'managerPassword',
                  context.t('admin.ssoField.managerPassword'),
                  true,
                ),
                (
                  'userSearchBase',
                  context.t('admin.ssoField.userSearchBase'),
                  false,
                ),
                (
                  'userSearchFilter',
                  context.t('admin.ssoField.userSearchFilter'),
                  false,
                ),
                ..._mappingFields,
              ],
              toggles: _mappingToggles,
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'Kerberos / SPNEGO',
              subtitle: context.t('admin.kerberosSubtitle'),
              section: _section('kerberos'),
              fields: [
                (
                  'servicePrincipal',
                  context.t('admin.ssoField.servicePrincipal'),
                  false,
                ),
                (
                  'keytabLocation',
                  context.t('admin.ssoField.keytabLocation'),
                  false,
                ),
              ],
              onChanged: () => setState(() {}),
            ),
            ProviderTile(
              title: 'CAS',
              subtitle: context.t('admin.casSubtitle'),
              section: _section('cas'),
              fields: [
                (
                  'serverUrlPrefix',
                  context.t('admin.ssoField.casServerUrl'),
                  false,
                ),
                ('serviceUrl', context.t('admin.ssoField.serviceUrl'), false),
              ],
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ],
    );
  }
}

/// Who a first sign-in through this provider lets in (HIN-175): with approval
/// it waits like a registration, with named domains only those come in
/// straight away. With neither, the line below says what that means.
class _ProviderAdmission extends StatefulWidget {
  const _ProviderAdmission({
    required this.way,
    required this.section,
    required this.onChanged,
  });

  /// The provider's settings block, which is also its name for the server.
  final String way;
  final Map<String, dynamic> section;
  final VoidCallback onChanged;

  @override
  State<_ProviderAdmission> createState() => _ProviderAdmissionState();
}

class _ProviderAdmissionState extends State<_ProviderAdmission> {
  static const _domainsMax = 50;

  String get _domains =>
      ((widget.section['allowedDomains'] as List?) ?? const [])
          .whereType<String>()
          .join(', ');

  /// Commas, spaces or new lines between them; a leading @ is dropped.
  void _putDomains(String text) {
    widget.section['allowedDomains'] = [
      for (final part in text.split(RegExp(r'[,;\s]+')))
        if (part.replaceFirst('@', '').trim().toLowerCase() case final domain
            when domain.isNotEmpty)
          domain,
    ].take(_domainsMax).toList();
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToggle(
          label: context.t('admin.ssoApproval.title'),
          subtitle: context.t('admin.ssoApproval.hint'),
          value: section['requireApproval'] == true,
          onChanged: (value) {
            setState(() => section['requireApproval'] = value);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: _domains,
          autocorrect: false,
          keyboardType: TextInputType.url,
          style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
          decoration: adminInputDecoration(
            context,
            label: context.t('admin.ssoApproval.domains'),
            hint: 'example.org',
            helper: context.t('admin.ssoApproval.domainsHint'),
          ),
          onChanged: _putDomains,
        ),
        if (providerIsOpen(section)) ...[
          const SizedBox(height: 10),
          OpenWayLine(
            way: OpenWay(
              way: widget.way,
              name: section['displayName'] as String?,
            ),
          ),
        ],
      ],
    );
  }
}
