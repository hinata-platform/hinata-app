import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/issues/issue_links_section.dart';
import 'package:hinata/features/issues/participants/participant_banner.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../issue_fixtures.dart';
import '../../../support/recording_fake.dart';

/// What somebody an issue is shared with sees: the band that says so with the
/// way out, and links they can follow but not change. Raw i18n keys render.
void main() {
  group('the participant band', () {
    Widget band({double scale = 1, VoidCallback? onLeave}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: ParticipantBanner(projectName: 'IT', onLeave: onLeave ?? () {}),
        ),
      ),
    );

    testWidgets('says what the participant may do and offers to leave', (
      tester,
    ) async {
      var left = false;
      await tester.pumpWidget(band(onLeave: () => left = true));

      expect(find.text('issues.participants.banner'), findsOneWidget);
      expect(
        tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('issues.participants.leave'));
      expect(left, isTrue);
    });

    testWidgets('holds at twice the text size', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(band(scale: 2));

      expect(tester.takeException(), isNull);
    });
  });

  group('links for a reader', () {
    late FakeIssueRepository issues;

    setUp(() {
      issues = FakeIssueRepository()
        ..answer<Stream<List<int>>>(
          #issueLinkEventStream,
          const Stream<List<int>>.empty(),
        )
        ..answer(#issueLinks, [
          IssueLink(
            id: 'l1',
            type: 'RELATES',
            outward: true,
            verb: 'relates to',
            issue: testIssue('i2'),
          ),
        ]);
    });

    Widget links({required bool readOnly}) => MaterialApp(
      home: Scaffold(
        body: RepositoryProvider<IssueRepository>.value(
          value: issues,
          child: SingleChildScrollView(
            child: IssueLinksSection(
              issueId: 'i1',
              projectId: 'p1',
              project: null,
              userNames: const {},
              userAvatars: const {},
              readOnly: readOnly,
            ),
          ),
        ),
      ),
    );

    testWidgets('can be followed but not added or removed', (tester) async {
      await tester.pumpWidget(links(readOnly: true));
      await tester.pump();
      await tester.pump();

      expect(find.text('HIN-1'), findsWidgets);
      expect(find.text('issues.links.add'), findsNothing);
      expect(find.byIcon(LucideIcons.unlink), findsNothing);
    });

    testWidgets('members still add and remove', (tester) async {
      await tester.pumpWidget(links(readOnly: false));
      await tester.pump();
      await tester.pump();

      expect(find.text('issues.links.add'), findsOneWidget);
      expect(find.byIcon(LucideIcons.unlink), findsOneWidget);
    });
  });
}
