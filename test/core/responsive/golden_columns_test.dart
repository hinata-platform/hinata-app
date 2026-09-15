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

  test('two account columns put the time cards in the golden one', () {
    final columns = arrangeGolden(
      settingsGroups(timeTracking: true, tokens: true, admin: true),
      2,
    ).columns;

    expect(columns.first, [
      SettingsCard.notifications,
      SettingsCard.timeTracking,
      SettingsCard.availability,
    ]);
    expect(columns.last, [
      SettingsCard.security,
      SettingsCard.sessions,
      SettingsCard.access,
      SettingsCard.appearance,
      SettingsCard.tokens,
      SettingsCard.admin,
      SettingsCard.data,
      SettingsCard.danger,
    ]);
  });

  test(
    'three account columns: time, then sign-in and notifications, then the account',
    () {
      final columns = arrangeGolden(
        settingsGroups(timeTracking: true, tokens: true, admin: true),
        3,
      ).columns;

      expect(columns, [
        [SettingsCard.timeTracking, SettingsCard.availability],
        [
          SettingsCard.security,
          SettingsCard.sessions,
          SettingsCard.notifications,
        ],
        [
          SettingsCard.access,
          SettingsCard.appearance,
          SettingsCard.tokens,
          SettingsCard.admin,
          SettingsCard.data,
          SettingsCard.danger,
        ],
      ]);
    },
  );

  test('two project columns keep the wide cards in the golden one', () {
    final columns = arrangeGolden(
      projectSettingsGroups(timeTracking: true),
      2,
    ).columns;

    expect(columns.first, [
      ProjectSettingsCard.general,
      ProjectSettingsCard.workflow,
      ProjectSettingsCard.git,
    ]);
    expect(columns.last, [
      ProjectSettingsCard.members,
      ProjectSettingsCard.labels,
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
