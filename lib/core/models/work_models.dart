import 'package:equatable/equatable.dart';

/// A reusable, colored issue label ("Stichwort"). [name] is the canonical key
/// issues reference via their `tags`; [id] is a stable handle used as a UI list
/// key and to detect renames server-side. [hue] is an oklch hue (see
/// `core/theme/hue_colors.dart`).
class ProjectLabel extends Equatable {
  const ProjectLabel({required this.id, required this.name, required this.hue});

  final String id;
  final String name;
  final int hue;

  factory ProjectLabel.fromAny(dynamic value, int index) {
    if (value is String) {
      return ProjectLabel(
        id: value,
        name: value,
        hue: _labelHueFallback(index),
      );
    }
    final json = value as Map<String, dynamic>;
    return ProjectLabel(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      hue: (json['hue'] as num?)?.toInt() ?? 250,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'hue': hue};

  ProjectLabel copyWith({String? name, int? hue}) =>
      ProjectLabel(id: id, name: name ?? this.name, hue: hue ?? this.hue);

  @override
  List<Object?> get props => [id, name, hue];
}

/// One ordered workflow state. [name] is the canonical key (matches
/// `Issue.state`); [id] is a stable handle for reorder/rename. [hue] is an
/// oklch hue used to tint the state everywhere it renders.
class WorkflowState extends Equatable {
  const WorkflowState({
    required this.id,
    required this.name,
    required this.hue,
  });

  final String id;
  final String name;
  final int hue;

  factory WorkflowState.fromAny(dynamic value, int index) {
    if (value is String) {
      return WorkflowState(id: value, name: value, hue: 250);
    }
    final json = value as Map<String, dynamic>;
    return WorkflowState(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      hue: (json['hue'] as num?)?.toInt() ?? 250,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'hue': hue};

  WorkflowState copyWith({String? name, int? hue}) =>
      WorkflowState(id: id, name: name ?? this.name, hue: hue ?? this.hue);

  @override
  List<Object?> get props => [id, name, hue];
}

/// Label hue cycle mirrored from the backend palette, used only as a fallback
/// when an older server returns bare label strings.
const List<int> _kFallbackLabelHues = [70, 250, 300, 200, 155, 20, 330, 45];
int _labelHueFallback(int index) =>
    _kFallbackLabelHues[index % _kFallbackLabelHues.length];

class Project extends Equatable {
  const Project({
    required this.id,
    required this.key,
    required this.name,
    this.description,
    this.leadIds = const [],
    this.memberIds = const [],
    this.workflowStates = const [],
    this.resolvedStates = const [],
    this.labels = const [],
    this.color = '#AEC6F4',
    this.archived = false,
  });

  final String id;
  final String key;
  final String name;
  final String? description;

  /// Project leads (>= 1); the first is the primary lead.
  final List<String> leadIds;
  final List<String> memberIds;
  final List<WorkflowState> workflowStates;

  /// Resolved states by *name* (subset of [workflowStates] names).
  final List<String> resolvedStates;

  /// Reusable, colored issue labels ("Stichworte") for this project.
  final List<ProjectLabel> labels;
  final String color;
  final bool archived;

  /// Primary lead (legacy single-lead accessor).
  String? get leadId => leadIds.isEmpty ? null : leadIds.first;

  /// Ordered workflow state names — what issues/boards key off of.
  List<String> get stateNames =>
      workflowStates.map((s) => s.name).toList(growable: false);

  /// Reusable label names.
  List<String> get labelNames =>
      labels.map((l) => l.name).toList(growable: false);

  /// Configured hue for a label name, or null when unknown.
  int? hueForLabel(String name) {
    for (final l in labels) {
      if (l.name == name) return l.hue;
    }
    return null;
  }

