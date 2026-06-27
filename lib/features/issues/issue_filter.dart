import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../../core/models/work_models.dart';

/// The facets the Issues overview can filter on. Mirrors the board filter but
/// swaps the board-only facets (sprint / author / label / epic) for the
/// cross-project facets that make sense on a global task list.
enum IssueFilterFacet { state, priority, assignee, project, type }

/// Swimlane-style grouping for the Issues list. [none] renders one flat list;
/// every other value buckets the (already filtered) issues under section
/// headers.
enum IssueGrouping { none, state, priority, assignee, project, type }

/// Multi-criteria filter for the Issues overview. Empty sets mean "no
/// restriction" for that facet. State / priority / type are stored as
/// UPPER-CASE backend codes; [assignees] hold user ids and [projects] hold
/// project ids. Facets combine with AND across facets and OR within a facet —
/// identical semantics to the board filter so the UX reads the same.
@immutable
class IssueFilter {
  const IssueFilter({
    this.states = const {},
    this.priorities = const {},
    this.assignees = const {},
    this.projects = const {},
    this.types = const {},
  });

  final Set<String> states;
  final Set<String> priorities;
  final Set<String> assignees;
  final Set<String> projects;
  final Set<String> types;

  /// Sentinel used in [assignees] to match issues with no assignee.
  static const noAssignee = '__none__';

  bool get isEmpty =>
      states.isEmpty &&
      priorities.isEmpty &&
      assignees.isEmpty &&
      projects.isEmpty &&
      types.isEmpty;

  int get activeCount =>
      states.length +
      priorities.length +
      assignees.length +
      projects.length +
      types.length;

  Set<String> facet(IssueFilterFacet f) => switch (f) {
    IssueFilterFacet.state => states,
    IssueFilterFacet.priority => priorities,
    IssueFilterFacet.assignee => assignees,
    IssueFilterFacet.project => projects,
    IssueFilterFacet.type => types,
  };

  /// Whether [issue] passes every active facet (AND across facets, OR within).
  bool matches(Issue issue) {
    if (states.isNotEmpty && !states.contains(issue.state.toUpperCase())) {
      return false;
    }
    if (priorities.isNotEmpty &&
        !priorities.contains(issue.priority.toUpperCase())) {
      return false;
    }
    if (assignees.isNotEmpty) {
      final id = issue.assigneeId;
      final hasId = id != null && id.isNotEmpty;
      final matchesId = hasId && assignees.contains(id);
      final matchesNone = !hasId && assignees.contains(noAssignee);
      if (!matchesId && !matchesNone) return false;
    }
    if (projects.isNotEmpty && !projects.contains(issue.projectId)) {
      return false;
    }
    if (types.isNotEmpty && !types.contains(issue.type.toUpperCase())) {
      return false;
    }
    return true;
  }

  IssueFilter copyWith({
    Set<String>? states,
    Set<String>? priorities,
    Set<String>? assignees,
    Set<String>? projects,
    Set<String>? types,
  }) => IssueFilter(
    states: states ?? this.states,
    priorities: priorities ?? this.priorities,
    assignees: assignees ?? this.assignees,
    projects: projects ?? this.projects,
    types: types ?? this.types,
  );

  /// Returns a copy with [value] toggled in [facet].
  IssueFilter toggle(IssueFilterFacet facet, String value) {
    Set<String> next(Set<String> current) {
      final updated = {...current};
      if (!updated.remove(value)) updated.add(value);
      return updated;
    }

    return switch (facet) {
      IssueFilterFacet.state => copyWith(states: next(states)),
      IssueFilterFacet.priority => copyWith(priorities: next(priorities)),
      IssueFilterFacet.assignee => copyWith(assignees: next(assignees)),
      IssueFilterFacet.project => copyWith(projects: next(projects)),
      IssueFilterFacet.type => copyWith(types: next(types)),
    };
  }

  static const empty = IssueFilter();
}

/// The distinct facet values available to filter on, derived from the issues
/// currently loaded (plus the known projects so the project facet resolves
/// names). Preserves first-seen order.
class IssueFilterOptions {
  IssueFilterOptions({
    required this.states,
    required this.priorities,
    required this.assignees,
    required this.projects,
    required this.types,
    required this.hasUnassigned,
  });

  /// UPPER-CASE workflow-state codes.
  final List<String> states;

  /// UPPER-CASE priority codes.
  final List<String> priorities;

  /// Assignee user ids (the "Unassigned" sentinel is added by the UI when
  /// [hasUnassigned] is set).
  final List<String> assignees;

  /// Project ids that own at least one loaded issue.
  final List<String> projects;

  /// UPPER-CASE issue-type codes.
  final List<String> types;

  /// Whether at least one loaded issue has no assignee.
  final bool hasUnassigned;

