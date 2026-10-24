import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/case/case_view.dart';

import 'case_fixtures.dart';

/// What the case's ⋯ menu offers (HIN-174), case by case.
void main() {
  const action = CaseDecision(outcome: CaseOutcome.action);

  test('an open case offers the person it is about, nothing to undo', () {
    expect(caseMenuActions(caseDetail()), [CaseMenuAction.profile]);
  });

  test('a case whose content is withheld offers no profile', () {
    // Withheld: what it is, and so who wrote it, waits for a second person.
    expect(caseMenuActions(caseDetail(withheld: true)), isEmpty);
  });

  test('a removal acted on can be undone, appealed by mail and held', () {
    expect(
      caseMenuActions(
        caseDetail(
          summary: caseRow(state: CaseState.acted, removed: true),
          decision: action,
        ),
      ),
      [
        CaseMenuAction.profile,
        CaseMenuAction.restore,
        CaseMenuAction.appeal,
        CaseMenuAction.hold,
      ],
    );
  });

  test('a pending appeal leaves undoing and a second appeal to its review', () {
    expect(
      caseMenuActions(
        caseDetail(
          summary: caseRow(state: CaseState.acted, removed: true),
          decision: action,
          appeal: const CaseAppeal(state: AppealState.pending),
        ),
      ),
      [CaseMenuAction.profile, CaseMenuAction.hold],
    );
  });

  test('a running suspension can be lifted', () {
    expect(
      caseMenuActions(
        caseDetail(
          summary: caseRow(state: CaseState.acted, suspended: true),
          decision: action,
        ),
      ),
      contains(CaseMenuAction.lift),
    );
  });

  test('a case decided without action is only held', () {
    expect(
      caseMenuActions(
        caseDetail(
          summary: caseRow(state: CaseState.noAction),
          decision: const CaseDecision(outcome: CaseOutcome.noViolation),
        ),
      ),
      [CaseMenuAction.profile, CaseMenuAction.hold],
    );
  });
}
