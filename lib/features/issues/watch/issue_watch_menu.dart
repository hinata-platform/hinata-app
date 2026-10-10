import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_widgets.dart';
import 'issue_watch_cubit.dart';

/// Everything the issue's watch submenu needs: the cubit holding the roster,
/// who is asking, and how to resolve the people on it.
///
/// The lookups are functions rather than snapshots on purpose. The detail
/// aggregate ships only the users an issue *references* — watchers are hydrated
/// with the rest of the directory after first paint, and a map captured when
/// the top bar was built would leave the roster showing raw ids.
class IssueWatchMenuData {
  const IssueWatchMenuData({
    required this.cubit,
    required this.issue,
    required this.onToggle,
    required this.nameFor,
    required this.avatarFor,
    required this.pronounsFor,
  });

  final IssueWatchCubit cubit;

  /// The issue being watched — read for the implicit-notification hint below.
  final Issue issue;

  /// Subscribes or unsubscribes the caller. The host owns the outcome: the flip
  /// here is optimistic, so only it can say the server actually took it.
  final VoidCallback onToggle;

  final String? Function(String userId) nameFor;
  final String? Function(String userId) avatarFor;
  final String? Function(String userId) pronounsFor;

  /// The signed-in user, or null while the session is still resolving — taken
  /// from the cubit so the roster and the toggle can never disagree on who
  /// "you" is.
  String? get meId => cubit.userId;

  /// Why the toggle can read "start watching" while mail already arrives:
  /// assignees and the reporter are notified without ever subscribing.
  String? get implicitHintKey {
    final me = meId;
    if (me == null) return null;
    if (issue.assigneeIds.contains(me) || issue.assigneeId == me) {
      return 'issues.watch.implicitAssignee';
    }
    if (issue.reporterId == me) return 'issues.watch.implicitReporter';
    return null;
  }
}

/// The "Watch" row in the issue's "…" menu. It opens a submenu card over the
/// menu: the one action (start or stop watching), the note that says why mail
/// may already arrive without it, and who is watching. The row's glyph still
/// carries the current state, so the menu answers "am I watching this?"
/// without the card being opened.
///
/// Built from [state] when the anchor builds — the host rebuilds the anchor on
/// every roster change, so the card shows the roster as it is when the menu
/// opens. Choosing the action reports [toggleValue]; the host toggles and says
/// how it went, since the menu is gone by then.
GlassMenuItem<T> issueWatchMenuItem<T>(
  BuildContext context, {
  required T toggleValue,
  required IssueWatchMenuData data,
  required IssueWatchState state,
}) {
  final me = data.meId;
  final watching = state.isWatchedBy(me);
  final hintKey = data.implicitHintKey;
  // "You" first, then everyone else in server order.
  final ordered = [
    if (me != null && state.watcherIds.contains(me)) me,
    for (final id in state.watcherIds)
      if (id != me) id,
  ];
  return GlassMenuItem<T>(
    value: toggleValue,
    label: context.t('issues.watch.title'),
    // Nobody to subscribe before the session resolves.
    enabled: me != null,
    leading: Icon(
      watching ? LucideIcons.eye : LucideIcons.eyeOff,
      size: 16,
      color: watching ? AppColors.accentInk : AppColors.inkSoft,
    ),
    submenu: [
      GlassMenuItem<T>(
        value: toggleValue,
        label: context.t(watching ? 'issues.watch.stop' : 'issues.watch.start'),
        leading: Icon(
          watching ? LucideIcons.eyeOff : LucideIcons.eye,
          size: 16,
          color: AppColors.accentInk,
        ),
      ),
      if (hintKey != null)
        GlassMenuNote<T>(
          label: context.t(hintKey),
          leading: Icon(LucideIcons.info, size: 13, color: AppColors.inkFaint),
          caption: true,
        ),
      GlassMenuNote<T>(
        label: context.t('issues.watch.watchersTitle'),
        caption: true,
        dividerAbove: true,
      ),
      if (ordered.isEmpty)
        GlassMenuNote<T>(
          label: context.t('issues.watch.noWatchers'),
          caption: true,
        )
      else
        for (final id in ordered)
          _watcherNote<T>(context, data: data, id: id, isMe: id == me),
    ],
  );
}

/// One person on the roster, the avatar in the slot a row's glyph sits in.
GlassMenuNote<T> _watcherNote<T>(
  BuildContext context, {
  required IssueWatchMenuData data,
  required String id,
  required bool isMe,
}) {
  // Watchers are the one group the detail aggregate does not ship users for,
  // so the directory may not have resolved them (yet, or ever, for a
  // deactivated account). An id is not a name — the avatar still takes it,
  // where it renders as a neutral glyph.
  final name = data.nameFor(id);
  final label = name ?? context.t('issues.watch.unknownWatcher');
  return GlassMenuNote<T>(
    label: isMe ? '$label · ${context.t('issues.watch.you')}' : label,
    leading: HiveAvatar(
      name: name ?? id,
      imageUrl: data.avatarFor(id),
      pronouns: data.pronounsFor(id),
      size: 24,
    ),
  );
}
