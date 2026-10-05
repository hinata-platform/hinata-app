import 'package:hinata/core/models/work_models.dart';

/// A minimal issue, for answers that need one.
Issue testIssue([String id = 'i1']) => Issue.fromJson({
  'id': id,
  'projectId': 'p1',
  'readableId': 'HIN-1',
  'title': 'Title',
  'state': 'OPEN',
});

/// A minimal work entry, for answers that need one.
const WorkItem testWorkItem = WorkItem(
  id: 'w1',
  durationMinutes: 30,
  activityType: 'Development',
);
