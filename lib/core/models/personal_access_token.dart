import '../util/dates.dart';

/// The fixed, server-enforced set of scopes a Personal Access Token (PAT) can
/// grant to the embedded MCP server. Friendly labels are looked up per scope via
/// i18n (`pat.scope.<id>` — the `:` is swapped for `_` so it forms a valid
/// i18next key segment; see [patScopeKey]).
const List<String> kPatScopes = [
  'issues:read',
  'issues:write',
  'projects:read',
  'kb:read',
  'kb:write',
  'worklog:write',
  'search:read',
];

/// i18n key segment for a scope id — i18next treats `:` as the namespace
/// separator, so scope ids must be sanitised before use as a key.
String patScopeKey(String scope) => 'pat.scope.${scope.replaceAll(':', '_')}';

/// A Personal Access Token as returned by `GET /api/v1/me/pats` — metadata only,
/// never the secret. Timestamps arrive as ISO-8601 UTC and are parsed to local.
class PersonalAccessToken {
  const PersonalAccessToken({
    required this.id,
    required this.name,
    required this.prefix,
    required this.scopes,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.revoked = false,
  });

  final String id;
  final String name;

  /// The public, non-secret token prefix (e.g. `hnp_ab12`) shown to identify a
  /// token in the list — the plaintext secret is only ever seen once at creation.
  final String prefix;
  final List<String> scopes;
  final DateTime? createdAt;

  /// Null until the token is first used to authenticate.
  final DateTime? lastUsedAt;

  /// Null when the token never expires.
  final DateTime? expiresAt;
  final bool revoked;

  /// Whether the token is past its (non-null) expiry.
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory PersonalAccessToken.fromJson(Map<String, dynamic> json) =>
      PersonalAccessToken(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        prefix: json['prefix'] as String? ?? '',
        scopes: ((json['scopes'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        createdAt: parseInstant(json['createdAt']),
        lastUsedAt: parseInstant(json['lastUsedAt']),
        expiresAt: parseInstant(json['expiresAt']),
        revoked: json['revoked'] as bool? ?? false,
      );
}

/// The response to `POST /api/v1/me/pats` — the one-time plaintext [token] plus
/// the persisted [meta]. The plaintext is never retrievable again.
class CreatedPat {
  const CreatedPat({required this.token, required this.meta});

  final String token;
  final PersonalAccessToken meta;

  factory CreatedPat.fromJson(Map<String, dynamic> json) => CreatedPat(
    token: json['token'] as String? ?? '',
    meta: PersonalAccessToken.fromJson(
      (json['meta'] as Map<String, dynamic>?) ?? const {},
    ),
  );
}
