import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import 'moderation_hex.dart';

/// How a case looks in a list and at its head (HIN-174): the glyph, the word
/// and how full of honey its cell is. Fill and glyph say the state twice, and
/// the word is always there, beside the cell or as its label.
typedef CaseLook = ({
  IconData glyph,
  String wordKey,
  double fill,
  bool dashed,
  bool urgent,
});

CaseLook caseLookOf(CaseSummary c) => switch (c.state) {
  CaseState.open => _look(LucideIcons.flag, 'open'),
  CaseState.urgent => _look(
    LucideIcons.siren,
    'urgent',
    fill: .34,
    urgent: true,
  ),
  CaseState.inReview => _look(LucideIcons.eye, 'inReview', fill: .55),
  CaseState.pendingConfirmation => _look(
    LucideIcons.usersRound,
    'pending',
    fill: .55,
  ),
  CaseState.appeal => _look(LucideIcons.rotateCcw, 'appeal', dashed: true),
  CaseState.acted when c.removed => _look(
    LucideIcons.eyeOff,
    'removed',
    fill: 1,
  ),
  CaseState.acted when c.suspended => _look(
    LucideIcons.userX,
    'suspended',
    fill: 1,
  ),
  CaseState.acted => _look(LucideIcons.clipboardCheck, 'handled'),
  CaseState.noAction => _look(LucideIcons.check, 'clear'),
};

CaseLook _look(
  IconData glyph,
  String word, {
  double fill = 0,
  bool dashed = false,
  bool urgent = false,
}) => (
  glyph: glyph,
  wordKey: 'moderation.state.$word',
  fill: fill,
  dashed: dashed,
  urgent: urgent,
);

/// The cell of case [summary], with or without its word beside it.
class CaseHex extends StatelessWidget {
  const CaseHex({
    super.key,
    required this.summary,
    this.size = 30,
    this.words = true,
  });

  final CaseSummary summary;
  final double size;
  final bool words;

  @override
  Widget build(BuildContext context) {
    final look = caseLookOf(summary);
    return ModerationHex(
      glyph: look.glyph,
      label: context.t(look.wordKey),
      fill: look.fill,
      dashed: look.dashed,
      urgent: look.urgent,
      size: size,
      words: words,
    );
  }
}

/// A kind of content in a word: Kommentar, Vorgang, Seite.
String contentKindWord(BuildContext context, ContentKind kind) =>
    context.t('moderation.kind.${kind.name}');

/// How long a case has waited, short: 40 Min., 5 Std., 3 Tg.
String caseAge(BuildContext context, Duration waited) {
  if (waited.inMinutes < 60) {
    return context.t(
      'moderation.case.age.minutes',
      count: waited.inMinutes < 1 ? 1 : waited.inMinutes,
    );
  }
  if (waited.inHours < 48) {
    return context.t('moderation.case.age.hours', count: waited.inHours);
  }
  return context.t('moderation.case.age.days', count: waited.inDays);
}

/// The same, written out for a screen reader: seit 26 Stunden, überfällig.
String caseAgeSpoken(BuildContext context, Duration waited, bool overdue) {
  final age = waited.inMinutes < 60
      ? context.t(
          'moderation.case.ageSpoken.minutes',
          count: waited.inMinutes < 1 ? 1 : waited.inMinutes,
        )
      : waited.inHours < 48
      ? context.t('moderation.case.ageSpoken.hours', count: waited.inHours)
      : context.t('moderation.case.ageSpoken.days', count: waited.inDays);
  return context.t(
    overdue ? 'moderation.case.waitedOverdue' : 'moderation.case.waited',
    variables: {'age': age},
  );
}

/// How long a case has waited, in a fixed width at the end of its row. An
/// overdue case says so with a honey wash, a different glyph and a word, so it
/// reads without its colour.
class CaseAgeChip extends StatelessWidget {
  const CaseAgeChip({super.key, required this.since, required this.now});

  final CaseSummary since;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final first = since.firstReportedAt;
    if (first == null) return const SizedBox.shrink();
    final waited = now.difference(first);
    final overdue = since.overdueAt(now);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = overdue ? AppColors.warningInk : AppColors.inkSoft;
    final age = caseAge(context, waited.isNegative ? Duration.zero : waited);
    return Semantics(
      label: caseAgeSpoken(context, waited, overdue),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: overdue
                ? AppColors.accent.withValues(alpha: dark ? .30 : .26)
                : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
              color: overdue ? AppColors.accentStrong : AppColors.hairline2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                overdue ? LucideIcons.alarmClock : LucideIcons.clock,
                size: 13,
                color: ink,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  overdue
                      ? context.t(
                          'moderation.case.overdueSince',
                          variables: {'age': age},
                        )
                      : age,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    fontWeight: FontWeight.w700,
                    color: ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet line with a glyph: what a case says about itself.
class CaseInfoLine extends StatelessWidget {
  const CaseInfoLine({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;

  /// A step offered at the end of the line, such as "Freigeben …".
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: AppColors.inkSoft),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: AppType.label,
                  height: 1.4,
                  color: AppColors.inkSoft,
                ),
              ),
              if (action != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: action),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A small heading over a part of a case, with a quiet note at its end.
class CaseSectionLabel extends StatelessWidget {
  const CaseSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.inkSoft,
            ),
          ),
      ],
    ),
  );
}
