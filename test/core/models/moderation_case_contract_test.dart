import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/case/case_detail_cubit.dart'
    show CaseNotice, movedMeanwhile;

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
        'them, and is overdue when the server says so', () {
      final row = CaseSummary.fromJson(summary());
      expect(row.category, ReportCategory.harassment);
      expect(row.sources, {ReportSource.member});
      expect(row.overdue, isFalse);
      expect(
        CaseSummary.fromJson({...summary(), 'overdue': true}).overdue,
        isTrue,
      );
    });

    test('tells unchanged, changed and deleted apart while it is open', () {
      CaseDetail detail({String? current, String state = 'OPEN'}) =>
          CaseDetail.fromJson({
            'summary': summary(state: state),
            'evidence': const {
              'ref': {'kind': 'COMMENT', 'id': 'c1', 'parentId': 'i1'},
              'contentHash': 'a',
              'excerpt': 'Du bist zu blöd.',
            },
            'currentHash': current,
            'removalState': 'INCOMPLETE',
            'takeOverAllowed': true,
          });

      expect(detail(current: 'a').sinceReport, SinceReport.unchanged);
      expect(detail(current: 'b').sinceReport, SinceReport.changed);
      expect(detail().takeOverAllowed, isTrue);
      expect(detail().sinceReport, SinceReport.deleted);
      expect(detail(state: 'ACTED').sinceReport, isNull);
      expect(detail().removalIncomplete, isTrue);
    });
  });

  /// The server's `ModerationCaseContractTest` holds the very same list.
  test('the refusals the app acts on are named by their keys', () {
    const codes = [
      'error.moderation.refused',
      'error.moderation.tooManyReports',
      'error.moderation.tooManyReveals',
      'error.moderation.openAccessUnconfirmed',
      'error.moderation.flagUnconfirmed',
      'error.moderation.caseDecided',
      'error.moderation.caseChanged',
    ];
    ApiFailure refusal(String code, [Map<String, String> more = const {}]) =>
        ApiFailure('x', statusCode: 409, details: {'code': code, ...more});

    expect(
      ContentRefusal.of(refusal(codes[0], {'terms': 'Spoiler, Leak'})),
      const ContentRefusal(['Spoiler', 'Leak']),
    );
    expect(
      OpenAccessRefusal.of(refusal(codes[3], {'ways': 'registration,oidc'})),
      const OpenAccessRefusal(['registration', 'oidc']),
    );
    expect(flagConfirmRequired(refusal(codes[4])), isTrue);
    expect(
      movedMeanwhile(refusal(codes[5])),
      const CaseNotice('moderation.case.decidedMeanwhile', moved: true),
    );
    expect(
      movedMeanwhile(refusal(codes[6])),
      const CaseNotice('moderation.case.changedMeanwhile', moved: true),
    );
    // The codes before they were the keys are nothing any more.
    expect(flagConfirmRequired(refusal('moderation.flagConfirm')), isFalse);
    expect(movedMeanwhile(refusal('decided')), isNull);
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
