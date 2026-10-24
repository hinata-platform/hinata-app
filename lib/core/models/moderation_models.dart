import 'package:equatable/equatable.dart';

import '../api/api_client.dart' show ApiFailure;

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

  /// Something else for a value this app does not know.
  static ReportCategory of(Object? wire) => values.firstWhere(
    (category) => category.wire == wire,
    orElse: () => ReportCategory.other,
  );
}

/// What the text check says when nothing is stored (HIN-176):
/// `ALLOW`, `FLAG` or `BLOCK`.
enum TextVerdict {
  allow('ALLOW'),
  flag('FLAG'),
  block('BLOCK');

  const TextVerdict(this.wire);

  final String wire;

  static TextVerdict of(Object? wire) => values.firstWhere(
    (verdict) => verdict.wire == wire,
    orElse: () => TextVerdict.allow,
  );
}

/// One find of the text check, with what it weighs where it stands.
class TextFind extends Equatable {
  const TextFind({
    required this.term,
    required this.category,
    required this.weight,
    this.technical = false,
    this.own = false,
  });

  final String term;

  /// The server's name of the category, as [ReportCategory.wire].
  final String category;
  final int weight;

  /// Found in code, a log or an identifier, where it weighs less.
  final bool technical;

  /// One of the administrator's own terms.
  final bool own;

