import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/person/person_moderation_cubit.dart';

import '../../support/recording_fake.dart';
import 'case_fixtures.dart';

/// Moderation from a person's profile (HIN-174): a case of moderation's own,
/// read for its decision, and lifting a suspension at the revision it stands
/// at now. A refusal is said in the server's words.
void main() {
  late FakeModerationRepository moderation;
  late PersonModerationCubit cubit;

  setUp(() {
    moderation = FakeModerationRepository();
    cubit = PersonModerationCubit(moderation);
  });
  tearDown(() => cubit.close());

  test('opens a case on the person and reads it for its decision', () async {
    moderation
      ..answer<String>(#openOwn, 'k9')
      ..answer<CaseDetail>(#detail, caseDetail());

    final detail = await cubit.openCase(
      'jonas',
      ReportCategory.spam,
      'Schickt seit Tagen dieselbe Werbung.',
    );

    expect(detail, isNotNull);
    expect(moderation.callTo(#openOwn).positionalArguments, [
      const TargetRef(ContentKind.person, 'jonas'),
      ReportCategory.spam,
      'Schickt seit Tagen dieselbe Werbung.',
    ]);
    expect(moderation.callTo(#detail).positionalArguments, ['k9']);
    expect(cubit.state, isNull);
  });

  test('a case the server will not open says why', () async {
    moderation.fail(#openOwn, ApiFailure('error.moderation.ownCase'));

    expect(
      await cubit.openCase('jonas', ReportCategory.spam, 'x' * 20),
      isNull,
    );
    expect(cubit.state, 'error.moderation.ownCase');

    cubit.seen();
    expect(cubit.state, isNull);
  });

  test('lifts at the revision the case stands at now', () async {
    moderation
      ..answer<CaseDetail>(#detail, caseDetail(summary: caseRow(rev: 7)))
      ..answer<CaseSummary>(#liftSuspension, caseRow());

    expect(await cubit.lift('k1', 'Hat sich gemeldet.'), isTrue);
    expect(moderation.callTo(#liftSuspension).positionalArguments, [
      'k1',
      7,
      'Hat sich gemeldet.',
    ]);
  });

  test('a lift the server refuses says why', () async {
    moderation
      ..answer<CaseDetail>(#detail, caseDetail())
      ..fail(#liftSuspension, ApiFailure('error.moderation.caseChanged'));

    expect(await cubit.lift('k1', 'Hat sich gemeldet.'), isFalse);
    expect(cubit.state, 'error.moderation.caseChanged');
  });
}
