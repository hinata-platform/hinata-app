import 'package:equatable/equatable.dart';

/// Server metadata from GET /api/v1/meta (version gate, branding, flags).
class ServerMeta extends Equatable {
  const ServerMeta({
    required this.serverVersion,
    required this.minAppVersion,
    required this.setupCompleted,
    this.organizationName,
    this.privacyPolicyUrl = '',
    this.featureFlags = const {},
  });

  final String serverVersion;
  final String minAppVersion;
  final bool setupCompleted;
  final String? organizationName;
  final String privacyPolicyUrl;
  final Map<String, bool> featureFlags;

  factory ServerMeta.fromJson(Map<String, dynamic> json) => ServerMeta(
        serverVersion: json['serverVersion'] as String? ?? '0.0.0',
        minAppVersion: json['minAppVersion'] as String? ?? '0.0.0',
        setupCompleted: json['setupCompleted'] as bool? ?? false,
        organizationName: json['organizationName'] as String?,
        privacyPolicyUrl: json['privacyPolicyUrl'] as String? ?? '',
        featureFlags: (json['featureFlags'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v == true)),
      );

  bool isFlagEnabled(String flag) => featureFlags[flag] ?? false;

  @override
  List<Object?> get props =>
      [serverVersion, minAppVersion, setupCompleted, organizationName];
}

class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.roles,
    this.avatarUrl,
    this.title,
    this.locale = 'en',
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final Set<String> roles;
  final String? avatarUrl;
  final String? title;
  final String locale;

  bool get isAdmin => roles.contains('ADMIN');

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String? ?? json['username'] as String,
        roles: ((json['roles'] as List<dynamic>?) ?? []).cast<String>().toSet(),
        avatarUrl: json['avatarUrl'] as String?,
        title: json['title'] as String?,
        locale: json['locale'] as String? ?? 'en',
      );

  @override
  List<Object?> get props => [id, email, username, displayName, roles, title];
}

class DirectoryUser extends Equatable {
  const DirectoryUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.title,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? title;

  factory DirectoryUser.fromJson(Map<String, dynamic> json) => DirectoryUser(
        id: json['id'] as String,
        username: json['username'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        title: json['title'] as String?,
      );

  @override
  List<Object?> get props => [id, username, displayName];
}

class SsoProvider extends Equatable {
  const SsoProvider({required this.id, required this.displayName, required this.loginUrl});

  final String id;
  final String displayName;
  final String loginUrl;

  factory SsoProvider.fromJson(Map<String, dynamic> json) => SsoProvider(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? json['id'] as String,
        loginUrl: json['loginUrl'] as String,
      );

  @override
  List<Object?> get props => [id, displayName, loginUrl];
}

/// Compares dotted semantic versions; returns true when [current] < [minimum].
bool isVersionBelow(String current, String minimum) {
  List<int> parse(String v) =>
      v.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9].*'), '')) ?? 0).toList();
  final a = parse(current);
  final b = parse(minimum);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}