  /// Configured hue for a workflow-state name, or null when unknown.
  int? hueForState(String name) {
    for (final s in workflowStates) {
      if (s.name == name) return s.hue;
    }
    return null;
  }

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    key: json['key'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    leadIds: _leadIds(json),
    memberIds: _stringList(json['memberIds']),
    workflowStates: _indexedList(json['workflowStates'], WorkflowState.fromAny),
    resolvedStates: _stringList(json['resolvedStates']),
    labels: _indexedList(json['labels'], ProjectLabel.fromAny),
    color: json['color'] as String? ?? '#AEC6F4',
    archived: json['archived'] as bool? ?? false,
  );

  Project copyWith({
    String? key,
    String? name,
    String? description,
    List<String>? leadIds,
    List<String>? memberIds,
    List<WorkflowState>? workflowStates,
    List<String>? resolvedStates,
    List<ProjectLabel>? labels,
    String? color,
    bool? archived,
  }) => Project(
    id: id,
    key: key ?? this.key,
    name: name ?? this.name,
    description: description ?? this.description,
    leadIds: leadIds ?? this.leadIds,
    memberIds: memberIds ?? this.memberIds,
    workflowStates: workflowStates ?? this.workflowStates,
    resolvedStates: resolvedStates ?? this.resolvedStates,
    labels: labels ?? this.labels,
    color: color ?? this.color,
    archived: archived ?? this.archived,
  );

