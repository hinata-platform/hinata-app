import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/features/moderation/case/case_detail_cubit.dart';

import '../../support/recording_fake.dart';
import 'case_fixtures.dart';

/// One case on the moderation page (HIN-174): read with the names it needs,
/// each step at the revision seen, and a 409 read again with a word on what
/// moved meanwhile.
void main() {
  late FakeModerationRepository moderation;
  late FakeUserRepository users;

  final detail = caseDetail(
    history: [
      CaseEvent(at: reportedAt, kind: CaseEventKind.claimed, actorId: 'sara'),
    ],
  );

  setUp(() {
    moderation = FakeModerationRepository()
      ..answer<CaseDetail>(#detail, detail);
    users = FakeUserRepository()
      ..answer<List<DirectoryUser>>(#usersByIds, const [
        DirectoryUser(id: 'sara', username: 'sara', displayName: 'Sara Klein'),
        DirectoryUser(id: jonas, username: jonas, displayName: 'Jonas Becker'),
      ]);
  });

  CaseDetailCubit build() => CaseDetailCubit(moderation, users, 'k1');

  blocTest<CaseDetailCubit, CaseDetailState>(
    'reads the case and the names of everyone it names, in one request',
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [
      const CaseDetailState(),
      CaseDetailState(
        load: CaseLoad.ready,
        detail: detail,
        names: const {'sara': 'Sara Klein', jonas: 'Jonas Becker'},
      ),
    ],
    verify: (_) => expect(
      users.callTo(#usersByIds).positionalArguments.single,
      unorderedEquals(['sara', jonas]),
    ),
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'a case that is not the reader\'s to see is gone',
    setUp: () =>
        moderation.fail(#detail, ApiFailure('Nicht gefunden', statusCode: 404)),
    build: build,
    act: (cubit) => cubit.load(),
    skip: 1,
    expect: () => [const CaseDetailState(load: CaseLoad.gone)],
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'taking a case sends the revision seen and reads it again',
    setUp: () => moderation.answer<CaseSummary>(#claim, caseRow()),
    build: build,
    act: (cubit) async {
      await cubit.load();
      await cubit.claim();
    },
    verify: (_) {
      expect(
        moderation.callTo(#claim),
        invoked(#claim, positional: ['k1', 3], named: {#takeOver: false}),
      );
      expect(
        moderation.calls.where((call) => call.memberName == #detail),
        hasLength(2),
      );
    },
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'somebody else decided meanwhile: read again and say so',
    setUp: () => moderation.fail(
      #claim,
      ApiFailure(
        'Der Fall hat sich geändert',
        statusCode: 409,
        details: const {'code': 'decided'},
      ),
    ),
    build: build,
    act: (cubit) async {
      await cubit.load();
      await cubit.claim();
    },
    skip: 3,
    expect: () => [
      CaseDetailState(
        load: CaseLoad.ready,
        detail: detail,
        names: const {'sara': 'Sara Klein', jonas: 'Jonas Becker'},
        noticeKey: 'moderation.case.decidedMeanwhile',
      ),
    ],
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'a refusal of a step is said in the server\'s words and the case stays',
    setUp: () => moderation.fail(
      #revealReporter,
      ApiFailure(
        'Bei Gefährdung von Kindern bleibt das verdeckt',
        statusCode: 403,
      ),
    ),
    build: build,
    act: (cubit) async {
      await cubit.load();
      await cubit.revealReporter('r1', 'Wiederholte Meldungen derselben Art');
    },
    skip: 3,
    expect: () => [
      CaseDetailState(
        load: CaseLoad.ready,
        detail: detail,
        names: const {'sara': 'Sara Klein', jonas: 'Jonas Becker'},
        errorKey: 'Bei Gefährdung von Kindern bleibt das verdeckt',
      ),
    ],
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'asking to open withheld content goes out with the reason, and the answer '
    'is read as the case now stands',
    setUp: () => moderation.answer<CaseDetail>(#revealEvidence, detail),
    build: build,
    act: (cubit) async {
      await cubit.load();
      await cubit.revealEvidence('Die Meldung nennt eine Drohung');
    },
    verify: (_) => expect(
      moderation.callTo(#revealEvidence),
      invoked(
        #revealEvidence,
        positional: ['k1', 'Die Meldung nennt eine Drohung'],
      ),
    ),
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'deciding an appeal sends the result and the reason',
    setUp: () => moderation.answer<CaseSummary>(#decideAppeal, caseRow()),
    build: build,
    act: (cubit) async {
      await cubit.load();
      await cubit.decideAppeal(
        AppealResult.reverse,
        'Der Kommentar war Ironie unter Kollegen.',
      );
    },
    verify: (cubit) {
      expect(
        moderation.callTo(#decideAppeal),
        invoked(
          #decideAppeal,
          positional: [
            'k1',
            3,
            AppealResult.reverse,
            'Der Kommentar war Ironie unter Kollegen.',
          ],
        ),
      );
      expect(cubit.state.noticeKey, 'moderation.appealReview.reversed');
    },
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'an appeal by mail is entered with the day it came',
    setUp: () => moderation.answer<CaseSummary>(#recordAppeal, caseRow()),
    build: build,
    act: (cubit) async {
      await cubit.load();
      await cubit.recordAppeal('Ich widerspreche.', DateTime.utc(2026, 10, 23));
    },
    verify: (_) => expect(
      moderation.callTo(#recordAppeal),
      invoked(
        #recordAppeal,
        positional: ['k1', 'Ich widerspreche.', DateTime.utc(2026, 10, 23)],
      ),
    ),
  );

  blocTest<CaseDetailCubit, CaseDetailState>(
    'more reports come a page at a time, after the ones shown',
    setUp: () {
      moderation
        ..answer<CaseDetail>(#detail, caseDetail(reportTotal: 2))
        ..answer<({List<CaseReport> items, int total})>(#reports, (
          items: const [CaseReport(id: 'r2', number: 2)],
          total: 2,
        ));
    },
    build: build,
    act: (cubit) async {
      await cubit.load();
      await cubit.moreReports();
      // Everything is shown: nothing more to ask for.
      await cubit.moreReports();
    },
    verify: (cubit) {
      expect(
        moderation.callTo(#reports),
        invoked(#reports, positional: ['k1', 0, 20]),
      );
      expect(
        [for (final report in cubit.state.detail!.reports) report.id],
        ['r1', 'r2'],
      );
    },
  );
}
