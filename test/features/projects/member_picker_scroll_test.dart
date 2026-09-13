import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/features/projects/settings/settings_common.dart';

/// The "add members" picker lists the whole directory, so on a real workspace it
/// is always taller than the sheet it opens in.
///
/// Its list once sat in the body's `Column` without a `Flexible`. Under the
/// modal's height bound that lays the list out at its full height: the column
/// overflows, the list has no extent to scroll through — a drag bounces straight
/// back to the top — and the footer with the confirm button is pushed below the
/// sheet. On a phone nobody past the first screenful could be added at all.
///
/// Both presentations are covered, because `showGlassModal` builds a different
/// one on each side of its phone breakpoint: a Wolt bottom sheet and a card.
void main() {
  const phone = Size(402, 874);

  final directory = [
    for (var i = 1; i <= 40; i++)
      DirectoryUser(
        id: 'u$i',
        username: 'user$i',
        displayName: 'Person $i',
        title: i.isEven ? 'Referat $i' : null,
      ),
  ];

  Future<void> open(
    WidgetTester tester,
    Size size, {
    required List<DirectoryUser> people,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showMemberPicker(
                  context,
                  candidates: people,
                  projectName: 'EP26',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Whether [finder]'s widget is laid out entirely inside the window.
  bool onScreen(WidgetTester tester, Finder finder, Size size) {
    final rect = tester.getRect(finder);
    return rect.top >= 0 && rect.bottom <= size.height;
  }

  /// Space between the bottom of [above] and the footer's confirm label. The
  /// footer's own top padding plus the list's bottom padding is well under
  /// 100 points; 160 leaves room for either to grow without admitting a sheet
  /// stretched to the height of the screen (hundreds of points of gap).
  double gapToFooter(WidgetTester tester, Finder above) =>
      tester.getRect(find.text('projectSettings.add')).top -
      tester.getRect(above).bottom;

  Future<void> scrollsToTheLastPerson(WidgetTester tester, Size size) async {
    await open(tester, size, people: directory);

    expect(
      tester.takeException(),
      isNull,
      reason: 'the body must fit the modal, not overflow it',
    );
    final confirm = find.text('projectSettings.add');
    expect(confirm, findsOneWidget);
    expect(
      onScreen(tester, confirm, size),
      isTrue,
      reason: 'the footer is pinned inside the sheet, not below the fold',
    );

    final list = find.descendant(
      of: find.byType(AnimatedSwitcher),
      matching: find.byType(Scrollable),
    );
    expect(list, findsOneWidget);
    final position = tester.state<ScrollableState>(list).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'forty people do not fit one screen — the list has to scroll',
    );

    await tester.drag(list, const Offset(0, -6000));
    await tester.pumpAndSettle();

    // A fling settles within a pixel or two of the end, not on it exactly.
    expect(
      position.pixels,
      closeTo(position.maxScrollExtent, 4),
      reason: 'a list without an extent bounces back to the top instead',
    );
    final last = find.text('Person 40');
    expect(last, findsOneWidget);
    expect(onScreen(tester, last, size), isTrue);

    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.text('projectSettings.addN'), findsOneWidget);
    expect(onScreen(tester, find.text('projectSettings.addN'), size), isTrue);
    expect(tester.takeException(), isNull);
  }

  testWidgets('on a phone the sheet scrolls to the last person', (
    tester,
  ) async {
    await scrollsToTheLastPerson(tester, phone);
  });

  testWidgets('on a wide window the card scrolls to the last person', (
    tester,
  ) async {
    await scrollsToTheLastPerson(tester, const Size(1280, 800));
  });

  testWidgets('a short list shrinks the sheet instead of padding it', (
    tester,
  ) async {
    await open(tester, phone, people: directory.take(2).toList());

    expect(tester.takeException(), isNull);
    expect(gapToFooter(tester, find.text('Person 2')), lessThan(160));
  });

  testWidgets('with nobody left to add the notice sits on the footer', (
    tester,
  ) async {
    // Inside the Flexible a bare Center takes all the height it is allowed and
    // stretches the sheet to 92 % of the screen around one line of text.
    await open(tester, phone, people: const []);

    expect(tester.takeException(), isNull);
    final notice = find.text('projectSettings.everyoneMember');
    expect(notice, findsOneWidget);
    expect(gapToFooter(tester, notice), lessThan(160));
  });
}
