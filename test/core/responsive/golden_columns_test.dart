import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/golden_columns.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:hinata/features/projects/settings/project_settings_layout.dart';

/// Cards spread over golden columns: every card once, groups kept together,
/// and the columns about level at every width, on the project settings page.
void main() {
  test(
    'one column below the medium breakpoint, three from the reading width',
    () {
      expect(goldenColumnCount(Breakpoints.mediumMax - 1), 1);
      expect(goldenColumnCount(Breakpoints.mediumMax), 2);
      expect(goldenColumnCount(Breakpoints.readingWidth - 1), 2);
      expect(goldenColumnCount(Breakpoints.readingWidth), 3);
    },
  );

  test('a lead group opens the golden column however light it is', () {
    final groups = [
      const GoldenGroup(['tall'], weight: 20),
      const GoldenGroup(['other'], weight: 6),
      const GoldenGroup(['hero'], weight: 1, lead: true),
    ];

    for (final columns in [2, 3]) {
      expect(arrangeGolden(groups, columns).columns.first.first, 'hero');
    }
  });

  test('one column keeps the order the page declares', () {
    final groups = projectSettingsGroups(timeTracking: true, templates: false);

    expect(
      arrangeGolden(groups, 1).columns.single,
      groups.expand((group) => group.cards).toList(),
    );
  });

  void expectLevel<T>(List<GoldenGroup<T>> groups, String page) {
    for (final columns in [2, 3]) {
      final arrangement = arrangeBalanced(groups, columns);
      final cards = arrangement.columns.expand((column) => column).toList();
      expect(
        cards.toSet().length,
        cards.length,
        reason: '$page/$columns: a card twice',
      );
      expect(
        cards.toSet(),
        groups.expand((group) => group.cards).toSet(),
        reason: '$page/$columns: a card missing',
      );
      for (final group in groups) {
        final holding = arrangement.columns.where(
          (column) => column.contains(group.cards.first),
        );
        expect(
          holding.single.toSet().containsAll(group.cards),
          isTrue,
          reason: '$page/$columns: ${group.cards} split',
        );
      }
      expect(
        spreadOf(arrangement.loads),
        lessThanOrEqualTo(levelEnough),
        reason: '$page/$columns: ${arrangement.loads}',
      );
    }
  }

  test(
    'the project settings end about level with and without time tracking',
    () {
      expectLevel(
        projectSettingsGroups(timeTracking: true, templates: false),
        'project time',
      );
      expectLevel(
        projectSettingsGroups(timeTracking: false, templates: false),
        'project',
      );
    },
  );

  test('a page too short for three columns keeps two on a wide screen', () {
    final groups = projectSettingsGroups(timeTracking: false, templates: false);

    // Three columns would leave the third half empty beside two long ones.
    expect(spreadOf(arrangeGolden(groups, 3).loads), greaterThan(levelEnough));
    expect(arrangeBalanced(groups, 3).columns, hasLength(2));
  });

  test('the first column is the golden one', () {
    final arrangement = arrangeGolden(
      projectSettingsGroups(timeTracking: true, templates: false),
      3,
    );

    expect(arrangement.flex, [1618, 1000, 1000]);
  });

  test('two project columns: General opens the page, whatever else moves', () {
    final columns = arrangeGolden(
      projectSettingsGroups(timeTracking: true, templates: false),
      2,
    ).columns;

    expect(columns.first, [
      ProjectSettingsCard.general,
      ProjectSettingsCard.git,
      ProjectSettingsCard.timeTracking,
    ]);
    expect(columns.last, [
      ProjectSettingsCard.members,
      ProjectSettingsCard.labels,
      ProjectSettingsCard.workflow,
      ProjectSettingsCard.archive,
      ProjectSettingsCard.danger,
    ]);
  });

  test('General leads whether or not the time card is there', () {
    // The lead is the one position on the page somebody can rely on, so it must
    // not depend on which optional cards the instance happens to show.
    for (final timeTracking in [true, false]) {
      for (final columns in [2, 3]) {
        final arrangement = arrangeGolden(
          projectSettingsGroups(timeTracking: timeTracking, templates: false),
          columns,
        );
        expect(
          arrangement.columns.first.first,
          ProjectSettingsCard.general,
          reason: 'timeTracking=$timeTracking, columns=$columns',
        );
      }
    }
  });

  test('the template card does not unseat General or unbalance the page', () {
    // It is short — a date, a switch and a button — so it rides with whichever
    // column has room. What it must not do is take the lead position or leave
    // one column towering over the others.
    for (final columns in [2, 3]) {
      final arrangement = arrangeGolden(
        projectSettingsGroups(timeTracking: true, templates: true),
        columns,
      );
      expect(
        arrangement.columns.first.first,
        ProjectSettingsCard.general,
        reason: 'columns=$columns',
      );
      expect(
        arrangement.columns.expand((column) => column),
        contains(ProjectSettingsCard.templates),
      );
    }
    expectLevel(
      projectSettingsGroups(timeTracking: true, templates: true),
      'project templates',
    );
  });
}