  @override
  List<Object?> get props => [
    id,
    key,
    name,
    description,
    leadIds,
    memberIds,
    workflowStates,
    resolvedStates,
    labels,
    color,
    archived,
  ];
}

/// Resolves the primary lead id from either the new [leadIds] array or the
/// legacy single `leadId` field.
List<String> _leadIds(Map<String, dynamic> json) {
  final list = _stringList(json['leadIds']);
  if (list.isNotEmpty) return list;
  final single = json['leadId'] as String?;
  return single != null && single.isNotEmpty ? [single] : const [];
}

List<T> _indexedList<T>(dynamic value, T Function(dynamic, int) build) {
  final list = (value as List<dynamic>?) ?? const [];
  return [for (var i = 0; i < list.length; i++) build(list[i], i)];
}

class Issue extends Equatable {
  const Issue({
    required this.id,
    required this.projectId,
    required this.readableId,
    required this.title,
    required this.state,
    this.description,
    this.type = 'TASK',
    this.priority = 'NORMAL',
    this.assigneeId,
    this.reporterId,
    this.tags = const [],
    this.parentId,
    this.dependsOnIds = const [],
    this.sprintId,
    this.startDate,
    this.dueDate,
    this.estimateMinutes,
    this.storyPoints,
    this.spentMinutes = 0,
    this.attachments = const [],
    this.rank = 0,
    this.resolvedAt,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String readableId;
  final String title;
  final String state;
  final String? description;
  final String type;
  final String priority;
  final String? assigneeId;
  final String? reporterId;
  final List<String> tags;
  final String? parentId;
  final List<String> dependsOnIds;
  final String? sprintId;
  final DateTime? startDate;
  final DateTime? dueDate;
  final int? estimateMinutes;

  /// Scrum effort estimate in story points (Fibonacci); null = unestimated.
  final int? storyPoints;
  final int spentMinutes;
  final List<IssueAttachment> attachments;
  final double rank;
  final DateTime? resolvedAt;
  final DateTime? updatedAt;

  bool get resolved => resolvedAt != null;

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    readableId: json['readableId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    state: json['state'] as String? ?? '',
    description: json['description'] as String?,
    type: json['type'] as String? ?? 'TASK',
    priority: json['priority'] as String? ?? 'NORMAL',
    assigneeId: json['assigneeId'] as String?,
    reporterId: json['reporterId'] as String?,
    tags: _stringList(json['tags']),
    parentId: json['parentId'] as String?,
    dependsOnIds: _stringList(json['dependsOnIds']),
    sprintId: json['sprintId'] as String?,
    startDate: _date(json['startDate']),
    dueDate: _date(json['dueDate']),
    estimateMinutes: json['estimateMinutes'] as int?,
    storyPoints: json['storyPoints'] as int?,
    spentMinutes: json['spentMinutes'] as int? ?? 0,
    attachments: ((json['attachments'] as List<dynamic>?) ?? [])
        .map((a) => IssueAttachment.fromJson(a as Map<String, dynamic>))
        .toList(),
    rank: (json['rank'] as num?)?.toDouble() ?? 0,
    resolvedAt: _instant(json['resolvedAt']),
    updatedAt: _instant(json['updatedAt']),
  );

  /// Returns a copy with the given fields replaced — used for optimistic
  /// sprint/board mutations before the server response is reconciled.
  Issue copyWith({
    String? state,
    String? assigneeId,
    Object? sprintId = _noChange,
    Object? storyPoints = _noChange,
    double? rank,
  }) => Issue(
    id: id,
    projectId: projectId,
    readableId: readableId,
    title: title,
    state: state ?? this.state,
    description: description,
    type: type,
    priority: priority,
    assigneeId: assigneeId ?? this.assigneeId,
    reporterId: reporterId,
    tags: tags,
    parentId: parentId,
    dependsOnIds: dependsOnIds,
    sprintId: sprintId == _noChange ? this.sprintId : sprintId as String?,
    startDate: startDate,
    dueDate: dueDate,
    estimateMinutes: estimateMinutes,
    storyPoints: storyPoints == _noChange
        ? this.storyPoints
        : storyPoints as int?,
    spentMinutes: spentMinutes,
    attachments: attachments,
    rank: rank ?? this.rank,
    resolvedAt: resolvedAt,
    updatedAt: updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    readableId,
    title,
    state,
    assigneeId,
    priority,
    sprintId,
    storyPoints,
    rank,
    updatedAt,
  ];
}

/// Sentinel so [Issue.copyWith] can distinguish "leave unchanged" from
/// "set to null" for nullable fields.
const Object _noChange = Object();

class IssueAttachment extends Equatable {
  const IssueAttachment({
    required this.id,
    required this.fileName,
    required this.size,
    this.contentType,
    this.uploaderId,
    this.uploadedAt,
  });

  final String id;
  final String fileName;
  final int size;
  final String? contentType;
  final String? uploaderId;
  final DateTime? uploadedAt;

  factory IssueAttachment.fromJson(Map<String, dynamic> json) =>
      IssueAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String? ?? 'file',
        size: json['size'] as int? ?? 0,
        contentType: json['contentType'] as String?,
        uploaderId: json['uploaderId'] as String?,
        uploadedAt: _instant(json['uploadedAt']),
      );

  @override
  List<Object?> get props => [id, fileName, size];
}

class IssueComment extends Equatable {
  const IssueComment({
    required this.id,
    required this.authorId,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String text;
  final DateTime? createdAt;

  factory IssueComment.fromJson(Map<String, dynamic> json) => IssueComment(
    id: json['id'] as String,
    authorId: json['authorId'] as String? ?? '',
    text: json['text'] as String? ?? '',
    createdAt: _instant(json['createdAt']),
  );

  @override
  List<Object?> get props => [id, authorId, text];
}

/// One entry in an issue's change history ("Verlauf").
class IssueActivity extends Equatable {
  const IssueActivity({
    required this.id,
    required this.field,
    this.actorId,
    this.fromValue,
    this.toValue,
    this.createdAt,
  });

  /// Backend IssueActivity.Field: CREATED, TITLE, DESCRIPTION, STATE,
  /// ASSIGNEE, PRIORITY, TYPE, SPRINT, START_DATE, DUE_DATE, ESTIMATE, TAGS.
  final String field;
  final String id;
  final String? actorId;
  final String? fromValue;
  final String? toValue;
  final DateTime? createdAt;

  factory IssueActivity.fromJson(Map<String, dynamic> json) => IssueActivity(
    id: json['id'] as String? ?? '',
    field: json['field'] as String? ?? 'CREATED',
    actorId: json['actorId'] as String?,
    fromValue: json['fromValue'] as String?,
    toValue: json['toValue'] as String?,
    createdAt: _instant(json['createdAt']),
  );

  @override
  List<Object?> get props => [id, field, fromValue, toValue, createdAt];
}

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
  });

