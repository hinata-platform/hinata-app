part of 'work_models.dart';

class Sprint extends Equatable {
  const Sprint({
    required this.id,
    required this.name,
    this.boardId,
    this.goal,
    this.startDate,
    this.endDate,
    this.capacityPoints,
    this.archived = false,
  });

  final String id;
  final String name;
  final String? boardId;
  final String? goal;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Story-point capacity the team commits to for this sprint.
  final int? capacityPoints;
  final bool archived;

  factory Sprint.fromJson(Map<String, dynamic> json) => Sprint(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    boardId: json['boardId'] as String?,
    goal: json['goal'] as String?,
    startDate: _date(json['startDate']),
    endDate: _date(json['endDate']),
    capacityPoints: json['capacityPoints'] as int?,
    archived: json['archived'] as bool? ?? false,
  );

  /// Lifecycle state derived from the board's active sprint (never stored, so
  /// it can't drift). Mirrors the backend SprintState reasoning.
  SprintLifecycle lifecycle(String? activeSprintId) {
    if (archived) return SprintLifecycle.completed;
    if (id == activeSprintId) return SprintLifecycle.active;
    return SprintLifecycle.planned;
  }

  @override
  List<Object?> get props => [id, name, archived, capacityPoints, endDate];
}

enum SprintLifecycle { planned, active, completed }

/// Working mode of a board — mirrors backend AgileBoard.Type.
enum BoardType { kanban, scrum }

class AgileBoard extends Equatable {
  const AgileBoard({
    required this.id,
    required this.name,
    this.type = BoardType.kanban,
    this.projectIds = const [],
    this.activeSprintId,
    this.ownerId,
    this.columnsCustomized = false,
  });

  final String id;
  final String name;
  final BoardType type;
  final List<String> projectIds;

  /// Sprint shown by default; when set the board is a "sprint board".
  final String? activeSprintId;

  /// User id of the member who created the board; they may always manage it.
  final String? ownerId;

  /// Whether the columns were arranged by hand. While false the board derives
  /// them from the spanned workflows, so a rename in project settings shows up
  /// by itself — which is why the editor offers a way back to automatic.
  final bool columnsCustomized;

  bool get isScrum => type == BoardType.scrum;

  factory AgileBoard.fromJson(Map<String, dynamic> json) => AgileBoard(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    type: (json['type'] as String?)?.toUpperCase() == 'SCRUM'
        ? BoardType.scrum
        : BoardType.kanban,
    projectIds: _stringList(json['projectIds']),
    activeSprintId: json['activeSprintId'] as String?,
    ownerId: json['ownerId'] as String?,
    columnsCustomized: json['columnsCustomized'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    activeSprintId,
    ownerId,
    columnsCustomized,
  ];
}

/// One column of a hand-made board layout — what the column editor sends back.
/// Unlike [BoardColumnView] it carries no issues: it is the arrangement, not
/// the wall.
class BoardColumnLayout extends Equatable {
  const BoardColumnLayout({
    required this.name,
    required this.states,
    this.wipLimit,
  });

  final String name;

  /// Workflow state names this column collects, at most one per project.
  final List<String> states;
  final int? wipLimit;

  BoardColumnLayout copyWith({
    String? name,
    List<String>? states,
    int? wipLimit,
    bool clearWipLimit = false,
  }) => BoardColumnLayout(
    name: name ?? this.name,
    states: states ?? this.states,
    wipLimit: clearWipLimit ? null : (wipLimit ?? this.wipLimit),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'states': states,
    'wipLimit': ?wipLimit,
  };

  @override
  List<Object?> get props => [name, states, wipLimit];
}

class BoardColumnView extends Equatable {
  const BoardColumnView({
    required this.name,
    required this.states,
    required this.issues,
    this.wipLimit,
    this.hue,
  });

  final String name;
  final List<String> states;
  final List<Issue> issues;
  final int? wipLimit;

  /// Configured oklch hue of this column's workflow state (server-derived).
  final int? hue;

