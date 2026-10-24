import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/report/report_cubit.dart';

import '../../support/recording_fake.dart';

/// Reporting from the app (HIN-173): the reason, then what moderation should
/// know, then sending it, with every refusal kept in the sheet.
void main() {
  const comment = TargetRef(ContentKind.comment, 'c1', parentId: 'i1');
  final now = DateTime.utc(2026, 10, 24, 12);
  late FakeModerationRepository moderation;

  setUp(() => moderation = FakeModerationRepository());

  ReportCubit build() => ReportCubit(moderation, comment, now: () => now);

  test('a popover tapped away while it sends takes nothing late', () async {
    final answer = Completer<void>();
    moderation.answerWith(#report, (_) => answer.future);
    final cubit = build()..choose(ReportCategory.spam);

    final sending = cubit.send('');
    await cubit.close();
    answer.complete();

    await expectLater(sending, completes);
  });

  blocTest<ReportCubit, ReportState>(
    'choosing a reason opens the details, going back remembers it',
    build: build,
    act: (cubit) => cubit
      ..choose(ReportCategory.harassment)
      ..back(),
    expect: () => const [
      ReportState(category: ReportCategory.harassment),
      ReportState(previous: ReportCategory.harassment),
    ],
  );

  blocTest<ReportCubit, ReportState>(
    'a reason that needs an explanation does not go out without one',
    build: build,
    act: (cubit) async {
      cubit.choose(ReportCategory.illegal);
      await cubit.send('  kurz ');
    },
    skip: 1,
    expect: () => const [
      ReportState(category: ReportCategory.illegal, explanationMissing: true),
    ],
    verify: (_) => expect(moderation.calls, isEmpty),
  );

  blocTest<ReportCubit, ReportState>(
    'something without a menu of its own is not sent without where it is',
    build: () => ReportCubit(moderation, TargetRef.elsewhere, now: () => now),
    act: (cubit) async {
      cubit.choose(ReportCategory.illegal);
      await cubit.send('kurz', location: '  ');
    },
    skip: 1,
    expect: () => const [
      ReportState(
        category: ReportCategory.illegal,
        locationMissing: true,
        explanationMissing: true,
      ),
    ],
    verify: (_) => expect(moderation.calls, isEmpty),
  );

  blocTest<ReportCubit, ReportState>(
    'sends where it is with something without a menu of its own',
    setUp: () => moderation.answer<void>(#report, null),
    build: () => ReportCubit(moderation, TargetRef.elsewhere, now: () => now),
    act: (cubit) async {
      cubit.choose(ReportCategory.spam);
      await cubit.send('', location: ' Board "Messe 2026" ');
    },
    verify: (_) {
      final call = moderation.only;
      expect(call.positionalArguments, [
        TargetRef.elsewhere,
        ReportCategory.spam,
      ]);
      expect(call.namedArguments[#location], 'Board "Messe 2026"');
      expect(call.namedArguments[#explanation], isNull);
    },
  );

  blocTest<ReportCubit, ReportState>(
    'sends the reason, the words and the block, and is done',
    setUp: () => moderation.answer<void>(#report, null),
    build: build,
    act: (cubit) async {
      cubit
        ..choose(ReportCategory.harassment)
        ..setAlsoBlock(true);
      await cubit.send(' Das geht seit Wochen so. ');
    },
    skip: 2,
    expect: () => const [
      ReportState(
        category: ReportCategory.harassment,
        alsoBlock: true,
        sending: true,
      ),
      ReportState(
        category: ReportCategory.harassment,
        alsoBlock: true,
        sent: true,
      ),
    ],
    verify: (_) => expect(
      moderation.only,
      invoked(
        #report,
        positional: [comment, ReportCategory.harassment],
        named: {#explanation: 'Das geht seit Wochen so.', #alsoBlock: true},
      ),
    ),
  );

  blocTest<ReportCubit, ReportState>(
    'a refusal stays in the sheet, in the server\'s words',
    setUp: () => moderation.fail(
      #report,
      ApiFailure('Dieser Inhalt wurde entfernt', statusCode: 410),
    ),
    build: build,
    act: (cubit) async {
      cubit.choose(ReportCategory.spam);
      await cubit.send('');
    },
    skip: 2,
    expect: () => const [
      ReportState(
        category: ReportCategory.spam,
        errorKey: 'Dieser Inhalt wurde entfernt',
      ),
    ],
  );

  blocTest<ReportCubit, ReportState>(
    'too many reports say by when it works again',
    setUp: () => moderation.fail(
      #report,
      ApiFailure(
        'Zu viele Meldungen',
        statusCode: 429,
        details: const {
          'code': 'error.moderation.tooManyReports',
          'retryAfter': '3600',
        },
      ),
    ),
    build: build,
    act: (cubit) async {
      cubit.choose(ReportCategory.spam);
      await cubit.send('');
    },
    skip: 2,
    expect: () => [
      ReportState(
        category: ReportCategory.spam,
        retryAt: now.add(const Duration(hours: 1)),
      ),
    ],
  );
}