  factory TextFind.fromJson(Map<String, dynamic> json) => TextFind(
    term: json['term'] as String? ?? '',
    category: json['category'] as String? ?? 'OTHER',
    weight: (json['weight'] as num?)?.toInt() ?? 0,
    technical: json['technical'] as bool? ?? false,
    own: json['own'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [term, category, weight, technical, own];
}

/// The answer to "test a text" in Admin → Moderation: what would happen with
/// the settings as they are, what was found whatever the switches say, and
/// the technical words that kept a rule from counting.
class TextCheckResult extends Equatable {
  const TextCheckResult({
    required this.verdict,
    this.terms = const [],
    this.found = const [],
    this.exceptions = const [],
  });

  final TextVerdict verdict;
  final List<String> terms;
  final List<TextFind> found;
  final List<String> exceptions;

  factory TextCheckResult.fromJson(Map<String, dynamic> json) =>
      TextCheckResult(
        verdict: TextVerdict.of(json['verdict']),
        terms: [
          for (final term in (json['terms'] as List<dynamic>?) ?? const [])
            '$term',
        ],
        found: [
          for (final find in (json['found'] as List<dynamic>?) ?? const [])
            TextFind.fromJson(find as Map<String, dynamic>),
        ],
        exceptions: [
          for (final word in (json['exceptions'] as List<dynamic>?) ?? const [])
            '$word',
        ],
      );

  @override
  List<Object?> get props => [verdict, terms, found, exceptions];
}

/// What a report or a mark is about, with the server's name for it (HIN-170).
enum ContentKind {
  issue('ISSUE'),
  comment('COMMENT'),
  attachment('ATTACHMENT'),
  article('ARTICLE'),
  person('PERSON'),
  other('OTHER');

  const ContentKind(this.wire);

  final String wire;

  /// Something else for a value this app does not know.
  static ContentKind of(Object? wire) => values.firstWhere(
    (kind) => kind.wire == wire,
    orElse: () => ContentKind.other,
  );
}

/// What a report names: the kind, the id and, for an attachment or a comment,
/// what it lives in (HIN-170). The server resolves it; nothing here is trusted.
class TargetRef extends Equatable {
  const TargetRef(this.kind, this.id, {this.parentId});

  /// Something that is no post, page or person (HIN-175): it has no id, and
  /// the report names where it is instead.
  static const elsewhere = TargetRef(ContentKind.other, '');

  final ContentKind kind;
  final String id;
  final String? parentId;

  Map<String, dynamic> toJson() => {
    'kind': kind.wire,
    if (id.isNotEmpty) 'id': id,
    'parentId': ?parentId,
  };

  @override
  List<Object?> get props => [kind, id, parentId];
}

/// How the moderation left a field of a content (HIN-171): removed, so the
/// placeholder stands in its place, or written anew, so it shows its text.
enum MarkState {
  removed('REMOVED'),
  rewritten('REWRITTEN');

  const MarkState(this.wire);

  final String wire;

  /// Written anew for a value this app does not know: the field shows its
  /// text, which is what the server sent.
  static MarkState of(Object? wire) => values.firstWhere(
    (state) => state.wire == wire,
    orElse: () => MarkState.rewritten,
  );
}

/// The moderation's mark on one field of a content.
class ContentMark extends Equatable {
  const ContentMark({required this.state, this.caseId, this.at});

  final MarkState state;

  /// The case the decision belongs to, for the notice to the person concerned.
  final String? caseId;
  final DateTime? at;

  bool get removed => state == MarkState.removed;

  factory ContentMark.fromJson(Map<String, dynamic> json) => ContentMark(
    state: MarkState.of(json['state']),
    caseId: json['caseId'] as String?,
    at: parseInstant(json['at']),
  );

  /// The marks of a content by field name, from its `moderation` object; an
  /// older server sends none.
  static Map<String, ContentMark> mapOf(Object? json) => {
    if (json is Map)
      for (final entry in json.entries)
        if (entry.value is Map<String, dynamic>)
          '${entry.key}': ContentMark.fromJson(
            entry.value as Map<String, dynamic>,
          ),
  };

  @override
  List<Object?> get props => [state, caseId, at];
}

/// How much of a content a removal takes (HIN-171): all of it, one field of an
/// issue, a page back to the version before, a person's picture or the words
/// on their profile. A notice names it; none for a suspension alone.
enum RemovalScope {
  whole('WHOLE'),
  title('TITLE'),
  description('DESCRIPTION'),
  revert('REVERT'),
  avatar('AVATAR'),
  profileText('PROFILE_TEXT');

  const RemovalScope(this.wire);

  final String wire;

  static RemovalScope? of(Object? wire) {
    for (final scope in values) {
      if (scope.wire == wire) return scope;
    }
    return null;
  }
}

/// Where an appeal stands.
enum AppealState {
  pending('PENDING'),
  upheld('UPHELD'),
  reversed('REVERSED');

  const AppealState(this.wire);

  final String wire;

  static AppealState? of(Object? wire) {
    for (final state in values) {
      if (state.wire == wire) return state;
    }
    return null;
  }
}

/// The moderation's notice to the person concerned (HIN-171), with every
/// statement DSA Art. 17(3) asks for, in the reader's language as the server
/// wrote it, and where an appeal stands.
class Statement extends Equatable {
  const Statement({
    required this.caseId,
    this.headline = '',
    this.measure = '',
    this.scope,
    this.until,
    this.suspends = false,
    this.basis,
    this.facts,
    this.automatedDetection = false,
    this.automation,
    this.lawGround = false,
    this.groundText,
    this.rulesUrl,
    this.appealUntil,
    this.appealable = false,
    this.appeal,
    this.appealState,
    this.courtsNote,
    this.messageToAuthor,
  });

  final String caseId;
  final String headline;

  /// What was done, how far, and for how long.
  final String measure;
  final RemovalScope? scope;

  /// When a suspension ends; none for none, or for one without an end.
  final DateTime? until;

  /// Whether the decision suspended the account, as the server says it: the
  /// suspension decided, however it stands now, and not a guess from [until],
  /// which is empty for one without an end and for one that ended.
  final bool suspends;

  /// What led to it, and what moderation found.
  final String? basis;
  final String? facts;

  /// Whether a machine found it; the decision is always a person's.
  final bool automatedDetection;
  final String? automation;

  /// Whether it rests on the law rather than on the house rules.
  final bool lawGround;

  /// The rule or the law it rests on, in words.
  final String? groundText;

  /// The house rules as they read when it was decided, as a path of the
  /// server.
  final String? rulesUrl;

  /// Until when the person may appeal, and whether they still may.
  final DateTime? appealUntil;
  final bool appealable;

  /// Where an appeal stands, in words, and as a state.
  final String? appeal;
  final AppealState? appealState;

  final String? courtsNote;

  /// What moderation wrote to the person, if anything.
  final String? messageToAuthor;

  /// This statement with the words a moderator is still typing put in: the
  /// preview while deciding follows every keystroke without asking the server
  /// for each (HIN-174).
  Statement withTexts({
    String? facts,
    String? groundText,
    String? messageToAuthor,
  }) => Statement(
    caseId: caseId,
    headline: headline,
    measure: measure,
    scope: scope,
    until: until,
    suspends: suspends,
    basis: basis,
    facts: facts,
    automatedDetection: automatedDetection,
    automation: automation,
    lawGround: lawGround,
    groundText: groundText,
    rulesUrl: rulesUrl,
    appealUntil: appealUntil,
    appealable: appealable,
    appeal: appeal,
    appealState: appealState,
    courtsNote: courtsNote,
    messageToAuthor: messageToAuthor,
  );

  factory Statement.fromJson(Map<String, dynamic> json) => Statement(
    caseId: json['caseId'] as String? ?? '',
    headline: json['headline'] as String? ?? '',
    measure: json['measure'] as String? ?? '',
    scope: RemovalScope.of(json['scope']),
    until: parseInstant(json['until']),
    suspends: json['suspension'] != null,
    basis: json['basis'] as String?,
    facts: json['facts'] as String?,
    automatedDetection: json['automatedDetection'] as bool? ?? false,
    automation: json['automation'] as String?,
    lawGround: json['ground'] == 'LAW',
    groundText: json['groundText'] as String?,
    rulesUrl: json['rulesUrl'] as String?,
    appealUntil: parseInstant(json['appealUntil']),
    appealable: json['appealable'] as bool? ?? false,
    appeal: json['appeal'] as String?,
    appealState: AppealState.of(json['appealState']),
    courtsNote: json['courtsNote'] as String?,
    messageToAuthor: json['messageToAuthor'] as String?,
  );

  @override
  List<Object?> get props => [
    caseId,
    headline,
    measure,
    scope,
    until,
    suspends,
    basis,
    facts,
    automatedDetection,
    automation,
    lawGround,
    groundText,
    rulesUrl,
    appealUntil,
    appealable,
    appeal,
    appealState,
    courtsNote,
    messageToAuthor,
  ];
}

/// What the server's text check refused (HIN-176), read off a failed save by
/// `details.code`, never by the status alone: a 422 means other things too.
class ContentRefusal extends Equatable {
  const ContentRefusal(this.terms);

  /// The words refused, as the author wrote them; the author may see them.
  final List<String> terms;

  static const code = 'error.moderation.refused';

  /// The refusal in [error], if it is one.
  static ContentRefusal? of(Object? error) {
    if (error is! ApiFailure || error.details['code'] != code) return null;
    final terms = (error.details['terms'] ?? '')
        .split(',')
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList();
    return ContentRefusal(terms);
  }

  @override
  List<Object?> get props => [terms];
}

/// A save that would open a way in without approval, refused until the
/// administrator confirmed what that makes of the instance (HIN-175): which
/// ways.
class OpenAccessRefusal extends Equatable {
  const OpenAccessRefusal(this.ways);

  /// As the server names them: `registration`, `oidc` and so on.
  final List<String> ways;

  static const code = 'error.moderation.openAccessUnconfirmed';

  /// The refusal in [failure], if it is one.
  static OpenAccessRefusal? of(ApiFailure failure) =>
      failure.statusCode == 409 && failure.details['code'] == code
      ? OpenAccessRefusal(
          (failure.details['ways'] ?? '')
              .split(',')
              .where((way) => way.isNotEmpty)
              .toList(),
        )
      : null;

  @override
  List<Object?> get props => [ways];
}

/// Whether [failure] refused a save that would put texts before moderation,
/// until the administrator confirmed that the works council was involved and
/// the impact assessment done (HIN-176).
bool flagConfirmRequired(ApiFailure failure) =>
    failure.statusCode == 409 &&
    failure.details['code'] == 'error.moderation.flagUnconfirmed';
