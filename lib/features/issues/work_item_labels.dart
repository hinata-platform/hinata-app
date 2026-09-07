/// How an entry names its activity and its author — in one place, because both
/// the timeline row and the edit sheet draw the same entry and must not
/// disagree about what it says.
library;

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';

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
