import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/features/moderation/queue/moderation_cases_cubit.dart';
import 'package:hinata/features/moderation/queue/moderation_summary_cubit.dart';

import '../../support/recording_fake.dart';
import 'case_fixtures.dart';

/// The moderation page's lists and numbers (HIN-174).
void main() {
  late FakeModerationRepository moderation;

  setUp(() => moderation = FakeModerationRepository());

  test('each view reads its own list, fifty cases a page', () async {
    moderation.answer<({List<CaseSummary> items, int total})>(#cases, (
      items: [caseRow()],
      total: 1,
    ));
    final appeals = ModerationCasesCubit(moderation, CaseView.appeal);
    addTearDown(appeals.close);
    await appeals.load();

    expect(
      moderation.callTo(#cases),
      invoked(#cases, positional: [CaseView.appeal, 0, 50]),
    );
    expect(appeals.state.items.single.id, 'k1');
  });

  // A widget test only for its clock: the minute passes without waiting.
  testWidgets('the numbers are read once a minute while running, and never '
      'while paused', (tester) async {
    moderation.answer<ModerationSummary>(
      #summary,
      const ModerationSummary(open: 5, overdue: 1, appeals: 1),
    );
    final summary = ModerationSummaryCubit(moderation);
    addTearDown(summary.close);
    int reads() =>
        moderation.calls.where((c) => c.memberName == #summary).length;

    summary.start();
    await tester.pump();
    expect(reads(), 1);
    expect(summary.state?.open, 5);

    await tester.pump(const Duration(seconds: 60));
    expect(reads(), 2);

    summary.pause();
    await tester.pump(const Duration(minutes: 5));
    expect(reads(), 2);

    // A failed read keeps the numbers shown.
    moderation.fail(#summary, ApiFailure('Offline', statusCode: 0));
    summary.start();
    await tester.pump();
    expect(summary.state?.open, 5);
    summary.pause();
  });
}
