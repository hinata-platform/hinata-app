import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// How the caller stands to an issue: a member of its project, or somebody the
/// issue is shared with from outside it (HIN-136).
enum ParticipationRole { member, participant }

/// The caller's standing on one issue, from `IssueDetail.participation`. A
/// server that predates sharing sends nothing, which reads as a member who may
/// manage participants: exactly what every caller was before.
class IssueParticipation extends Equatable {
  const IssueParticipation({
    required this.role,
    required this.canManageParticipants,
  });

  static const member = IssueParticipation(
    role: ParticipationRole.member,
    canManageParticipants: true,
  );

  final ParticipationRole role;

  /// Whether the caller may share the issue and take people off it again.
  final bool canManageParticipants;

  /// Reads and comments only; sees nothing else of the project.
  bool get isParticipant => role == ParticipationRole.participant;

  factory IssueParticipation.fromJson(Map<String, dynamic>? json) {
    if (json == null) return member;
    return IssueParticipation(
      role: json['role'] == 'PARTICIPANT'
          ? ParticipationRole.participant
          : ParticipationRole.member,
      canManageParticipants: json['canManageParticipants'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [role, canManageParticipants];
}

/// Somebody outside the project an issue is shared with, as the share dialog
/// lists them.
class IssueParticipant extends Equatable {
  const IssueParticipant({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.pronouns,
    this.addedAt,
    this.addedById,
    this.addedByName,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? pronouns;
  final DateTime? addedAt;
  final String? addedById;

  /// The display name of whoever added them; null on a server that predates it.
  final String? addedByName;

  factory IssueParticipant.fromJson(Map<String, dynamic> json) =>
      IssueParticipant(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        pronouns: json['pronouns'] as String?,
        addedAt: parseInstant(json['addedAt']),
        addedById: json['addedById'] as String?,
        addedByName: json['addedByName'] as String?,
      );

  @override
  List<Object?> get props => [
    id,
    displayName,
    avatarUrl,
    pronouns,
    addedAt,
    addedById,
    addedByName,
  ];
}
