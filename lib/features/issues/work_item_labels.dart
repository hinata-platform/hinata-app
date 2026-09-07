/// How an entry names its activity and its author — in one place, because both
/// the timeline row and the edit sheet draw the same entry and must not
/// disagree about what it says.
library;

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';

/// The six activity types the product has always had, in the order every
/// picker offers them.
///
/// Here rather than beside one of the two sheets that show them: the 1.x work
/// log and the module's entry editor are two forms over the same field, and a
/// list that drifted would put an activity in one that the other cannot select.
const workItemActivities = [
  'Development',
  'Testing',
  'Documentation',
  'Design',
  'Meeting',
  'Support',
];

/// The list to offer for an entry whose activity is [current] — the six above,
/// plus [current] itself when it is not one of them. An MCP client or the API
/// may have set something else, and a picker that silently omitted it would
/// show six unselected chips and no sign of what the entry actually says.
List<String> workItemActivityChoices(String? current) => [
  ...workItemActivities,
  if (current != null && !workItemActivities.contains(current)) current,
];

/// The activity's translated name, or the raw value for one the bundle does
/// not know — an MCP client may send its own.
String activityLabel(BuildContext context, String activity) {
  final key = 'time.activity.${activity.toLowerCase()}';
  final label = context.t(key);
  return label == key ? activity : label;
}

/// Who the entry is credited to: the person's name, the legacy label for the
/// pre-2.0 remainder, and "deleted user" for an id the directory no longer
/// answers to — never a raw id.
String workItemPersonLabel(
  BuildContext context,
  WorkItem item,
  String? Function(String userId) nameFor,
) {
  if (item.isLegacy) return context.t('time.legacySource');
  final userId = item.userId;
  if (userId == null) return context.t('time.deletedUser');
  return nameFor(userId) ?? context.t('time.deletedUser');
}
