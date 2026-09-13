/// How an entry names its author, in one place, because the timeline row and
/// the issue's work log draw the same entry and must not disagree about it.
library;

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';

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
