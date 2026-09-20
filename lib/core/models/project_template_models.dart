import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'work_models.dart';

/// What copying a project would involve, as the server counts it.
///
/// The numbers sit under the switches in the copy sheet. They come from the
/// server rather than from the issues the app happens to have loaded, because
/// the app has loaded one page of a board and the copy takes the whole project.
class ProjectCopyScope extends Equatable {
  const ProjectCopyScope({
    this.issues = 0,
    this.subtasks = 0,
    this.attachments = 0,
    this.attachmentBytes = 0,
    this.suggestedKey = '',
    this.withinLimit = true,
  });

  final int issues;
  final int subtasks;
  final int attachments;
  final int attachmentBytes;

  /// A project key nobody is using yet, derived from the original's.
  final String suggestedKey;

  /// Whether the project is small enough to copy at all. False means the sheet
  /// says so before anybody presses the button.
  final bool withinLimit;

  factory ProjectCopyScope.fromJson(Map<String, dynamic> json) => ProjectCopyScope(
    issues: (json['issues'] as num?)?.toInt() ?? 0,
    subtasks: (json['subtasks'] as num?)?.toInt() ?? 0,
    attachments: (json['attachments'] as num?)?.toInt() ?? 0,
    attachmentBytes: (json['attachmentBytes'] as num?)?.toInt() ?? 0,
    suggestedKey: json['suggestedKey'] as String? ?? '',
    withinLimit: json['withinLimit'] as bool? ?? true,
  );

  @override
  List<Object?> get props => [
    issues,
    subtasks,
    attachments,
    attachmentBytes,
    suggestedKey,
    withinLimit,
  ];
}

/// The project a copy produced, and what came along with it.
class ProjectCopyResult extends Equatable {
  const ProjectCopyResult({
    required this.project,
    this.issuesCopied = 0,
    this.subtasksCopied = 0,
    this.attachmentsCopied = 0,
    this.deadlinesSet = 0,
  });

  final Project project;
  final int issuesCopied;
  final int subtasksCopied;
  final int attachmentsCopied;

  /// How many deadlines the copy's own event date worked out to. Zero is the
  /// ordinary answer for a copy made without a date: the rules travelled and
  /// the dates are still to come.
  final int deadlinesSet;

  factory ProjectCopyResult.fromJson(Map<String, dynamic> json) => ProjectCopyResult(
    project: Project.fromJson(json['project'] as Map<String, dynamic>),
    issuesCopied: (json['issuesCopied'] as num?)?.toInt() ?? 0,
    subtasksCopied: (json['subtasksCopied'] as num?)?.toInt() ?? 0,
    attachmentsCopied: (json['attachmentsCopied'] as num?)?.toInt() ?? 0,
    deadlinesSet: (json['deadlinesSet'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [
    project,
    issuesCopied,
    subtasksCopied,
    attachmentsCopied,
    deadlinesSet,
  ];
}

/// One deadline that would move when the event date does.
class ScheduleMove extends Equatable {
  const ScheduleMove({
    required this.issueId,
    required this.readableId,
    required this.title,
    required this.field,
    this.from,
    this.to,
  });

  final String issueId;
  final String readableId;
  final String title;

  /// `START` or `DUE` — which of the two planning dates this row is about.
  final String field;
  final DateTime? from;
  final DateTime? to;

  factory ScheduleMove.fromJson(Map<String, dynamic> json) => ScheduleMove(
    issueId: json['issueId'] as String? ?? '',
    readableId: json['readableId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    field: json['field'] as String? ?? 'DUE',
    from: parseDate(json['from']),
    to: parseDate(json['to']),
  );

  @override
  List<Object?> get props => [issueId, readableId, title, field, from, to];
}

/// What moving a project's event date would do, before anything is written.
class SchedulePreview extends Equatable {
  const SchedulePreview({
    this.eventDate,
    this.newEventDate,
    this.shiftDays,
    this.moved = 0,
    this.unchanged = 0,
    this.pending = 0,
    this.manual = 0,
    this.named = 0,
    this.moves = const [],
  });

  /// The date as it stands, and the one being proposed.
  final DateTime? eventDate;
  final DateTime? newEventDate;

  /// Days between the two, or null when one of them is absent.
  final int? shiftDays;

  /// How many issues would move.
  final int moved;

  /// How many carry a rule that works out to the day they already hold.
  final int unchanged;

  /// How many carry a rule and would still have no date, because the event date
  /// is being cleared.
  final int pending;

  /// How many deadlines somebody typed by hand. These are never touched, and
  /// the sheet says so rather than leaving the difference unexplained.
  final int manual;

  /// How many of [moved] are named in [moves]; the rest are only counted.
  final int named;
  final List<ScheduleMove> moves;

  /// Whether the sheet has anything to show. With nothing moving, the date is
  /// simply set and no sheet appears.
  bool get hasChanges => moved > 0;

  factory SchedulePreview.fromJson(Map<String, dynamic> json) => SchedulePreview(
    eventDate: parseDate(json['eventDate']),
    newEventDate: parseDate(json['newEventDate']),
    shiftDays: (json['shiftDays'] as num?)?.toInt(),
    moved: (json['moved'] as num?)?.toInt() ?? 0,
    unchanged: (json['unchanged'] as num?)?.toInt() ?? 0,
    pending: (json['pending'] as num?)?.toInt() ?? 0,
    manual: (json['manual'] as num?)?.toInt() ?? 0,
    named: (json['named'] as num?)?.toInt() ?? 0,
    moves: ((json['moves'] as List<dynamic>?) ?? const [])
        .map((m) => ScheduleMove.fromJson(m as Map<String, dynamic>))
        .toList(growable: false),
  );

  @override
  List<Object?> get props => [
    eventDate,
    newEventDate,
    shiftDays,
    moved,
    unchanged,
    pending,
    manual,
    named,
    moves,
  ];
}

/// What moving the event date actually did.
class ScheduleResult extends Equatable {
  const ScheduleResult({
    required this.project,
    this.deadlinesMoved = 0,
    this.leftAlone = 0,
  });

  final Project project;
  final int deadlinesMoved;

  /// Deadlines somebody typed by hand, which stayed where they were.
  final int leftAlone;

  factory ScheduleResult.fromJson(Map<String, dynamic> json) => ScheduleResult(
    project: Project.fromJson(json['project'] as Map<String, dynamic>),
    deadlinesMoved: (json['deadlinesMoved'] as num?)?.toInt() ?? 0,
    leftAlone: (json['leftAlone'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [project, deadlinesMoved, leftAlone];
}
