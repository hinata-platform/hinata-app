/// The planner's sentences that carry a number or a list (HIN-160), in one
/// place beside `shift_texts.dart`.
library;

import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';

/// A refusal in the module's words. `maxBelowAssigned` names how many are on
/// the shift already, where the server said.
String planErrorText(
  BuildContext context,
  String key, [
  Map<String, String> details = const {},
]) {
  if (key == 'error.shifts.maxBelowAssigned') {
    final assigned = int.tryParse(details['assigned'] ?? '');
    if (assigned != null) {
      return context.t('shifts.plan.maxBelowAssigned', count: assigned);
    }
  }
  return context.t(key);
}

/// "3 Personen haben jetzt eine Überschneidung", or null without warnings.
String? overlapNotice(BuildContext context, List<ShiftWarning> warnings) {
  if (warnings.isEmpty) return null;
  return context.t(
    'shifts.plan.overlaps',
    count: ShiftWarning.people(warnings),
  );
}
