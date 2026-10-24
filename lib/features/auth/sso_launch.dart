import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/core_models.dart';
import '../../core/storage/app_storage.dart';

/// Hands a sign-in to [provider] of the server [storage] is connected to.
///
/// On the web the whole flow stays in this tab: the server is told where to
/// return, and the flow ends at this origin's `/auth-callback`. Natively the
/// system browser takes it, and the server comes back through the app's own
/// link. [invite] is the token of an invitation the sign-in completes
/// (HIN-179).
///
/// Returns whether the browser took the sign-in.
Future<bool> launchSso(
  AppStorage storage,
  SsoProvider provider, {
  String? invite,
}) async {
  final uri = await prepareSso(storage, provider, invite: invite);
  return kIsWeb
      ? launchUrl(uri, webOnlyWindowName: '_self')
      : launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Where a sign-in with [provider] starts, with a fresh verifier kept in
/// [storage] for its callback.
///
/// The start carries only the verifier's challenge, and the server hands the
/// code of the sign-in to nobody without the verifier: a link carrying the
/// code, opened anywhere but here, signs no one in.
Future<Uri> prepareSso(
  AppStorage storage,
  SsoProvider provider, {
  String? invite,
}) async {
  final verifier = newSsoVerifier();
  await storage.setPendingSsoVerifier(verifier);
  return ssoStartUri(
    storage.serverUrl ?? '',
    provider,
    returnTo: kIsWeb ? Uri.base.origin : null,
    invite: invite,
    challenge: ssoChallengeOf(verifier),
  );
}

/// Where a sign-in with [provider] starts: [returnTo] is the web app's origin
/// for the server to come back to, [invite] an invitation the sign-in
/// completes, [challenge] what binds its code to this device.
Uri ssoStartUri(
  String serverUrl,
  SsoProvider provider, {
  String? returnTo,
  String? invite,
  String? challenge,
}) {
  final uri = Uri.parse('$serverUrl${provider.loginUrl}');
  final extra = {
    'return': ?returnTo,
    'invite': ?invite,
    'challenge': ?challenge,
  };
  return extra.isEmpty
      ? uri
      : uri.replace(queryParameters: {...uri.queryParameters, ...extra});
}

/// A fresh verifier (RFC 7636): 32 random bytes, base64url without padding.
String newSsoVerifier() {
  final random = Random.secure();
  return _base64Url(List<int>.generate(32, (_) => random.nextInt(256)));
}

/// The S256 challenge of [verifier], as the server computes it.
String ssoChallengeOf(String verifier) =>
    _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
