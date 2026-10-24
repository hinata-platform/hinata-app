import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// How an instance words its house rules (HIN-175): the text the server ships
/// in nine languages, a text of its own, or a page elsewhere. "How we
/// moderate" follows each of them.
enum HouseRulesMode {
  builtIn('BUILT_IN'),
  text('TEXT'),
  url('URL');

  const HouseRulesMode(this.wire);

  final String wire;

  /// Built in for a value this app does not know: the server always appends
  /// its own section, so the rules still read whole.
  static HouseRulesMode of(Object? wire) => values.firstWhere(
    (mode) => mode.wire == wire,
    orElse: () => HouseRulesMode.builtIn,
  );
}

/// The current house rules as the signed-in person reads them
/// (`GET /api/v1/me/rules`), in their language.
class HouseRules extends Equatable {
  const HouseRules({
    required this.version,
    required this.markdown,
    this.mode = HouseRulesMode.builtIn,
    this.url,
    this.createdAt,
    this.pending = false,
    this.acceptedVersion,
    this.acceptedAt,
  });

  /// The version to accept; only the current one counts.
  final int version;

  /// The rules with "How we moderate" at the end, as Markdown.
  final String markdown;

  final HouseRulesMode mode;

  /// Where the instance keeps its own rules, in [HouseRulesMode.url].
  final String? url;

  /// Since when this version holds.
  final DateTime? createdAt;

  /// Whether this person still has to accept them before going on.
  final bool pending;

  /// The last version this person accepted, and when.
  final int? acceptedVersion;
  final DateTime? acceptedAt;

  factory HouseRules.fromJson(Map<String, dynamic> json) => HouseRules(
    version: (json['version'] as num).toInt(),
    markdown: json['markdown'] as String? ?? '',
    mode: HouseRulesMode.of(json['mode']),
    url: json['url'] as String?,
    createdAt: parseInstant(json['createdAt']),
    pending: json['pending'] as bool? ?? false,
    acceptedVersion: (json['acceptedVersion'] as num?)?.toInt(),
    acceptedAt: parseInstant(json['acceptedAt']),
  );

  @override
  List<Object?> get props => [
    version,
    markdown,
    mode,
    url,
    createdAt,
    pending,
    acceptedVersion,
    acceptedAt,
  ];
}

/// The house rules as the admin area shows them
/// (`GET /api/v1/admin/moderation/rules`): which version holds since when,
/// and the last one everybody had to accept anew.
class HouseRulesVersions extends Equatable {
  const HouseRulesVersions({
    this.version,
    this.since,
    this.requiredVersion,
    this.publicUrl,
  });

  final int? version;
  final DateTime? since;
  final int? requiredVersion;

  /// The public page of the current version, for anybody without an account.
  final String? publicUrl;

  factory HouseRulesVersions.fromJson(Map<String, dynamic> json) =>
      HouseRulesVersions(
        version: (json['version'] as num?)?.toInt(),
        since: parseInstant(json['since']),
        requiredVersion: (json['requiredVersion'] as num?)?.toInt(),
        publicUrl: json['publicUrl'] as String?,
      );

  @override
  List<Object?> get props => [version, since, requiredVersion, publicUrl];
}

/// A way in that lets people in without anybody deciding (HIN-175): the
/// registration, or an SSO provider that creates active accounts.
class OpenWay extends Equatable {
  const OpenWay({required this.way, this.name});

  /// `registration`, `oidc`, `oauth2`, `saml` or `ldap`.
  final String way;

  /// The provider's name as the sign-in page shows it; none for the
  /// registration.
  final String? name;

  factory OpenWay.fromJson(Map<String, dynamic> json) =>
      OpenWay(way: json['way'] as String? ?? '', name: json['name'] as String?);

  @override
  List<Object?> get props => [way, name];
}

/// Who comes in, as Admin → Moderation shows it first
/// (`GET /api/v1/admin/moderation/entry`).
class AccountEntry extends Equatable {
  const AccountEntry({this.openWays = const [], this.proxyNotTrusted = false});

  final List<OpenWay> openWays;

  /// Requests come through a proxy the server does not trust, so every
  /// client counts as the proxy's address.
  final bool proxyNotTrusted;

  factory AccountEntry.fromJson(Map<String, dynamic> json) => AccountEntry(
    openWays: [
      for (final way in (json['openWays'] as List<dynamic>?) ?? const [])
        OpenWay.fromJson(way as Map<String, dynamic>),
    ],
    proxyNotTrusted: json['proxyNotTrusted'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [openWays, proxyNotTrusted];
}

/// Why something is reported, in the order the report sheet lists them, with
/// the server's name for each (HIN-170).
enum ReportCategory {
  harassment('HARASSMENT'),
  threat('THREAT', urgent: true),
  sexual('SEXUAL'),
  childSafety('CHILD_SAFETY', urgent: true, needsExplanation: true),
  privacy('PRIVACY'),
  spam('SPAM'),
  illegal('ILLEGAL', needsExplanation: true),
  other('OTHER', needsExplanation: true);

  const ReportCategory(
    this.wire, {
    this.urgent = false,
    this.needsExplanation = false,
  });

  final String wire;

  /// Looked at first, before anything else waiting.
  final bool urgent;

  /// The server asks for a reason of at least [explanationMin] characters.
  final bool needsExplanation;

  static const explanationMin = 10;
  static const explanationMax = 1000;
}
