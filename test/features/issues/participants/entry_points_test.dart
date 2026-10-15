import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/features/issues/issue_detail_sheet.dart';
import 'package:hinata/features/issues/participants/mention_access_hint.dart';
import 'package:hinata/features/issues/participants/share_issue_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The ways into the share dialog: the "…" menu for members, the note under
/// a comment that mentions somebody without access, and the refused
/// assignment. Widget tests render raw i18n keys.
void main() {
  Widget menu({void Function(Rect)? onShare, bool readOnly = false}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: IssueActionsMenu(
              onExport: (_, _) {},
              onClone: () {},
              onMove: () {},
              onDelete: () {},
              canDelete: false,
              archived: false,
              onShare: onShare,
              readOnly: readOnly,
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.ellipsis));
    await tester.pumpAndSettle();
  }

  testWidgets('members find "Share with …" and it opens at the menu', (
    tester,
  ) async {
    Rect? opened;
    await tester.pumpWidget(menu(onShare: (anchor) => opened = anchor));
    await open(tester);

    expect(find.text('issues.participants.menu'), findsOneWidget);
    expect(find.text('issues.clone.action'), findsOneWidget);

    await tester.tap(find.text('issues.participants.menu'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, isNotNull);
  });

  testWidgets('a participant sees only export (and watch when loaded)', (
    tester,
  ) async {
    await tester.pumpWidget(menu(onShare: (_) {}, readOnly: true));
    await open(tester);

    expect(find.text('issues.export.action'), findsOneWidget);
    expect(find.text('issues.participants.menu'), findsNothing);
    expect(find.text('issues.clone.action'), findsNothing);
    expect(find.text('issues.move.action'), findsNothing);
    expect(find.text('issues.archive'), findsNothing);
  });

  testWidgets('no share entry for a caller who may not share', (tester) async {
    await tester.pumpWidget(menu());
    await open(tester);

    expect(find.text('issues.participants.menu'), findsNothing);
  });

  group('the mention note', () {
    Widget hint(
      TextEditingController controller, {
      Map<String, bool> known = const {'u1': true, 'u2': false},
      Set<String> blocked = const {},
      void Function(String)? onShare,
    }) => MaterialApp(
      home: Scaffold(
        body: MentionAccessHint(
          controller: controller,
          known: known,
          blockedAmong: (ids) async => blocked,
          nameOf: (id) =>
              {'u1': 'Rebar', 'u2': 'Helen', 'u3': 'Omar'}[id] ?? '',
          onShare: (id, name) async => onShare?.call(id),
        ),
      ),
    );

    testWidgets('says nothing about a member', (tester) async {
      final draft = TextEditingController(text: 'hi {{user:u1}}');
      await tester.pumpWidget(hint(draft));

      expect(find.text('issues.participants.mentionHint'), findsNothing);
    });

    testWidgets('names somebody without access and offers to share', (
      tester,
    ) async {
      String? shared;
      final draft = TextEditingController(text: 'hi ');
      await tester.pumpWidget(hint(draft, onShare: (id) => shared = id));

      draft.text = 'hi {{user:u2}} ';
      await tester.pumpAndSettle();
      expect(find.text('issues.participants.mentionHint'), findsOneWidget);

      await tester.tap(find.text('issues.participants.share'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(shared, 'u2');
    });

    testWidgets('asks about people the detail does not know', (tester) async {
      final draft = TextEditingController(text: 'see {{user:u3}}');
      await tester.pumpWidget(hint(draft, blocked: {'u3'}));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('issues.participants.mentionHint'), findsOneWidget);
    });

    testWidgets('goes when the mention is deleted', (tester) async {
      final draft = TextEditingController(text: 'hi {{user:u2}}');
      await tester.pumpWidget(hint(draft));
      expect(find.text('issues.participants.mentionHint'), findsOneWidget);

      draft.text = 'hi ';
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('issues.participants.mentionHint'), findsNothing);
    });

    test('finds each mentioned id once', () {
      expect(
        mentionedUserIds('{{user:a}} x {{user:b}} {{user:a}} {{issue:K-1}}'),
        ['a', 'b'],
      );
    });
  });

  test('a refused assignment names whom it refused', () {
    expect(
      refusedAssigneeId(
        ApiFailure(
          'no',
          details: const {'reason': 'assigneeNoAccess', 'userIds': 'u7,u8'},
        ),
      ),
      'u7',
    );
    expect(refusedAssigneeId(ApiFailure('other')), isNull);
  });
}
