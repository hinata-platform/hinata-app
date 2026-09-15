import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/golden_columns.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:hinata/features/account/settings_layout.dart';
import 'package:hinata/features/projects/settings/project_settings_layout.dart';

/// Cards spread over golden columns: every card once, groups kept together,
/// and the columns about level at every width, on both settings pages.
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
    final groups = projectSettingsGroups(timeTracking: true);

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

  test('the account settings end about level in every combination', () {
    for (final time in [true, false]) {
      for (final extras in [true, false]) {
        expectLevel(
          settingsGroups(timeTracking: time, tokens: extras, admin: extras),
          'account time=$time extras=$extras',
        );
      }
    }
  });

  test(
    'the project settings end about level with and without time tracking',
    () {
      expectLevel(projectSettingsGroups(timeTracking: true), 'project time');
      expectLevel(projectSettingsGroups(timeTracking: false), 'project');
    },
  );

  test('the two time cards share the load instead of one column', () {
    final groups = settingsGroups(
      timeTracking: true,
      tokens: true,
      admin: true,
    );
    for (final count in [2, 3]) {
      final columns = arrangeGolden(groups, count).columns;
      int columnOf(SettingsCard card) =>
          columns.indexWhere((column) => column.contains(card));

      expect(
        columnOf(SettingsCard.timeTracking),
        isNot(columnOf(SettingsCard.availability)),
        reason: '$count columns',
      );
    }
  });

  test('two project columns: the longest card opens the golden one', () {
    final columns = arrangeGolden(
      projectSettingsGroups(timeTracking: true),
      2,
    ).columns;

    expect(columns.first, [
      ProjectSettingsCard.general,
      ProjectSettingsCard.members,
      ProjectSettingsCard.labels,
      ProjectSettingsCard.git,
    ]);
    expect(columns.last, [
      ProjectSettingsCard.workflow,
      ProjectSettingsCard.timeTracking,
      ProjectSettingsCard.archive,
      ProjectSettingsCard.danger,
    ]);
  });

  test('a page too short for three columns keeps two on a wide screen', () {
    final groups = projectSettingsGroups(timeTracking: false);

    // Three columns would leave the third half empty beside two long ones.
    expect(spreadOf(arrangeGolden(groups, 3).loads), greaterThan(levelEnough));
    expect(arrangeBalanced(groups, 3).columns, hasLength(2));
  });

  test('the first column is the golden one', () {
    final arrangement = arrangeGolden(
      projectSettingsGroups(timeTracking: true),
      3,
    );

    expect(arrangement.flex, [1618, 1000, 1000]);
  });
}
