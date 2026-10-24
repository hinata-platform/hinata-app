import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/models/person_profile.dart';
import 'package:hinata/features/moderation/case/case_detail_cubit.dart'
    show CaseNotice;
import 'package:hinata/features/moderation/decision/decision_cubit.dart';

import '../../support/recording_fake.dart';
import 'case_fixtures.dart';

/// Deciding a case (HIN-174): the server words the preview only when
/// something structured changes and only its newest answer counts; what is
/// typed goes in here; two moderators deciding at once are told who won.
void main() {
  const rules = ModerationRules(
    version: 2,
    rules: [
      HouseRule(1, 'Respekt'),
      HouseRule(2, 'Kein Herabsetzen anderer'),
      HouseRule(6, 'Kein Spam'),
    ],
    categoryRules: {
      ReportCategory.harassment: 2,
      ReportCategory.spam: 6,
      ReportCategory.other: 1,
    },
  );
  const preview = Statement(
    caseId: 'k1',
    measure: 'Dein Kommentar wurde entfernt.',
    facts: DecisionCubit.factsMark,
    groundText: 'Verstoß gegen die Hausregeln: 2. Kein Herabsetzen anderer',
  );

  late FakeModerationRepository moderation;
  late FakeUserRepository users;

  setUp(() {
    moderation = FakeModerationRepository()
      ..answer<ModerationRules>(#rules, rules)
      ..answer<Statement>(#statementPreview, preview);
    users = FakeUserRepository()
      ..answer<PersonProfile>(
        #profile,
        const PersonProfile(id: jonas, displayName: 'Jonas', username: jonas),
      );
  });

  Future<DecisionCubit> started({CaseDetail? detail}) async {
    final cubit = DecisionCubit(
      moderation,
      users,
      detail: detail ?? caseDetail(),
    );
    addTearDown(cubit.close);
    await cubit.start();
    return cubit;
  }

  Iterable<Invocation> previews() =>
      moderation.calls.where((call) => call.memberName == #statementPreview);

  test('the rule of the reported category is picked to begin with', () async {
    final cubit = await started();
    expect(cubit.state.rule, const HouseRule(2, 'Kein Herabsetzen anderer'));
    // No outcome yet: nothing to word.
    expect(previews(), isEmpty);
  });

  test('only structured changes ask the server; what is typed goes into the '
      'last answer', () async {
    final cubit = await started();
    cubit.choose(CaseOutcome.action);
    await pumpEventQueue();
    expect(previews(), hasLength(1));
    final draft = previews().single.positionalArguments[1] as DecisionDraft;
    expect(draft.removal, RemovalScope.whole);
    expect(draft.ruleReference, '2. Kein Herabsetzen anderer');
    expect(draft.facts, DecisionCubit.factsMark);

    cubit
      ..setFacts('Der Kommentar wertet eine Kollegin ab, statt die Sache.')
      ..setMessage('Bitte bleib sachlich.')
      ..setInternalNote('Zweiter Vorfall');
    await pumpEventQueue();
    expect(previews(), hasLength(1));
    expect(
      cubit.state.preview?.facts,
      'Der Kommentar wertet eine Kollegin ab, statt die Sache.',
    );
    expect(cubit.state.preview?.messageToAuthor, 'Bitte bleib sachlich.');

    cubit.chooseRule(const HouseRule(1, 'Respekt'));
    await pumpEventQueue();
    expect(previews(), hasLength(2));
    // The same choice again changes nothing.
    cubit.chooseRule(const HouseRule(1, 'Respekt'));
    await pumpEventQueue();
    expect(previews(), hasLength(2));
  });

  test(
    'the law is typed, and goes into the ground the server worded',
    () async {
      moderation.answer<Statement>(
        #statementPreview,
        const Statement(
          caseId: 'k1',
          groundText: 'Rechtswidrig nach ${DecisionCubit.lawMark}',
        ),
      );
      final cubit = await started();
      cubit
        ..choose(CaseOutcome.action)
        ..setGround(DecisionGround.law)
        ..setLawReference('§ 185 StGB');
      await pumpEventQueue();
      expect(cubit.state.preview?.groundText, 'Rechtswidrig nach § 185 StGB');
      final draft = previews().last.positionalArguments[1] as DecisionDraft;
      expect(draft.lawReference, DecisionCubit.lawMark);
      expect(draft.ruleReference, isNull);
    },
  );

  test('only the newest answer counts', () async {
    final answers = <Completer<Statement>>[];
    moderation.answerWith(#statementPreview, (_) {
      final answer = Completer<Statement>();
      answers.add(answer);
      return answer.future;
    });
    final cubit = await started();
    cubit.choose(CaseOutcome.action);
    cubit.chooseRule(const HouseRule(1, 'Respekt'));
    expect(answers, hasLength(2));

    answers[1].complete(
      const Statement(caseId: 'k1', measure: 'Neuer Wortlaut'),
    );
    await pumpEventQueue();
    answers[0].complete(
      const Statement(caseId: 'k1', measure: 'Alter Wortlaut'),
    );
    await pumpEventQueue();
    expect(cubit.state.preview?.measure, 'Neuer Wortlaut');
  });

  test('what is still missing is said once sending was tried', () async {
    final cubit = await started();
    await cubit.submit();
    expect(cubit.problems, {DecisionProblem.outcome});
    expect(cubit.state.showProblems, isTrue);

    cubit
      ..choose(CaseOutcome.action)
      ..setRemove(false);
    expect(cubit.problems, {DecisionProblem.measure, DecisionProblem.facts});
    expect(moderation.calls.where((c) => c.memberName == #decide), isEmpty);
  });

  test(
    'a decision goes out with the revision seen and closes the dialog',
    () async {
      moderation.answer<CaseSummary>(#decide, caseRow(state: CaseState.acted));
      final cubit = await started();
      cubit
        ..choose(CaseOutcome.action)
        ..setFacts('Der Kommentar wertet eine Kollegin ab, statt die Sache.')
        ..setMessage('Bitte bleib sachlich.');
      await cubit.submit();

      final draft =
          moderation.callTo(#decide).positionalArguments[1] as DecisionDraft;
      expect(draft.rev, 3);
      expect(draft.outcome, CaseOutcome.action);
      expect(draft.category, ReportCategory.harassment);
      expect(draft.messageToAuthor, 'Bitte bleib sachlich.');
      expect(draft.responsibleId, jonas);
      expect(
        cubit.state.closedWith,
        const CaseNotice('moderation.decision.sent'),
      );
    },
  );

  for (final (code, key) in const [
    ('error.moderation.caseDecided', 'moderation.case.decidedMeanwhile'),
    ('error.moderation.caseChanged', 'moderation.case.changedMeanwhile'),
  ]) {
    test('a 409 with "$code" closes the dialog and says so', () async {
      moderation.fail(
        #decide,
        ApiFailure(
          'Der Fall hat sich geändert',
          statusCode: 409,
          details: {'code': code},
        ),
      );
      final cubit = await started();
      cubit
        ..choose(CaseOutcome.unfounded)
        ..setFacts('Die Meldung nennt den falschen Kommentar.');
      await cubit.submit();
      expect(cubit.state.closedWith, CaseNotice(key, moved: true));
    });
  }

  test('an administrator is never suspended; a moderator needs a second '
      'person', () async {
    users.answer<PersonProfile>(
      #profile,
      const PersonProfile(
        id: jonas,
        displayName: 'Jonas',
        username: jonas,
        roles: ['ADMIN', 'MEMBER'],
      ),
    );
    final admin = await started();
    admin
      ..choose(CaseOutcome.action)
      ..setSuspend(true);
    expect(admin.canSuspend, isFalse);
    expect(admin.state.suspend, isFalse);

    users.answer<PersonProfile>(
      #profile,
      const PersonProfile(
        id: jonas,
        displayName: 'Jonas',
        username: jonas,
        roles: ['MODERATOR', 'MEMBER'],
      ),
    );
    final moderator = await started();
    moderator
      ..choose(CaseOutcome.action)
      ..setSuspend(true)
      ..setDuration(SuspensionLength.days30);
    expect(moderator.state.suspend, isTrue);
    expect(moderator.state.needsSecondPerson, isTrue);
    await pumpEventQueue();
    final draft = previews().last.positionalArguments[1] as DecisionDraft;
    expect(draft.suspension, SuspensionLength.days30);
  });

  test(
    'spam that misleads is offered only for spam, and sent only there',
    () async {
      moderation.answer<CaseSummary>(#decide, caseRow(state: CaseState.acted));
      final cubit = await started(
        detail: caseDetail(
          summary: caseRow(categories: const [ReportCategory.spam]),
        ),
      );
      expect(cubit.state.rule, const HouseRule(6, 'Kein Spam'));
      cubit
        ..choose(CaseOutcome.action)
        ..setDeceptiveCommercial(true)
        ..setFacts('Massenwerbung für ein Gewinnspiel ohne Bezug zum Projekt.');
      await cubit.submit();
      final draft =
          moderation.callTo(#decide).positionalArguments[1] as DecisionDraft;
      expect(draft.category, ReportCategory.spam);
      expect(draft.deceptiveCommercial, isTrue);
    },
  );

  test('something else is dealt with, never acted on', () {
    expect(outcomesOf(ContentKind.other), [
      CaseOutcome.noViolation,
      CaseOutcome.handled,
    ]);
    expect(scopesOf(ContentKind.issue), [
      RemovalScope.title,
      RemovalScope.description,
      RemovalScope.whole,
    ]);
  });
}
