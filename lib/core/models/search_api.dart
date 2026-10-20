/// DTOs for the `/api/v1/search` response (mirrors the server's `SearchHit` /
/// `SearchResponse`). Kept raw — the controller maps these onto [SearchEntry]
/// and composes/localises the display strings client-side.
library;

import '../util/dates.dart';

class SearchApiHit {
  SearchApiHit({
    required this.category,
    required this.id,
    required this.route,
    required this.title,
    this.subtitle,
    this.readableId,
    this.type,
    this.state,
    this.assigneeName,
    this.assigneeAvatarUrl,
    this.avatarUrl,
    this.projectKey,
    this.projectColor,
    this.openCount,
    this.doneCount,
    this.memberNames = const [],
    this.space,
    this.updatedAt,
    this.archived = false,
    this.kind,
    this.username,
    this.key,
    this.projectId,
    this.projectName,
    this.issueId,
    this.authorName,
    this.createdAt,
    this.contentType,
    this.size,
    this.startsAt,
    this.endsAt,
    this.location,
    this.cancelled = false,
    this.from,
    this.to,
    this.minutes,
    this.status,
    this.icon,
    this.hue,
    this.amountCents,
    this.currency,
  });

  final String category;
  final String id;
  final String route;
  final String title;
  final String? subtitle;
  final String? readableId;

  /// Issue type; for a `RATE` the scope it applies to (`PROJECT`, `USER`, …).
  final String? type;
  final String? state;
  final String? assigneeName;
  final String? assigneeAvatarUrl;
  final String? avatarUrl;
  final String? projectKey;
  final String? projectColor;
  final int? openCount;
  final int? doneCount;
  final List<String> memberNames;
  final String? space;
  final DateTime? updatedAt;

  /// Archived (soft-deleted) issue or archived project — badged in the UI.
  final bool archived;

  // ---- since search revision 2 (HIN-165), all optional ----

  /// Which of a category's kinds this is (`BOARD`/`SPRINT`, `ARTICLE`/`SPACE`,
  /// `EVENT`/`SHIFT`, `ENTRY`/`TIMESHEET`, `REQUEST`/`TYPE`, `BUDGET`/`RATE`).
  /// Absent for a category with a single kind.
  final String? kind;
  final String? username;

  /// A team's key (`TEAMS`, and a team rate's team).
  final String? key;
  final String? projectId;
  final String? projectName;
  final String? issueId;
  final String? authorName;

  /// When a comment was written or an attachment uploaded.
  final DateTime? createdAt;
  final String? contentType;

  /// An attachment's size in bytes.
  final int? size;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? location;
  final bool cancelled;

  /// Calendar days (`yyyy-MM-dd`): an entry's day, a timesheet's period, an
  /// absence request's span, a rate's validity (open when [to] is absent).
  final DateTime? from;
  final DateTime? to;
  final int? minutes;

  /// `SUBMITTED`… for a timesheet or an absence request, `BILLABLE`/`COST` for
  /// a rate.
  final String? status;
  final String? icon;
  final int? hue;
  final int? amountCents;
  final String? currency;

  factory SearchApiHit.fromJson(Map<String, dynamic> json) => SearchApiHit(
    category: json['category'] as String? ?? '',
    id: json['id'] as String? ?? '',
    route: json['route'] as String? ?? '/',
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String?,
    readableId: json['readableId'] as String?,
    type: json['type'] as String?,
    state: json['state'] as String?,
    assigneeName: json['assigneeName'] as String?,
    assigneeAvatarUrl: json['assigneeAvatarUrl'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    projectKey: json['projectKey'] as String?,
    projectColor: json['projectColor'] as String?,
    openCount: (json['openCount'] as num?)?.toInt(),
    doneCount: (json['doneCount'] as num?)?.toInt(),
    memberNames: ((json['memberNames'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    space: json['space'] as String?,
    updatedAt: parseInstant(json['updatedAt']),
    archived: json['archived'] as bool? ?? false,
    kind: json['kind'] as String?,
    username: json['username'] as String?,
    key: json['key'] as String?,
    projectId: json['projectId'] as String?,
    projectName: json['projectName'] as String?,
    issueId: json['issueId'] as String?,
    authorName: json['authorName'] as String?,
    createdAt: parseInstant(json['createdAt']),
    contentType: json['contentType'] as String?,
    size: (json['size'] as num?)?.toInt(),
    startsAt: parseInstant(json['startsAt']),
    endsAt: parseInstant(json['endsAt']),
    location: json['location'] as String?,
    cancelled: json['cancelled'] as bool? ?? false,
    from: parseDate(json['from']),
    to: parseDate(json['to']),
    minutes: (json['minutes'] as num?)?.toInt(),
    status: json['status'] as String?,
    icon: json['icon'] as String?,
    hue: (json['hue'] as num?)?.toInt(),
    amountCents: (json['amountCents'] as num?)?.toInt(),
    currency: json['currency'] as String?,
  );
}

class SearchApiGroup {
  SearchApiGroup({required this.category, required this.items});
  final String category;
  final List<SearchApiHit> items;

  factory SearchApiGroup.fromJson(Map<String, dynamic> json) => SearchApiGroup(
    category: json['category'] as String? ?? '',
    items: ((json['items'] as List<dynamic>?) ?? const [])
        .map((e) => SearchApiHit.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class SearchApiResponse {
  SearchApiResponse({
    required this.groups,
    required this.counts,
    this.cappedCounts = const {},
  });
  final List<SearchApiGroup> groups;

  /// Total entity count per category (UPPERCASE keys), for the chip badges.
  /// Only for a blank query; a category of a module that is off is absent.
  final Map<String, int> counts;

  /// Categories whose count stopped at the server's ceiling: the number is a
  /// lower bound and reads "99+".
  final Set<String> cappedCounts;

  factory SearchApiResponse.fromJson(Map<String, dynamic> json) =>
      SearchApiResponse(
        groups: ((json['groups'] as List<dynamic>?) ?? const [])
            .map((e) => SearchApiGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        counts: ((json['counts'] as Map<String, dynamic>?) ?? const {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
        cappedCounts: ((json['cappedCounts'] as List<dynamic>?) ?? const [])
            .map((e) => '$e'.toUpperCase())
            .toSet(),
      );
}
