import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// Shared entries (HIN-95): an invitation to copy one entry into somebody
/// else's own record.
///
/// The recipient sees the invitation and never the sender's entry; accepting
/// files a copy that is theirs alone. The server decides what each side may
/// read — [entryId] arrives only for the sender, [copyId] only for the
/// recipient, and the project's and issue's names only while the reader can
/// see the project.

/// Where an invitation stands.
enum TimeShareStatus {
  pending,
  accepted,
  declined,
  revoked;

  static TimeShareStatus parse(String? raw) => switch (raw) {
    'ACCEPTED' => TimeShareStatus.accepted,
    'DECLINED' => TimeShareStatus.declined,
    'REVOKED' => TimeShareStatus.revoked,
    _ => TimeShareStatus.pending,
  };

  /// The i18n key of the state's name.
  String get labelKey => 'time.share.status.$name';
}

/// Which side of the invitations a list shows.
enum TimeShareBox {
  /// Waiting for the reader's answer.
  inbox,

  /// What the reader offered, in every state.
  sent;

  String get wire => name;
}

/// A person an invitation names.
class TimeSharePerson extends Equatable {
  const TimeSharePerson({required this.id, this.name});

  final String id;

  /// Null for an account deleted since.
  final String? name;

  factory TimeSharePerson.fromJson(Map<String, dynamic>? json) =>
      TimeSharePerson(
        id: json?['id'] as String? ?? '',
        name: json?['name'] as String?,
      );

  @override
  List<Object?> get props => [id, name];
}

/// One invitation as its reader sees it, with the entry as it was offered.
class TimeEntryShare extends Equatable {
  const TimeEntryShare({
    required this.id,
    required this.status,
    required this.from,
    required this.to,
    this.createdAt,
    this.decidedAt,
    this.entryId,
    this.copyId,
    this.projectId,
    this.projectName,
    this.projectKey,
    this.issueId,
    this.issueKey,
    this.issueTitle,
    this.date,
    this.durationMinutes = 0,
    this.startedAt,
    this.endedAt,
    this.description,
    this.billable = false,
    this.tags = const [],
  });

  final String id;
  final TimeShareStatus status;
  final TimeSharePerson from;
  final TimeSharePerson to;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  /// The sender's entry; only the sender is told.
  final String? entryId;

  /// The recipient's copy, once accepted; only the recipient is told.
  final String? copyId;

  final String? projectId;
  final String? projectName;
  final String? projectKey;
  final String? issueId;
  final String? issueKey;
  final String? issueTitle;
  final DateTime? date;
  final int durationMinutes;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? description;
  final bool billable;
  final List<String> tags;

  bool get isPending => status == TimeShareStatus.pending;

  factory TimeEntryShare.fromJson(Map<String, dynamic> json) => TimeEntryShare(
    id: json['id'] as String,
    status: TimeShareStatus.parse(json['status'] as String?),
    from: TimeSharePerson.fromJson(json['from'] as Map<String, dynamic>?),
    to: TimeSharePerson.fromJson(json['to'] as Map<String, dynamic>?),
    createdAt: parseInstant(json['createdAt']),
    decidedAt: parseInstant(json['decidedAt']),
    entryId: json['entryId'] as String?,
    copyId: json['copyId'] as String?,
    projectId: json['projectId'] as String?,
    projectName: json['projectName'] as String?,
    projectKey: json['projectKey'] as String?,
    issueId: json['issueId'] as String?,
    issueKey: json['issueKey'] as String?,
    issueTitle: json['issueTitle'] as String?,
    date: parseDate(json['date']),
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    startedAt: parseInstant(json['startedAt']),
    endedAt: parseInstant(json['endedAt']),
    description: json['description'] as String?,
    billable: json['billable'] as bool? ?? false,
    tags: [
      for (final tag in (json['tags'] as List<dynamic>?) ?? const [])
        tag as String,
    ],
  );

  @override
  List<Object?> get props => [id, status, decidedAt, copyId];
}

/// What the recipient changes before the copy is filed. Null keeps what the
/// invitation says; a different project files the copy on that project alone.
class TimeShareAcceptance {
  const TimeShareAcceptance({this.projectId, this.issueId, this.tags});

  final String? projectId;
  final String? issueId;
  final List<String>? tags;

  Map<String, dynamic> toJson() => {
    if (projectId != null) 'projectId': projectId,
    if (issueId != null) 'issueId': issueId,
    if (tags != null) 'tags': tags,
  };
}