  factory BoardColumnView.fromJson(Map<String, dynamic> json) =>
      BoardColumnView(
        name: json['name'] as String? ?? '',
        states: _stringList(json['states']),
        wipLimit: json['wipLimit'] as int?,
        hue: (json['hue'] as num?)?.toInt(),
        issues: ((json['issues'] as List<dynamic>?) ?? [])
            .map((i) => Issue.fromJson(i as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [name, states, issues, hue];
}

class BoardView extends Equatable {
  const BoardView({
    required this.board,
    required this.sprints,
    required this.columns,
  });

  final AgileBoard board;
  final List<Sprint> sprints;
  final List<BoardColumnView> columns;

  factory BoardView.fromJson(Map<String, dynamic> json) => BoardView(
    board: AgileBoard.fromJson(json['board'] as Map<String, dynamic>),
    sprints: ((json['sprints'] as List<dynamic>?) ?? [])
        .map((s) => Sprint.fromJson(s as Map<String, dynamic>))
        .toList(),
    columns: ((json['columns'] as List<dynamic>?) ?? [])
        .map((c) => BoardColumnView.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [board, sprints, columns];
}

/// One logged unit of work (`work_items`).
///
/// Only the 1.x fields are guaranteed on the wire; everything Time-Tracking 2.0
/// added is optional and parsed leniently, so an older server's answer still
/// reads with the same defaults the server itself applies ([source] `APP`,
/// [billable] false, no tags). [userId] is null for entries credited to nobody
/// — see [isLegacy].
class WorkItem extends Equatable {
  const WorkItem({
    required this.id,
    required this.durationMinutes,
    required this.activityType,
    this.userId,
    this.issueId,
    this.projectId,
    this.date,
    this.description,
    this.createdAt,
    this.startedAt,
    this.endedAt,
    this.billable = false,
    this.tags = const [],
    this.source = sourceApp,
    this.updatedAt,
    this.updatedBy,
    this.sharedFromId,
  });

  /// Logged by hand in the app — the default when a server sends no source.
  static const sourceApp = 'APP';

  /// Minutes that smart commits booked straight onto the issue before 2.0.
  /// The migration parks them in one entry per issue that belongs to nobody.
  static const sourceLegacy = 'LEGACY';

  final String id;
  final String? userId;
  final String? issueId;
  final String? projectId;
  final int durationMinutes;
  final String activityType;

  /// The calendar day the work is booked on — a pure date, never shifted
  /// across zones (only [startedAt]/[endedAt] are instants).
  final DateTime? date;
  final String? description;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final bool billable;
  final List<String> tags;

  /// Where the entry came from: `APP`, `TIMER`, `MCP`, `SMART_COMMIT`,
  /// `LEGACY`, `CALENDAR`, `CSV` or `SHARED`.
  final String source;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? sharedFromId;

  /// Whether this is the pre-2.0 remainder the migration credited to nobody.
  /// Rendered under its own label rather than a person, and never editable.
  bool get isLegacy => source == sourceLegacy;

  factory WorkItem.fromJson(Map<String, dynamic> json) => WorkItem(
    id: json['id'] as String,
    userId: _optionalId(json['userId']),
    issueId: _optionalId(json['issueId']),
    projectId: _optionalId(json['projectId']),
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    activityType: json['activityType'] as String? ?? 'Development',
    date: _date(json['date']),
    description: json['description'] as String?,
    createdAt: _instant(json['createdAt']),
    startedAt: _instant(json['startedAt']),
    endedAt: _instant(json['endedAt']),
    billable: json['billable'] as bool? ?? false,
    tags: ((json['tags'] as List<dynamic>?) ?? const [])
        .whereType<String>()
        .toList(),
    source: _optionalId(json['source']) ?? sourceApp,
    updatedAt: _instant(json['updatedAt']),
    updatedBy: _optionalId(json['updatedBy']),
    sharedFromId: _optionalId(json['sharedFromId']),
  );

  @override
  List<Object?> get props => [
    id,
    userId,
    issueId,
    projectId,
    durationMinutes,
    activityType,
    date,
    description,
    startedAt,
    endedAt,
    billable,
    tags,
    source,
    updatedAt,
  ];
}

/// A string field that may arrive as null *or* blank — both mean "none".
String? _optionalId(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
