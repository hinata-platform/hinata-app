import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/person_picker_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/issue_detail.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/participants/issue_participants_cubit.dart';
import 'package:hinata/features/issues/participants/share_issue_sheet.dart';

import '../../../support/recording_fake.dart';

/// The share dialog: its sections in the spec's order, a search hit that
/// shares at once, a remove button named for the person it removes, and a
/// layout that holds at twice the text size. Widget tests render raw i18n
/// keys, so the finders below look for keys.
void main() {
  const helen = IssueParticipant(
    id: 'u2',
    displayName: 'Helen Mcneilly',
    addedById: 'u1',
  );
  const rebar = DirectoryUser(
    id: 'u1',
    username: 'rebar',
    displayName: 'Rebar',
  );
  const omar = DirectoryUser(id: 'u9', username: 'omar', displayName: 'Omar');

  late FakeIssueRepository issues;
  late FakeUserRepository users;

  setUp(() {
    issues = FakeIssueRepository()
      ..answer(#participants, const [helen])
      ..answer<void>(#addParticipant, null)
      ..answer<void>(#removeParticipant, null);
    users = FakeUserRepository()
      ..answer(#searchUsers, (items: const [omar], total: 1));
  });

  Widget panel({
    double scale = 1,
    Size size = const Size(420, 900),
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => IssueParticipantsCubit(
                issues: issues,
                issueId: 'i1',
                meId: 'u1',
                members: const [rebar],
              )..load(),
            ),
            BlocProvider(create: (_) => PersonPickerCubit(users)),
          ],
          child: const ShareIssuePanel(issueKey: 'IT-145', projectName: 'IT'),
        ),
      ),
    ),
  );

  testWidgets('shows the sections in order', (tester) async {
    await tester.pumpWidget(panel());
    await tester.pump();

    final search = tester.getTopLeft(find.byType(TextField)).dy;
    final participants = tester
        .getTopLeft(find.text('issues.participants.section'))
        .dy;
    final members = tester
        .getTopLeft(find.text('issues.participants.membersSection'))
        .dy;
    final footer = tester
        .getTopLeft(find.text('issues.participants.footer'))
        .dy;

    expect(search, lessThan(participants));
    expect(participants, lessThan(members));
    expect(members, lessThan(footer));
    expect(find.text('Helen Mcneilly'), findsOneWidget);
    expect(find.text('Rebar'), findsOneWidget);
  });

  testWidgets('a search hit shares the issue with one tap', (tester) async {
    await tester.pumpWidget(panel());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'om');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.tap(find.text('Omar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    final add = issues.callTo(#addParticipant);
    expect(add.positionalArguments, ['i1', 'u9']);
  });

  testWidgets('remove is a button named for the person', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(panel());
    await tester.pump();

    final remove = find.bySemanticsLabel('issues.participants.removeOf');
    expect(remove, findsOneWidget);
    expect(
      tester
          .getSemantics(remove)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(issues.callTo(#removeParticipant).positionalArguments, ['i1', 'u2']);
    semantics.dispose();
  });

  testWidgets('holds at twice the text size on a phone', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(panel(scale: 2, size: const Size(390, 844)));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
