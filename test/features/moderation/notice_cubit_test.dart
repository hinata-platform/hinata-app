import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/notice/notice_cubit.dart';

import '../../support/recording_fake.dart';

/// The notice to the person concerned (HIN-173): read, appealed, and gone
/// once its time ran out.
void main() {
  const open = Statement(
    caseId: 'k1',
    headline: 'Eine Entscheidung der Moderation zu deinem Inhalt',
    measure: 'Dein Kommentar wurde entfernt.',
    scope: StatementScope.whole,
    appealable: true,
  );
  const appealed = Statement(
    caseId: 'k1',
    headline: 'Eine Entscheidung der Moderation zu deinem Inhalt',
    measure: 'Dein Kommentar wurde entfernt.',
    scope: StatementScope.whole,
    appealState: AppealState.pending,
  );
  late FakeModerationRepository moderation;

  setUp(() => moderation = FakeModerationRepository());

  NoticeCubit cubit() {
    final notice = NoticeCubit(moderation, 'k1');
    addTearDown(notice.close);
    return notice;
  }

  test('reads the notice of the case', () async {
    moderation.answer<Statement>(#notice, open);
    final notice = cubit();
    await notice.load();
    expect(notice.state.status, NoticeStatus.ready);
    expect(notice.state.statement, open);
    expect(moderation.only, invoked(#notice, positional: ['k1']));
  });

  test('a notice whose time ran out is gone, not broken', () async {
    moderation.fail(
      #notice,
      ApiFailure('Hinweis nicht gefunden', statusCode: 404),
    );
    final notice = cubit();
    await notice.load();
    expect(notice.state.status, NoticeStatus.gone);
  });

  test('another failure offers to try again', () async {
    moderation.fail(#notice, failure);
    final notice = cubit();
    await notice.load();
    expect(notice.state.status, NoticeStatus.failure);
    expect(notice.state.errorKey, 'errors.test');
  });

  test('an appeal goes in and the page shows it', () async {
    moderation
      ..answer<Statement>(#notice, open)
      ..answer<Statement>(#appeal, appealed);
    final notice = cubit();
    await notice.load();

    expect(await notice.appeal('  Das war ironisch gemeint. '), isTrue);

    expect(notice.state.statement, appealed);
    expect(
      moderation.callTo(#appeal),
      invoked(#appeal, positional: ['k1', 'Das war ironisch gemeint.']),
    );
  });

  test('an appeal too late says so and reads the notice again', () async {
    moderation
      ..answer<Statement>(#notice, open)
      ..fail(#appeal, ApiFailure('Die Frist ist abgelaufen', statusCode: 409));
    final notice = cubit();
    await notice.load();
    moderation.answer<Statement>(#notice, appealed);

    expect(await notice.appeal('Bitte noch einmal ansehen.'), isFalse);

    expect(notice.state.appealErrorKey, 'Die Frist ist abgelaufen');
    expect(notice.state.statement, appealed);
  });

  test('an empty appeal sends nothing', () async {
    moderation.answer<Statement>(#notice, open);
    final notice = cubit();
    await notice.load();
    expect(await notice.appeal('   '), isFalse);
    expect(moderation.calls, hasLength(1));
  });
}
