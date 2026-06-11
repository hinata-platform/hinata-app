import 'package:equatable/equatable.dart';

import 'work_models.dart';

class Article extends Equatable {
  const Article({
    required this.id,
    required this.title,
    this.content,
    this.projectId,
    this.parentId,
    this.tags = const [],
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? content;
  final String? projectId;
  final String? parentId;
  final List<String> tags;
  final DateTime? updatedAt;

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        content: json['content'] as String?,
        projectId: json['projectId'] as String?,
        parentId: json['parentId'] as String?,
        tags: ((json['tags'] as List<dynamic>?) ?? const []).cast<String>(),
        updatedAt: json['updatedAt'] is String
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  @override
  List<Object?> get props => [id, title, parentId, updatedAt];
}

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.read,
    this.body,
    this.link,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final bool read;
  final String? body;
  final String? link;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'SYSTEM',
        title: json['title'] as String? ?? '',
        read: json['read'] as bool? ?? false,
        body: json['body'] as String?,
        link: json['link'] as String?,
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );

  @override
  List<Object?> get props => [id, read, title];
}

class ProjectCompletion extends Equatable {
  const ProjectCompletion({
    required this.done,
    required this.inProgress,
    required this.backlog,
    required this.total,
  });

  final int done;
  final int inProgress;
  final int backlog;
  final int total;

  double get donePercent => total == 0 ? 0 : done / total;
  double get inProgressPercent => total == 0 ? 0 : inProgress / total;
  double get backlogPercent => total == 0 ? 0 : backlog / total;

  factory ProjectCompletion.fromJson(Map<String, dynamic> json) => ProjectCompletion(
        done: json['done'] as int? ?? 0,
        inProgress: json['inProgress'] as int? ?? 0,
        backlog: json['backlog'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [done, inProgress, backlog, total];
}

class RankEntry extends Equatable {
  const RankEntry({
    required this.userId,
    required this.displayName,
    required this.points,
    this.title,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final int points;
  final String? title;
  final String? avatarUrl;

  factory RankEntry.fromJson(Map<String, dynamic> json) => RankEntry(
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        points: json['points'] as int? ?? 0,
        title: json['title'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
      );

  @override
  List<Object?> get props => [userId, points];
}

class TrackerDay extends Equatable {
  const TrackerDay({required this.date, required this.focusMinutes});

  final DateTime date;
  final int focusMinutes;

  factory TrackerDay.fromJson(Map<String, dynamic> json) => TrackerDay(
        date: DateTime.parse(json['date'] as String),
        focusMinutes: json['focusMinutes'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [date, focusMinutes];
}

class DashboardData extends Equatable {
  const DashboardData({
    required this.todayTasks,
    required this.completion,
    required this.ranking,
    required this.tracker,
  });

  final List<Issue> todayTasks;
  final ProjectCompletion completion;
  final List<RankEntry> ranking;
  final List<TrackerDay> tracker;

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
        todayTasks: ((json['todayTasks'] as List<dynamic>?) ?? [])
            .map((i) => Issue.fromJson(i as Map<String, dynamic>))
            .toList(),
        completion: ProjectCompletion.fromJson(
            (json['completion'] as Map<String, dynamic>?) ?? const {}),
        ranking: ((json['ranking'] as List<dynamic>?) ?? [])
            .map((r) => RankEntry.fromJson(r as Map<String, dynamic>))
            .toList(),
        tracker: ((json['tracker'] as List<dynamic>?) ?? [])
            .map((t) => TrackerDay.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [todayTasks, completion, ranking, tracker];
}
