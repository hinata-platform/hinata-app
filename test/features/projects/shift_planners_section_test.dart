import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/notifications/notification_visuals.dart';
import 'package:hinata/features/projects/settings/project_settings_layout.dart';
import 'package:hinata/features/projects/settings/shifts_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shifts/shift_fakes.dart';

/// Project settings → Schichtplanung (HIN-45): the planners by name, the line
/// that leads always plan, and the section only where the module is on.
void main() {
  test('the section is on the page only with the module', () {
    expect(
      projectSettingsSections(timeTracking: false, templates: false),
      isNot(contains(ProjectSettingsCard.shifts)),
    );
    expect(
      projectSettingsSections(
        timeTracking: false,
        templates: false,
        shifts: true,
      ),
      contains(ProjectSettingsCard.shifts),
    );
    expect(
      projectSettingsGroups(
        timeTracking: false,
        templates: false,
        shifts: true,
      ).expand((g) => g.cards),
      contains(ProjectSettingsCard.shifts),
    );
  });

  test('shift notifications share one glyph', () {
    expect(notificationVisual('SHIFT_ASSIGNED').$1, LucideIcons.calendarClock);
    expect(notificationVisual('SHIFT_REMINDER').$1, LucideIcons.calendarClock);
  });

  testWidgets('names the planners and says that leads always plan', (
    tester,
  ) async {
    final repo = FakeShiftRepository()
      ..plannerList = const ShiftPlanners(
        planners: [ShiftPlanner(userId: 'u1')],
        users: {'u1': ShiftUser(name: 'Lena Vogt')},
      );
    await pumpShiftsUi(
      tester,
      const ShiftPlannersSection(
        projectId: 'p1',
        projectName: 'Sommerfest',
        members: [
          DirectoryUser(id: 'u1', username: 'lena', displayName: 'Lena Vogt'),
          DirectoryUser(id: 'u2', username: 'mei', displayName: 'Mei Lin'),
        ],
        leadIds: ['lead'],
      ),
      repository: repo,
      width: 800,
    );
    await tester.pump();

    expect(find.text('Schichtplanung'), findsOneWidget);
    expect(find.text('Lena Vogt'), findsOneWidget);
    expect(find.text('Planer hinzufügen'), findsOneWidget);
    expect(find.text('Leads und Team-Admins planen immer.'), findsOneWidget);
    expect(find.byTooltip('Lena Vogt als Planer entfernen'), findsOneWidget);
    expect(repo.calls, ['planners:p1']);
  });
}