  bool get isEmpty =>
      states.isEmpty &&
      priorities.isEmpty &&
      assignees.isEmpty &&
      projects.isEmpty &&
      types.isEmpty;

  factory IssueFilterOptions.from(Iterable<Issue> issues) {
    final states = <String>{};
    final priorities = <String>{};
    final assignees = <String>{};
    final projects = <String>{};
    final types = <String>{};
    var hasUnassigned = false;
    for (final issue in issues) {
      if (issue.state.isNotEmpty) states.add(issue.state.toUpperCase());
      if (issue.priority.isNotEmpty) {
        priorities.add(issue.priority.toUpperCase());
      }
      final a = issue.assigneeId;
      if (a != null && a.isNotEmpty) {
        assignees.add(a);
      } else {
        hasUnassigned = true;
      }
      if (issue.projectId.isNotEmpty) projects.add(issue.projectId);
      if (issue.type.isNotEmpty) types.add(issue.type.toUpperCase());
    }
    return IssueFilterOptions(
      states: states.toList(),
      priorities: priorities.toList(),
      assignees: assignees.toList(),
      projects: projects.toList(),
      types: types.toList(),
      hasUnassigned: hasUnassigned,
    );
  }
}

// ─────────────────────────── time range ───────────────────────────────────

/// Preset windows offered by the time-range picker. [all] disables the filter;
/// [custom] defers to a user-picked [DateTimeRange]; [overdue] is special-cased
/// (past-due, still open) since it has no clean upper bound.
enum IssueTimePreset {
  all,
  overdue,
  today,
  thisWeek,
  thisMonth,
  last7,
  last30,
  next7,
  next30,
  custom,
}

/// A selected time window plus the logic that decides whether an issue falls
/// inside it.
///
/// Matching is schedule-aware so it stays intuitive: an issue with both a start
/// and a due date matches when that interval *overlaps* the window; an issue
/// with only one of the two matches when that date is inside the window; an
/// issue with neither falls back to its last-activity date ([Issue.updatedAt])
/// so freshly-touched but unscheduled work still surfaces.
@immutable
class IssueTimeRange {
  const IssueTimeRange({this.preset = IssueTimePreset.all, this.custom});

  final IssueTimePreset preset;

  /// Only set when [preset] is [IssueTimePreset.custom].
  final DateTimeRange? custom;

  bool get isActive => preset != IssueTimePreset.all;

  static const none = IssueTimeRange();

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The concrete inclusive day-bounds for a window, or null when the preset
  /// carries no fixed range ([all] / [overdue]).
  DateTimeRange? resolve(DateTime now) {
    final today = _dayOf(now);
    DateTimeRange r(DateTime from, DateTime to) =>
        DateTimeRange(start: from, end: to);
    switch (preset) {
      case IssueTimePreset.all:
      case IssueTimePreset.overdue:
        return null;
      case IssueTimePreset.today:
        return r(today, today);
      case IssueTimePreset.thisWeek:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return r(monday, monday.add(const Duration(days: 6)));
      case IssueTimePreset.thisMonth:
        final first = DateTime(today.year, today.month, 1);
        final last = DateTime(today.year, today.month + 1, 0);
        return r(first, last);
      case IssueTimePreset.last7:
        return r(today.subtract(const Duration(days: 6)), today);
      case IssueTimePreset.last30:
        return r(today.subtract(const Duration(days: 29)), today);
      case IssueTimePreset.next7:
        return r(today, today.add(const Duration(days: 6)));
      case IssueTimePreset.next30:
        return r(today, today.add(const Duration(days: 29)));
      case IssueTimePreset.custom:
        final c = custom;
        if (c == null) return null;
        return r(_dayOf(c.start), _dayOf(c.end));
    }
  }

  bool matches(Issue issue, {DateTime? clock}) {
    if (!isActive) return true;
    final now = clock ?? DateTime.now();
    if (preset == IssueTimePreset.overdue) {
      final due = issue.dueDate;
      return due != null && _dayOf(due).isBefore(_dayOf(now)) && !issue.resolved;
    }
    final range = resolve(now);
    if (range == null) return true;
    final from = range.start;
    final to = range.end;
    bool inRange(DateTime? d) {
      if (d == null) return false;
      final day = _dayOf(d);
      return !day.isBefore(from) && !day.isAfter(to);
    }

    final start = issue.startDate;
    final due = issue.dueDate;
    if (start != null && due != null) {
      // Interval overlap: starts on/before the window ends AND ends on/after it
      // begins.
      return !_dayOf(start).isAfter(to) && !_dayOf(due).isBefore(from);
    }
    if (due != null) return inRange(due);
    if (start != null) return inRange(start);
    return inRange(issue.updatedAt);
  }
}