  final String id;
  final String name;
  final BoardType type;
  final List<String> projectIds;

  /// Sprint shown by default; when set the board is a "sprint board".
  final String? activeSprintId;

  /// User id of the member who created the board; they may always manage it.
  final String? ownerId;

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
  );

  @override
  List<Object?> get props => [id, name, type, activeSprintId, ownerId];
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

class WorkItem extends Equatable {
  const WorkItem({
    required this.id,
    required this.userId,
    required this.durationMinutes,
    required this.activityType,
    this.date,
    this.description,
  });

  final String id;
  final String userId;
  final int durationMinutes;
  final String activityType;
  final DateTime? date;
  final String? description;

  factory WorkItem.fromJson(Map<String, dynamic> json) => WorkItem(
    id: json['id'] as String,
    userId: json['userId'] as String? ?? '',
    durationMinutes: json['durationMinutes'] as int? ?? 0,
    activityType: json['activityType'] as String? ?? 'Development',
    date: _date(json['date']),
    description: json['description'] as String?,
  );

  @override
  List<Object?> get props => [id, userId, durationMinutes, date];
}

class GanttTask extends Equatable {
  const GanttTask({
    required this.id,
    required this.readableId,
    required this.title,
    required this.state,
    required this.resolved,
    required this.progressPercent,
    this.type = 'TASK',
    this.startDate,
    this.dueDate,
    this.dependsOnIds = const [],
  });

  final String id;
  final String readableId;
  final String title;
  final String state;
  final String type;
  final bool resolved;
  final int progressPercent;
  final DateTime? startDate;
  final DateTime? dueDate;
  final List<String> dependsOnIds;

  factory GanttTask.fromJson(Map<String, dynamic> json) => GanttTask(
    id: json['id'] as String,
    readableId: json['readableId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    state: json['state'] as String? ?? '',
    type: json['type'] as String? ?? 'TASK',
    resolved: json['resolved'] as bool? ?? false,
    progressPercent: json['progressPercent'] as int? ?? 0,
    startDate: _date(json['startDate']),
    dueDate: _date(json['dueDate']),
    dependsOnIds: _stringList(json['dependsOnIds']),
  );

  @override
  List<Object?> get props => [id, readableId, state, progressPercent];
}

class TimesheetRow extends Equatable {
  const TimesheetRow({
    required this.userId,
    required this.projectId,
    required this.minutesPerDay,
    required this.totalMinutes,
  });

  final String userId;
  final String projectId;
  final Map<DateTime, int> minutesPerDay;
  final int totalMinutes;

  factory TimesheetRow.fromJson(Map<String, dynamic> json) => TimesheetRow(
    userId: json['userId'] as String? ?? '',
    projectId: json['projectId'] as String? ?? '',
    totalMinutes: json['totalMinutes'] as int? ?? 0,
    minutesPerDay: ((json['minutesPerDay'] as Map<String, dynamic>?) ?? {}).map(
      (k, v) => MapEntry(DateTime.parse(k), v as int),
    ),
  );

  @override
  List<Object?> get props => [userId, projectId, totalMinutes];
}

// ─────────────────────────── Sprint insights report ───────────────────────

/// Server-computed insights for one sprint (`GET /api/v1/sprints/{id}/report`).
class SprintReport extends Equatable {
  const SprintReport({
    required this.summary,
    required this.burndown,
    required this.velocity,
    required this.scope,
    required this.breakdown,
  });

  final SprintSummary summary;
  final List<BurndownPoint> burndown;
  final List<VelocityPoint> velocity;
  final List<SprintScopeChange> scope;
  final List<AssigneeLoad> breakdown;

