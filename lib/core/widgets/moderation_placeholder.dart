import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../util/dates.dart';
import 'quiet_content_line.dart';

/// What the moderation removed, as the placeholder names it (HIN-173).
enum RemovedPart {
  /// A comment or a voice message.
  content('moderation.placeholder.removed'),

  /// An issue's description.
  description('moderation.placeholder.description'),

  /// A knowledge page's content.
  page('moderation.placeholder.page');

  const RemovedPart(this.key);

  /// The i18n key of the words.
  final String key;
}

/// What stands where the moderation removed something (HIN-173): one quiet
/// line with the day it happened and, for the person it concerns, the way to
/// why. Drawn only for a removed field; a rewritten one shows its new text.
class ModerationPlaceholder extends StatelessWidget {
  const ModerationPlaceholder({
    super.key,
    this.part = RemovedPart.content,
    this.at,
    this.onWhy,
  });

  final RemovedPart part;

  /// When it was removed; the line leaves the day out without it.
  final DateTime? at;

  /// Opens the notice to the person concerned; nobody else gets the link.
  final VoidCallback? onWhy;

  @override
  Widget build(BuildContext context) {
    final at = this.at;
    final words = context.t(part.key);
    return Semantics(
      container: true,
      child: QuietContentLine(
        icon: LucideIcons.eyeOff,
        text: at == null ? words : '$words · ${recentDay(context, at)}',
        actionLabel: onWhy == null
            ? null
            : context.t('moderation.placeholder.why'),
        onAction: onWhy,
      ),
    );
  }
}
