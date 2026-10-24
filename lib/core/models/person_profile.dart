import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// A person as any member of the organisation may see them (HIN-165), from
/// `GET /api/v1/people/{id}`.
///
/// Only what the reader would see in Hinata anyway: the teams and projects
/// they share, the absence today only where the reader may see absences, the
/// address only for an administrator ([email] is null for everybody else).
class PersonProfile extends Equatable {
  const PersonProfile({
    required this.id,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.title,
    this.pronouns,
    this.roles = const [],
    this.timezone = 'UTC',
    this.sharedTeams = const [],
    this.sharedProjects = const [],
    this.absenceToday,
    this.email,
    this.active = true,
    this.self = false,
    this.canAdmin = false,
  });

  final String id;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String? title;
  final String? pronouns;

  /// A subset of `ADMIN`, `ORG_ADMIN`, `MODERATOR`, `MEMBER`, in that order.
  final List<String> roles;

  /// The person's own IANA zone, else the instance's, else `UTC`.
  final String timezone;
  final List<SharedTeam> sharedTeams;
  final List<SharedProject> sharedProjects;
  final AbsenceToday? absenceToday;

  /// Only for an administrator; nobody else learns an address here.
  final String? email;

  /// False for a deactivated account, which only an administrator can open.
  final bool active;

  /// The reader's own profile.
  final bool self;

  /// The reader holds the platform role and gets the account's administration
  /// beside the profile.
  final bool canAdmin;

  bool get isAdmin => roles.contains('ADMIN');
  bool get isOrgAdmin => roles.contains('ORG_ADMIN');
  bool get isModerator => roles.contains('MODERATOR');

  factory PersonProfile.fromJson(Map<String, dynamic> json) => PersonProfile(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    username: json['username'] as String? ?? '',
    avatarUrl: _blankToNull(json['avatarUrl']),
    title: _blankToNull(json['title']),
    pronouns: _blankToNull(json['pronouns']),
    roles: ((json['roles'] as List<dynamic>?) ?? const []).cast<String>(),
    timezone: _blankToNull(json['timezone']) ?? 'UTC',
    sharedTeams: ((json['sharedTeams'] as List<dynamic>?) ?? const [])
        .map((e) => SharedTeam.fromJson(e as Map<String, dynamic>))
        .toList(),
    sharedProjects: ((json['sharedProjects'] as List<dynamic>?) ?? const [])
        .map((e) => SharedProject.fromJson(e as Map<String, dynamic>))
        .toList(),
    absenceToday: json['absenceToday'] is Map<String, dynamic>
        ? AbsenceToday.fromJson(json['absenceToday'] as Map<String, dynamic>)
        : null,
    email: _blankToNull(json['email']),
    active: json['active'] as bool? ?? true,
    self: json['self'] as bool? ?? false,
    canAdmin: json['canAdmin'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [
    id,
    displayName,
    username,
    avatarUrl,
    title,
    pronouns,
    roles,
    timezone,
    sharedTeams,
    sharedProjects,
    absenceToday,
    email,
    active,
    self,
    canAdmin,
  ];
}

class SharedTeam extends Equatable {
  const SharedTeam({
    required this.id,
    required this.name,
    this.key,
    this.avatarUrl,
    this.icon,
  });

  final String id;
  final String name;
  final String? key;
  final String? avatarUrl;
  final String? icon;

  factory SharedTeam.fromJson(Map<String, dynamic> json) => SharedTeam(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    key: _blankToNull(json['key']),
    avatarUrl: _blankToNull(json['avatarUrl']),
    icon: _blankToNull(json['icon']),
  );

  @override
  List<Object?> get props => [id, name, key, avatarUrl, icon];
}

class SharedProject extends Equatable {
  const SharedProject({
    required this.id,
    required this.name,
    this.key,
    this.color,
  });

  final String id;
  final String name;
  final String? key;

  /// `#RRGGBB`, or null.
  final String? color;

  factory SharedProject.fromJson(Map<String, dynamic> json) => SharedProject(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    key: _blankToNull(json['key']),
    color: _blankToNull(json['color']),
  );

  @override
  List<Object?> get props => [id, name, key, color];
}

/// Where the person is today, as far as the reader may know. `SICK` arrives
/// as `OTHER` for a reader who sees absences only in part.
class AbsenceToday extends Equatable {
  const AbsenceToday({
    required this.type,
    this.typeId,
    required this.from,
    required this.to,
    this.halfDay = false,
  });

  final String type;
  final String? typeId;
  final DateTime from;
  final DateTime to;
  final bool halfDay;

  factory AbsenceToday.fromJson(Map<String, dynamic> json) {
    final from = parseDate(json['from']) ?? dateOnly(DateTime.now());
    return AbsenceToday(
      type: json['type'] as String? ?? 'OTHER',
      typeId: _blankToNull(json['typeId']),
      from: from,
      to: parseDate(json['to']) ?? from,
      halfDay: json['halfDay'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [type, typeId, from, to, halfDay];
}

String? _blankToNull(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
