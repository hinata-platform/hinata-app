import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/models/moderation_models.dart';

/// The names the moderation page sends and reads (HIN-174), kept in step with
/// the server by hand: its `ModerationCaseContractTest` holds the very same
/// lists, so a value added on one side fails the other until both agree.
void main() {
  test('a case shows one of the states the server derives', () {
    expect(
      [for (final s in CaseState.values) s.wire],
      const [
        'OPEN',
        'URGENT',
        'IN_REVIEW',
        'PENDING_CONFIRMATION',
        'APPEAL',
        'ACTED',
        'NO_ACTION',
      ],
    );
    expect(
      [for (final v in CaseView.values) v.wire],
      const ['OPEN', 'APPEAL', 'DONE'],
    );
    expect(
      [for (final s in ReportSource.values) s.wire],
      const ['MEMBER', 'PUBLIC', 'AUTOMATED', 'OWN_INITIATIVE'],
    );
    expect(
      [for (final o in ContentOrigin.values) o.wire],
      const ['MEMBER', 'EMAIL', 'GIT', 'MCP'],
    );
  });

  test('a decision is made of the server\'s choices', () {
    expect(
      [for (final o in CaseOutcome.values) o.wire],
      const ['NO_VIOLATION', 'UNFOUNDED', 'ACTION', 'HANDLED'],
    );
    expect(
      [for (final g in DecisionGround.values) g.wire],
      const ['RULES', 'LAW'],
    );
    expect(
      [for (final l in SuspensionLength.values) l.wire],
      const ['DAYS_7', 'DAYS_30', 'INDEFINITE'],
    );
    expect(
      [for (final s in RemovalScope.values) s.wire],
      const [
        'WHOLE',
        'TITLE',
        'DESCRIPTION',
        'REVERT',
        'AVATAR',
        'PROFILE_TEXT',
      ],
    );
    expect(
      [for (final r in AppealResult.values) r.wire],
      const ['UPHOLD', 'REVERSE'],
    );
  });

  test('what happened to a case is worded from the server\'s names', () {
    expect(
      [for (final k in CaseEventKind.values) k.wire],
      const [
        'REPORTED',
        'CLAIMED',
        'RELEASED',
        'REPORTER_REVEALED',
        'EVIDENCE_REQUESTED',
        'EVIDENCE_REVEALED',
        'DECIDED',
        'APPEALED',
        'APPEAL_DECIDED',
        'RESTORED',
        'HELD',
        'CONFIRMATION_REQUESTED',
        'CONFIRMATION_REJECTED',
        'SUSPENDED',
        'SUSPENSION_LIFTED',
      ],
    );
    expect([for (final v in AppealVia.values) v.wire], const ['APP', 'REPLY']);
    expect(
      [for (final o in RestoreOutcome.values) o.wire],
      const ['RESTORED', 'REWRITTEN_SINCE', 'GONE'],
    );
  });

  group('a case as the server sends it', () {
    Map<String, dynamic> summary({String state = 'OPEN'}) => {
      'id': 'k1',
      'state': state,
      'kind': 'COMMENT',
      'categories': ['PRIVACY', 'HARASSMENT'],
      'sources': ['MEMBER', 'SOMETHING_NEW'],
      'reportCount': 2,
      'firstReportedAt': '2026-10-22T09:14:00Z',
      'rev': 4,
    };

    test('names its first category in the order the report sheet lists '
        'them, and is overdue after a day', () {
      final row = CaseSummary.fromJson(summary());
      expect(row.category, ReportCategory.harassment);
      expect(row.sources, {ReportSource.member});
      final reported = DateTime.utc(2026, 10, 22, 9, 14);
      expect(row.overdueAt(reported.add(const Duration(hours: 23))), isFalse);
      expect(row.overdueAt(reported.add(const Duration(hours: 24))), isTrue);
      // Decided is never overdue.
      expect(
        CaseSummary.fromJson(
          summary(state: 'ACTED'),
        ).overdueAt(reported.add(const Duration(days: 3))),
        isFalse,
      );
    });

    test('tells unchanged, changed and deleted apart while it is open', () {
      CaseDetail detail({Object? current, String state = 'OPEN'}) =>
          CaseDetail.fromJson({
            'summary': summary(state: state),
            'evidence': const {
              'ref': {'kind': 'COMMENT', 'id': 'c1', 'parentId': 'i1'},
              'contentHash': 'a',
              'excerpt': 'Du bist zu blöd.',
            },
            'current': current,
            'removalState': 'INCOMPLETE',
          });

      expect(
        detail(current: {'contentHash': 'a'}).sinceReport,
        SinceReport.unchanged,
      );
      expect(
        detail(current: {'contentHash': 'b'}).sinceReport,
        SinceReport.changed,
      );
      expect(detail().sinceReport, SinceReport.deleted);
      expect(detail(state: 'ACTED').sinceReport, isNull);
      expect(detail().removalIncomplete, isTrue);
    });
  });

  test('a decision sends only what it says, trimmed', () {
    const draft = DecisionDraft(
      rev: 3,
      outcome: CaseOutcome.action,
      removal: RemovalScope.whole,
      ground: DecisionGround.rules,
      category: ReportCategory.harassment,
      facts: '  Der Kommentar wertet eine Kollegin ab.  ',
      ruleReference: 'Hausregel 2: Kein Herabsetzen anderer',
      messageToAuthor: '   ',
      suspension: SuspensionLength.days7,
    );

    expect(draft.toJson(), {
      'rev': 3,
      'outcome': 'ACTION',
      'removal': {'scope': 'WHOLE'},
      'ground': 'RULES',
      'category': 'HARASSMENT',
      'facts': 'Der Kommentar wertet eine Kollegin ab.',
      'ruleReference': 'Hausregel 2: Kein Herabsetzen anderer',
      'deceptiveCommercial': false,
      'lawEnforcementNotified': false,
      'suspension': {'duration': 'DAYS_7'},
    });
  });
}
