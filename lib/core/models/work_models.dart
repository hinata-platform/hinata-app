import 'package:equatable/equatable.dart';

class Project extends Equatable {
  const Project({
    required this.id,
    required this.key,
    required this.name,
    this.description,
    this.leadId,
    this.memberIds = const [],
    this.workflowStates = const [],
    this.resolvedStates = const [],
    this.color = '#AEC6F4',
    this.archived = false,
  });

  final String id;
  final String key;
  final String name;
  final String? description;
  final String? leadId;
  final List<String> memberIds;
  final List<String> workflowStates;
  final List<String> resolvedStates;
  final String color;
  final bool archived;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        key: json['key'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        leadId: json['leadId'] as String?,
        memberIds: _stringList(json['memberIds']),
        workflowStates: _stringList(json['workflowStates']),
        resolvedStates: _stringList(json['resolvedStates']),
        color: json['color'] as String? ?? '#AEC6F4',
        archived: json['archived'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [id, key, name, archived];
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
        spentMinutes: json['spentMinutes'] as int? ?? 0,
        attachments: ((json['attachments'] as List<dynamic>?) ?? [])
            .map((a) => IssueAttachment.fromJson(a as Map<String, dynamic>))
            .toList(),
        rank: (json['rank'] as num?)?.toDouble() ?? 0,
        resolvedAt: _instant(json['resolvedAt']),
        updatedAt: _instant(json['updatedAt']),
      );

  @override
  List<Object?> get props => [id, readableId, title, state, assigneeId, priority, updatedAt];
}

class IssueAttachment extends Equatable {
  const IssueAttachment({
    required this.id,
    required this.fileName,
    required this.size,
    this.contentType,
  });

  final String id;
  final String fileName;
  final int size;
  final String? contentType;

  factory IssueAttachment.fromJson(Map<String, dynamic> json) => IssueAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String? ?? 'file',
        size: json['size'] as int? ?? 0,
        contentType: json['contentType'] as String?,
      );

  @override
  List<Object?> get props => [id, fileName];
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

class Sprint extends Equatable {
  const Sprint({
    required this.id,
    required this.name,
    this.goal,
    this.startDate,
    this.endDate,
    this.archived = false,
  });

  final String id;
  final String name;
  final String? goal;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool archived;

  factory Sprint.fromJson(Map<String, dynamic> json) => Sprint(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        goal: json['goal'] as String?,
        startDate: _date(json['startDate']),
        endDate: _date(json['endDate']),
        archived: json['archived'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [id, name];
}

class AgileBoard extends Equatable {
  const AgileBoard({required this.id, required this.name, this.projectIds = const []});

  final String id;
  final String name;
  final List<String> projectIds;

  factory AgileBoard.fromJson(Map<String, dynamic> json) => AgileBoard(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        projectIds: _stringList(json['projectIds']),
      );

  @override
  List<Object?> get props => [id, name];
}

class BoardColumnView extends Equatable {
  const BoardColumnView({
    required this.name,
    required this.states,
    required this.issues,
    this.wipLimit,
  });

  final String name;
  final List<String> states;
  final List<Issue> issues;
  final int? wipLimit;

  factory BoardColumnView.fromJson(Map<String, dynamic> json) => BoardColumnView(
        name: json['name'] as String? ?? '',
        states: _stringList(json['states']),
        wipLimit: json['wipLimit'] as int?,
        issues: ((json['issues'] as List<dynamic>?) ?? [])
            .map((i) => Issue.fromJson(i as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [name, states, issues];
}

class BoardView extends Equatable {
  const BoardView({required this.board, required this.sprints, required this.columns});

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
    this.startDate,
    this.dueDate,
    this.dependsOnIds = const [],
  });

  final String id;
  final String readableId;
  final String title;
  final String state;
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
        minutesPerDay: ((json['minutesPerDay'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(DateTime.parse(k), v as int)),
      );

  @override
  List<Object?> get props => [userId, projectId, totalMinutes];
}

List<String> _stringList(dynamic value) =>
    ((value as List<dynamic>?) ?? const []).cast<String>();

DateTime? _date(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

DateTime? _instant(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).round(), isUtc: true);
  }
  return null;
}
