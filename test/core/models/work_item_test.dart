import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/issue_detail.dart';
import 'package:hinata/core/models/work_models.dart';

/// Time-Tracking 2.0 widened the wire shape additively. A server that predates
/// it — or a field the new one leaves null — must read as the same defaults the
/// server applies, never as a parse error on the issue sheet.
void main() {
  group('WorkItem.fromJson', () {
    test('reads the 2.0 fields', () {
      final item = WorkItem.fromJson(const {
        'id': 'w1',
        'issueId': 'i1',
        'projectId': 'p1',
        'userId': 'u1',
        'date': '2026-09-04',
        'durationMinutes': 90,
        'activityType': 'Testing',
        'description': 'Regression run',
        'createdAt': '2026-09-04T10:00:00Z',
        'startedAt': '2026-09-04T08:00:00Z',
        'endedAt': '2026-09-04T09:30:00Z',
        'billable': true,
        'tags': ['qa', 7, 'release'],
        'source': 'TIMER',
        'updatedAt': '2026-09-05T10:00:00Z',
        'updatedBy': 'u2',
        'sharedFromId': null,
      });
      expect(item.issueId, 'i1');
      expect(item.projectId, 'p1');
      expect(item.userId, 'u1');
      expect(item.date, DateTime(2026, 9, 4));
      expect(item.durationMinutes, 90);
      expect(item.billable, isTrue);
      // A non-string in the tag list is dropped, not a crash.
      expect(item.tags, ['qa', 'release']);
      expect(item.source, 'TIMER');
      expect(item.isLegacy, isFalse);
      expect(item.startedAt, isNotNull);
      expect(item.endedAt!.isAfter(item.startedAt!), isTrue);
      expect(item.updatedBy, 'u2');
      expect(item.sharedFromId, isNull);
    });

    test('a 1.x payload gets the server defaults', () {
      final item = WorkItem.fromJson(const {
        'id': 'w1',
        'userId': 'u1',
        'date': '2026-09-04',
        'durationMinutes': 30,
        'activityType': 'Development',
      });
      expect(item.source, WorkItem.sourceApp);
      expect(item.billable, isFalse);
      expect(item.tags, isEmpty);
      expect(item.issueId, isNull);
      expect(item.projectId, isNull);
      expect(item.startedAt, isNull);
      expect(item.updatedAt, isNull);
    });

    test('a legacy remainder belongs to nobody', () {
      final item = WorkItem.fromJson(const {
        'id': 'w1',
        'issueId': 'i1',
        'durationMinutes': 45,
        'activityType': 'Development',
        'source': 'LEGACY',
      });
      expect(item.userId, isNull);
      expect(item.isLegacy, isTrue);
    });

    test('a blank user id reads as none', () {
      final item = WorkItem.fromJson(const {
        'id': 'w1',
        'userId': '  ',
        'durationMinutes': 45,
        'activityType': 'Development',
      });
      expect(item.userId, isNull);
    });
  });

  test('TimesheetRow keeps a missing project as null', () {
    final row = TimesheetRow.fromJson(const {
      'userId': 'u1',
      'projectId': null,
      'minutesPerDay': {'2026-09-04': 60},
      'totalMinutes': 60,
    });
    expect(row.projectId, isNull);
    expect(row.minutesPerDay[DateTime(2026, 9, 4)], 60);
  });

  group('IssueDetail.workItemsTotal', () {
    Map<String, dynamic> detail({int? total, int items = 2}) => {
      'issue': const {
        'id': 'i1',
        'projectId': 'p1',
        'readableId': 'HIN-1',
        'title': 'One',
        'state': 'Open',
      },
      'workItems': [
        for (var i = 0; i < items; i++)
          {'id': 'w$i', 'durationMinutes': 10, 'activityType': 'Development'},
      ],
      'workItemsTotal': ?total,
    };

    test('is the server count when it sends one', () {
      expect(IssueDetail.fromJson(detail(total: 120)).workItemsTotal, 120);
    });

    test('falls back to the shipped list on an older server', () {
      expect(IssueDetail.fromJson(detail(items: 3)).workItemsTotal, 3);
    });
  });
}
