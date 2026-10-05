import 'package:flutter/widgets.dart';

import 'i18n.dart';

extension AuditLabels on BuildContext {
  /// The label of a server `AuditAction`, e.g. `TIME_ENTRY_UPDATED`.
  ///
  /// The server names its events and the app translates them, and nothing ties
  /// the two together: a new action without a translation used to show its raw
  /// key (`audit.action.TIME_OFF_YEAR_RUN`). It now reads as the action's own
  /// words until the translation follows.
  String auditAction(String action) {
    final key = 'audit.action.$action';
    final label = t(key);
    return label == key ? humanizeAuditAction(action) : label;
  }
}

/// `TIME_OFF_YEAR_RUN` as `Time off year run`.
String humanizeAuditAction(String action) {
  final words = action.toLowerCase().split('_').where((w) => w.isNotEmpty);
  final text = words.join(' ');
  if (text.isEmpty) return action;
  return text[0].toUpperCase() + text.substring(1);
}
