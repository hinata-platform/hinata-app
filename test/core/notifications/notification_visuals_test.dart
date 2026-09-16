import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/notifications/notification_visuals.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The time notifications arrive in the bell like any other, and each has a
/// face of its own. Without a case here they fell to the plain bell, and a
/// budget alert looked like a digest.
void main() {
  const time = [
    'TIME_TARGET_REMINDER',
    'TIME_BUDGET_ALERT',
    'TIME_ESTIMATE_REACHED',
    'TIME_TIMER_AUTO_STOPPED',
    'TIMESHEET_SUBMITTED',
    'TIMESHEET_APPROVED',
    'TIMESHEET_REJECTED',
    'TIMESHEET_REOPENED',
    'TIME_CORRECTION_REQUESTED',
    'TIME_CORRECTION_ANSWERED',
    'TIME_BACKFILL_REQUESTED',
  ];

  test('every time notification has an icon of its own', () {
    for (final type in time) {
      expect(
        notificationVisual(type).$1,
        isNot(LucideIcons.bell),
        reason: type,
      );
    }
  });

  test('a reminder and an alert look different', () {
    expect(
      notificationVisual('TIME_TARGET_REMINDER').$1,
      isNot(notificationVisual('TIME_BUDGET_ALERT').$1),
    );
    expect(notificationVisual('time_budget_alert').$1, LucideIcons.gauge);
  });
}
