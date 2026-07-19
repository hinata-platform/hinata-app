import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import '../blocs/app_config_bloc.dart';
import '../i18n/i18n.dart';
import '../storage/app_storage.dart';

/// Validates a deep-link `server` parameter. Requires an absolute **https** URL
/// with a host; returns the normalized origin, or `null` when the value is
/// missing/malformed/non-https (which must never be trusted).
String? normalizeServerLink(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !uri.isAbsolute ||
      uri.scheme != 'https' ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.origin;
}

/// Safely applies the backend named in an auth deep link (`/invite`,
/// `/reset-password`, `/verify-email`).
///
/// A crafted link could otherwise silently repoint the app at an attacker
/// backend and phish credentials/tokens. So: a non-https/invalid value is
/// ignored; a value that equals the current or an already-saved server is
/// applied silently; anything else requires explicit user confirmation before
/// switching.
Future<void> applyServerFromLink(BuildContext context, String? raw) async {
  final server = normalizeServerLink(raw);
  final storage = context.read<AppStorage>();
  if (server == null) {
    if (raw != null && raw.isNotEmpty && context.mounted) {
      showGlassToast(
        context,
        context.t('auth.serverLink.invalid'),
        kind: GlassToastKind.error,
      );
    }
    return;
  }
  final trusted =
      server == storage.serverUrl ||
      storage.servers.any((p) => p.url == server);
  if (!trusted) {
    final ok = await showGlassConfirm(
      context,
      icon: LucideIcons.serverCog,
      title: context.t('auth.serverLink.title'),
      message: context.t(
        'auth.serverLink.body',
        variables: {'host': Uri.parse(server).host},
      ),
      confirmLabel: context.t('auth.serverLink.confirm'),
    );
    if (ok != true) return;
  }
  if (!context.mounted) return;
  if (storage.serverUrl != server) {
    await storage.setServerUrl(server);
    if (context.mounted) {
      context.read<AppConfigBloc>().add(ServerUrlSubmitted(server));
    }
  }
}