  factory SprintReport.fromJson(Map<String, dynamic> json) => SprintReport(
    summary: SprintSummary.fromJson(
      (json['summary'] as Map<String, dynamic>?) ?? const {},
    ),
    burndown: ((json['burndown'] as List<dynamic>?) ?? const [])
        .map((e) => BurndownPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    velocity: ((json['velocity'] as List<dynamic>?) ?? const [])
        .map((e) => VelocityPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    scope: ((json['scope'] as List<dynamic>?) ?? const [])
        .map((e) => SprintScopeChange.fromJson(e as Map<String, dynamic>))
        .toList(),
    breakdown: ((json['breakdown'] as List<dynamic>?) ?? const [])
        .map((e) => AssigneeLoad.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [summary, burndown, velocity, scope, breakdown];
}

class SprintSummary extends Equatable {
  const SprintSummary({
    this.committed = 0,
    this.completed = 0,
    this.remaining = 0,
    this.issuesDone = 0,
    this.issuesTotal = 0,
    this.capacityPoints,
    this.avgVelocity = 0,
  });

  final int committed;
  final int completed;
  final int remaining;
  final int issuesDone;
  final int issuesTotal;
  final int? capacityPoints;
  final int avgVelocity;

  factory SprintSummary.fromJson(Map<String, dynamic> json) => SprintSummary(
    committed: json['committed'] as int? ?? 0,
    completed: json['completed'] as int? ?? 0,
    remaining: json['remaining'] as int? ?? 0,
    issuesDone: json['issuesDone'] as int? ?? 0,
    issuesTotal: json['issuesTotal'] as int? ?? 0,
    capacityPoints: json['capacityPoints'] as int?,
    avgVelocity: json['avgVelocity'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [
    committed,
    completed,
    remaining,
    issuesDone,
    issuesTotal,
    capacityPoints,
    avgVelocity,
  ];
}

class BurndownPoint extends Equatable {
  const BurndownPoint({
    required this.day,
    required this.ideal,
    this.date,
    this.remaining,
  });

  final int day;
  final DateTime? date;

  /// Story points still open at end of [day]; null for days not yet elapsed.
  final double? remaining;
  final double ideal;

  factory BurndownPoint.fromJson(Map<String, dynamic> json) => BurndownPoint(
    day: json['day'] as int? ?? 0,
    date: _date(json['date']),
    remaining: (json['remaining'] as num?)?.toDouble(),
    ideal: (json['ideal'] as num?)?.toDouble() ?? 0,
  );

  @override
  List<Object?> get props => [day, remaining, ideal];
}

class VelocityPoint extends Equatable {
  const VelocityPoint({
    required this.sprintId,
    required this.name,
    required this.committed,
    required this.completed,
  });

  final String sprintId;
  final String name;
  final int committed;
  final int completed;

  factory VelocityPoint.fromJson(Map<String, dynamic> json) => VelocityPoint(
    sprintId: json['sprintId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    committed: json['committed'] as int? ?? 0,
    completed: json['completed'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [sprintId, committed, completed];
}

class SprintScopeChange extends Equatable {
  const SprintScopeChange({
    required this.delta,
    required this.label,
    this.date,
  });

  final DateTime? date;
  final int delta;
  final String label;

  factory SprintScopeChange.fromJson(Map<String, dynamic> json) =>
      SprintScopeChange(
        date: _date(json['date']),
        delta: json['delta'] as int? ?? 0,
        label: json['label'] as String? ?? '',
      );

  @override
  List<Object?> get props => [date, delta, label];
}

class AssigneeLoad extends Equatable {
  const AssigneeLoad({
    required this.userId,
    required this.done,
    required this.total,
  });

  final String userId;
  final int done;
  final int total;

  factory AssigneeLoad.fromJson(Map<String, dynamic> json) => AssigneeLoad(
    userId: json['userId'] as String? ?? '',
    done: json['done'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [userId, done, total];
}

List<String> _stringList(dynamic value) =>
    ((value as List<dynamic>?) ?? const []).cast<String>();

DateTime? _date(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

DateTime? _instant(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  }
  return null;
}
