import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/core_models.dart';

/// Hands a sign-in to [provider] of the server at [serverUrl].
///
/// On the web the whole flow stays in this tab: the server is told where to
/// return, and the flow ends at this origin's `/auth-callback`. Natively the
/// system browser takes it, and the server comes back through the app's own
/// link. [invite] is the token of an invitation the sign-in completes
/// (HIN-179).
///
/// Returns whether the browser took the sign-in.
Future<bool> launchSso(
  String serverUrl,
  SsoProvider provider, {
  String? invite,
}) {
  final uri = ssoStartUri(
    serverUrl,
    provider,
    returnTo: kIsWeb ? Uri.base.origin : null,
    invite: invite,
  );
  return kIsWeb
      ? launchUrl(uri, webOnlyWindowName: '_self')
      : launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Where a sign-in with [provider] starts: [returnTo] is the web app's origin
/// for the server to come back to, [invite] an invitation the sign-in
/// completes.
Uri ssoStartUri(
  String serverUrl,
  SsoProvider provider, {
  String? returnTo,
  String? invite,
}) {
  final uri = Uri.parse('$serverUrl${provider.loginUrl}');
  final extra = {'return': ?returnTo, 'invite': ?invite};
  return extra.isEmpty
      ? uri
      : uri.replace(queryParameters: {...uri.queryParameters, ...extra});
}
