/// The pending OAuth 2.1 authorization request an AI client (e.g. Claude) is
/// asking the signed-in user to approve, as returned by
/// `GET /api/v1/oauth/consent/{requestId}`.
///
/// The backend 302-redirects the browser to the web app at
/// `/oauth-consent?request_id=<id>`; the consent screen fetches this record to
/// render the client name, the target redirect host and the requested scopes
/// (the same scope ids used by Personal Access Tokens — see [patScopeKey]).
class OAuthConsentInfo {
  const OAuthConsentInfo({
    required this.requestId,
    required this.clientName,
    required this.redirectHost,
    required this.scopes,
  });

  final String requestId;

  /// Human-readable name of the requesting client (e.g. "Claude").
  final String clientName;

  /// The host the browser will be sent back to on a decision (e.g. `claude.ai`)
  /// — shown so the user can sanity-check where they're granting access.
  final String redirectHost;

  /// The requested scope ids (e.g. `issues:read`); friendly labels resolve via
  /// `pat.scope.*` i18n keys.
  final List<String> scopes;

  factory OAuthConsentInfo.fromJson(Map<String, dynamic> json) =>
      OAuthConsentInfo(
        requestId: json['requestId'] as String? ?? '',
        clientName: json['clientName'] as String? ?? '',
        redirectHost: json['redirectHost'] as String? ?? '',
        scopes: ((json['scopes'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
      );
}
