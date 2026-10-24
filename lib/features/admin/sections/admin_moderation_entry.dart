import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../admin_form_helpers.dart';

/// Who comes in without anybody deciding, as Admin → Moderation shows it
/// first (HIN-175). Null while it is read, and when it could not be: the
/// card is a warning, and a failed read is no reason to raise one.
class AccountEntryCubit extends Cubit<AccountEntry?> {
  AccountEntryCubit(this._admin) : super(null);

  final AdminRepository _admin;

  Future<void> load() async {
    try {
      emit(await _admin.accountEntry());
    } catch (_) {
      // An older server, a refusal or a body this build cannot read: no
      // warning is better than a wrong one.
      emit(null);
    }
  }
}

/// The name of [way] in a sentence: the registration, or the provider by the
/// name its sign-in button shows.
String openWayName(BuildContext context, OpenWay way) =>
    way.way == 'registration'
    ? context.t('admin.entry.way.registration')
    : (way.name == null || way.name!.isEmpty
          ? way.way.toUpperCase()
          : way.name!);

/// One sentence per way that lets people in without approval.
String openWaySentence(BuildContext context, OpenWay way) =>
    way.way == 'registration'
    ? context.t('admin.entry.registration')
    : context.t(
        'admin.entry.provider',
        variables: {'name': openWayName(context, way)},
      );

/// Switches approval on in [settings] for every way in [ways], as their own
/// switches would.
void requireApprovalIn(Map<String, dynamic> settings, List<OpenWay> ways) {
  Map<String, dynamic> block(String name) =>
      (settings[name] ??= <String, dynamic>{}) as Map<String, dynamic>;
  for (final way in ways) {
    if (way.way == 'registration') {
      block('app')['requireAdminApproval'] = true;
    } else {
      block(way.way)['requireApproval'] = true;
    }
  }
}

/// The card at the top of Admin → Moderation while a way is open, and the
/// note about a proxy the server does not trust.
class AccountEntryNotice extends StatelessWidget {
  const AccountEntryNotice({
    super.key,
    required this.entry,
    required this.settings,
    required this.onSave,
  });

  final AccountEntry entry;
  final Map<String, dynamic> settings;

  /// Saves the settings draft as the Save action does; true once it is saved.
  final Future<bool> Function() onSave;

  Future<void> _close(BuildContext context) async {
    final entries = context.read<AccountEntryCubit>();
    requireApprovalIn(settings, entry.openWays);
    if (await onSave()) await entries.load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (entry.openWays.isNotEmpty)
        AdminSectionCard(
          icon: LucideIcons.doorOpen,
          title: context.t('admin.entry.title'),
          children: [
            AdminNote(
              text: [
                for (final way in entry.openWays) openWaySentence(context, way),
                context.t('admin.entry.consequence'),
              ].join(' '),
              icon: LucideIcons.triangleAlert,
              tone: AdminNoteTone.warning,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => unawaited(_close(context)),
                icon: const Icon(LucideIcons.userCheck, size: 16),
                label: Text(context.t('admin.entry.enable')),
              ),
            ),
          ],
        ),
      if (entry.openWays.isNotEmpty && entry.proxyNotTrusted)
        const SizedBox(height: 12),
      if (entry.proxyNotTrusted)
        AdminNote(
          text: context.t('admin.entry.proxy'),
          icon: LucideIcons.network,
          tone: AdminNoteTone.warning,
        ),
    ],
  );
}

/// Whether [entry] has anything to show.
bool accountEntryWorthShowing(AccountEntry? entry) =>
    entry != null && (entry.openWays.isNotEmpty || entry.proxyNotTrusted);

/// What the Moderation card says under each way's own switches, while it lets
/// people in without approval (HIN-175).
class OpenWayLine extends StatelessWidget {
  const OpenWayLine({super.key, required this.way});

  final OpenWay way;

  @override
  Widget build(BuildContext context) => AdminNote(
    text:
        '${openWaySentence(context, way)} ${context.t('admin.entry.consequence')}',
    icon: LucideIcons.triangleAlert,
    tone: AdminNoteTone.warning,
  );
}

/// The SSO providers that can let people in without approval, by the name
/// of their settings block. Kerberos and CAS cannot: their first sign-in
/// always waits.
const providerWays = ['oidc', 'oauth2', 'saml', 'ldap'];

/// Whether the provider settings [provider] let in whoever the provider
/// knows: switched on, without approval and without named domains.
bool providerIsOpen(Map<String, dynamic> provider) {
  final domains = provider['allowedDomains'];
  return provider['enabled'] == true &&
      provider['requireApproval'] != true &&
      (domains is! List ||
          domains.whereType<String>().every((d) => d.trim().isEmpty));
}

/// Whether the `app` block [app] lets anybody register without approval.
bool registrationIsOpen(Map<String, dynamic> app) =>
    app['localAuthEnabled'] != false &&
    app['registrationEnabled'] != false &&
    app['requireAdminApproval'] != true;
