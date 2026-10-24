import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/features/moderation/report/report_sheet.dart';

import '../../support/recording_fake.dart';
import 'moderation_test_support.dart';

/// Who may report what (HIN-173), asked the same way on every surface: on a
/// server that knows reporting, somebody else's, still there.
void main() {
  const me = AuthUser(
    id: 'u1',
    email: 'lena@werkhaus.example',
    username: 'lena',
    displayName: 'Lena Vogt',
    roles: {'MEMBER'},
  );

  Future<BuildContext> contextOn(
    WidgetTester tester, {
    AuthUser? user = me,
    ModerationMeta moderation = const ModerationMeta(version: 1),
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      moderationApp(
        account: FakeAccountRepository(),
        auth: RecordingAuth(user: user),
        moderation: moderation,
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('somebody else\'s, still there, may be reported', (tester) async {
    final context = await contextOn(tester);

    expect(canReport(context, authorId: 'jonas'), isTrue);
    expect(canReport(context, authorId: null), isTrue);
    expect(canReport(context, authorId: 'u1'), isFalse);
    expect(canReport(context, authorId: 'jonas', removed: true), isFalse);
  });

  testWidgets('nothing is reported on a server without moderation, or by '
      'nobody', (tester) async {
    expect(
      canReport(
        await contextOn(tester, moderation: const ModerationMeta()),
        authorId: 'jonas',
      ),
      isFalse,
    );
    expect(
      canReport(await contextOn(tester, user: null), authorId: 'jonas'),
      isFalse,
    );
  });
}
